#!/bin/sh
set -eu

if [ -z "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]; then
  echo "ERROR: Set the CLOUDFLARE_TUNNEL_TOKEN egg variable before starting this server."
  exit 1
fi

# Keep the upstream container's mutable work files in Pterodactyl's writable
# server directory. The Dockerfile symlinks Tomcat's work path here.
mkdir -p /home/container/work/cache /home/container/work/files \
  /home/container/work/plugins /home/container/work/logs

# cloudflared can log its environment-variable names and values. Put the token
# in a private file, remove it from the environment, then use --token-file.
TOKEN_FILE=/home/container/.cloudflared-token
umask 077
printf '%s' "$CLOUDFLARE_TUNNEL_TOKEN" > "$TOKEN_FILE"
unset CLOUDFLARE_TUNNEL_TOKEN

cloudflared tunnel --no-autoupdate run --token-file "$TOKEN_FILE" &
TUNNEL_PID=$!

/docker-entrypoint.sh &
HMDM_PID=$!

terminate() {
  kill "$TUNNEL_PID" "$HMDM_PID" 2>/dev/null || true
  wait "$TUNNEL_PID" "$HMDM_PID" 2>/dev/null || true
  rm -f "$TOKEN_FILE"
}
trap terminate INT TERM EXIT

while kill -0 "$TUNNEL_PID" 2>/dev/null && kill -0 "$HMDM_PID" 2>/dev/null; do
  sleep 2
done

if ! kill -0 "$HMDM_PID" 2>/dev/null; then
  STATUS=0
  wait "$HMDM_PID" || STATUS=$?
  kill "$TUNNEL_PID" 2>/dev/null || true
  wait "$TUNNEL_PID" 2>/dev/null || true
  exit "$STATUS"
fi

STATUS=0
wait "$TUNNEL_PID" || STATUS=$?
kill "$HMDM_PID" 2>/dev/null || true
wait "$HMDM_PID" 2>/dev/null || true
exit "$STATUS"