#!/bin/sh
set -eu

if [ -z "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]; then
  echo "ERROR: Set the CLOUDFLARE_TUNNEL_TOKEN egg variable before starting this server."
  exit 1
fi

# Bind the HTTP Connector to Pterodactyl's primary allocation. Wings maps
# that allocated port onto the same port inside the container.
SERVER_PORT=${SERVER_PORT:-8080}
case "$SERVER_PORT" in
  ''|*[!0-9]*) echo "ERROR: SERVER_PORT must be a numeric allocation port."; exit 1 ;;
esac
if [ "$SERVER_PORT" -lt 1 ] || [ "$SERVER_PORT" -gt 65535 ]; then
  echo "ERROR: SERVER_PORT must be between 1 and 65535."
  exit 1
fi

# Persist Tomcat's mutable files under Pterodactyl's writable server directory.
mkdir -p /home/container/headwind/work/cache /home/container/headwind/work/files \
  /home/container/headwind/work/plugins /home/container/headwind/work/logs \
  /home/container/headwind/webapps /home/container/headwind/config \
  /home/container/headwind/tmp

# Java ImageIO (including Headwind's QR PNG generation) needs writable temp
# storage. Tomcat otherwise defaults to /usr/local/tomcat/temp on the readonly
# container filesystem.
export CATALINA_TMPDIR=/home/container/headwind/tmp
JAVA_OPTS="${JAVA_OPTS:-} -Djava.io.tmpdir=${CATALINA_TMPDIR}"
export JAVA_OPTS

# Generate a writable Tomcat config from the upstream image template every boot,
# replacing its fixed HTTP port (8080) with the server's assigned allocation.
sed "s/port=\"8080\"/port=\"${SERVER_PORT}\"/" \
  /opt/headwind-ptero-defaults/server.xml > /home/container/headwind/server.xml

# Restore bundled webapp defaults into the writable path on a fresh server.
if [ -d /opt/headwind-ptero-defaults/webapps ] && [ -z "$(ls -A /home/container/headwind/webapps 2>/dev/null || true)" ]; then
  cp -a /opt/headwind-ptero-defaults/webapps/. /home/container/headwind/webapps/
fi

# Upstream's readiness psql command omits -p, so honor the egg's SQL_PORT via
# libpq's PGPORT. The ROOT.xml template also substitutes SQL_PORT directly.
export PGPORT="${SQL_PORT:-5432}"

# cloudflared can log its environment. Store the token privately, then remove
# it from the environment before launching cloudflared.
TOKEN_FILE=/home/container/.cloudflared-token
umask 077
printf '%s' "$CLOUDFLARE_TUNNEL_TOKEN" > "$TOKEN_FILE"
unset CLOUDFLARE_TUNNEL_TOKEN

# HTTP/2 uses outbound TCP 7844. QUIC requires UDP 7844; forcing HTTP/2 avoids
# QUIC retries where UDP is blocked (TCP 7844 must still be allowed).
cloudflared tunnel --no-autoupdate --protocol http2 run --token-file "$TOKEN_FILE" &
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
