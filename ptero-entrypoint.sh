#!/bin/sh
set -eu

if [ -z "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]; then
  echo "ERROR: Set the CLOUDFLARE_TUNNEL_TOKEN egg variable before starting this server."
  exit 1
fi

# cloudflared must be reaped if the Headwind process exits, and vice versa.
cloudflared tunnel --no-autoupdate run --token "$CLOUDFLARE_TUNNEL_TOKEN" &
TUNNEL_PID=$!

/docker-entrypoint.sh &
HMDM_PID=$!

terminate() {
  kill "$TUNNEL_PID" "$HMDM_PID" 2>/dev/null || true
  wait "$TUNNEL_PID" "$HMDM_PID" 2>/dev/null || true
}
trap terminate INT TERM

while kill -0 "$TUNNEL_PID" 2>/dev/null && kill -0 "$HMDM_PID" 2>/dev/null; do
  sleep 2
done

if ! kill -0 "$HMDM_PID" 2>/dev/null; then
  wait "$HMDM_PID" || STATUS=$?
  STATUS=${STATUS:-1}
  kill "$TUNNEL_PID" 2>/dev/null || true
  wait "$TUNNEL_PID" 2>/dev/null || true
  exit "$STATUS"
fi

wait "$TUNNEL_PID" || STATUS=$?
STATUS=${STATUS:-1}
kill "$HMDM_PID" 2>/dev/null || true
wait "$HMDM_PID" 2>/dev/null || true
exit "$STATUS"
