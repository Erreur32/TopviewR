#!/usr/bin/env bash
# Local test server: builds the image from this tree, starts btop-web-local (hardened compose + docker-compose.local.yml),
# waits for the healthcheck, then follows the container logs. Ctrl+C stops the container.
#
#   scripts/dev.sh           build if needed, start, follow logs ; Ctrl+C stops the container
#   scripts/dev.sh --build   force a rebuild (after a Dockerfile or script change)
#   scripts/dev.sh --keep    leave the container running when the logs stop
#   scripts/dev.sh --stop    stop and remove the container, then leave
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
NAME=btop-web-local
dc() { docker compose -f docker-compose.yaml -f docker-compose.local.yml "$@"; }
healthy() { [[ $(docker inspect -f '{{.State.Health.Status}}' "$NAME" 2>/dev/null) == healthy ]]; }
envval() { sed -n "s/^$1=//p" .env 2>/dev/null | head -1; }

recreate=() keep=0
for a in "$@"; do
  case $a in
    --build) recreate=(--force-recreate) ;;
    --keep) keep=1 ;;
    --stop) dc down; exit 0 ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) echo "unknown option: $a (see --help)" >&2; exit 2 ;;
  esac
done
[[ -f .env ]] || { echo "no .env: cp .env.example .env and set BTOP_PASS" >&2; exit 1; }

IP=$(hostname -I 2>/dev/null | awk '{print $1}')
PORT=$(envval BTOP_PORT); PORT=${PORT:-7682}
[[ $(envval BTOP_TLS) == off ]] && SCHEME=http || SCHEME=https
URL="$SCHEME://${IP:-localhost}:$PORT/"

dc up -d --build "${recreate[@]}"

echo -n "▸ waiting for the healthcheck"
for _ in $(seq 1 60); do
  healthy && break
  echo -n .; sleep 1
done
healthy || { echo " not healthy: docker logs $NAME" >&2; exit 1; }
echo " ok"

[[ $keep = 0 ]] && trap 'echo; echo "▸ stopping the test server…"; dc stop >/dev/null 2>&1 || true' EXIT
echo "▸ btop in the browser: $URL"
USER_NAME=$(envval BTOP_USER)
echo "▸ login: ${USER_NAME:-admin}, password: BTOP_PASS in .env"
echo "▸ STOP: Ctrl+C$([[ $keep = 0 ]] && echo " (stops the container)")"
echo
# hide libwebsockets internals and the healthcheck's own requests (127.0.0.1 every 30 s)
docker logs -f --tail 50 "$NAME" 2>&1 \
  | grep --line-buffered -vE '__lws_lc_(un)?tag|lws_gate_accepts|GOAWAY|HTTP / - 127\.0\.0\.1$|N:   |libwebsockets-evlib|lws_create_context|elops_init|Vhost .default.|lws_socket_bind|ttyd [0-9.]+ \(libwebsockets|tty configuration:|start command:|cert_lifetime'
