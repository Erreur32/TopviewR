#!/bin/sh
# End-to-end tests for the image: ./tests/test.sh [image]
set -eu
IMG="${1:-topviewr:dev}"
PASS="test-$(head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n')"
PORT=17681
NAME=btop-test-$$
CERTS="$(mktemp -d)"
fails=0

ok()   { echo "  OK   $*"; }
ko()   { echo "  FAIL $*"; fails=$((fails + 1)); }
check() { if [ "$2" = "$3" ]; then ok "$1"; else ko "$1 (expected $3, got $2)"; fi; }
refused() { case "$2" in 200|101) ko "$1 (got $2)" ;; *) ok "$1 ($2)" ;; esac; }
code() { curl -sk -o /dev/null -m 4 -w '%{http_code}' "$@" || true; }
cleanup() { docker rm -f "$NAME" >/dev/null 2>&1 || true; rm -rf "$CERTS"; }
trap cleanup EXIT
start() { cleanup; mkdir -p "$CERTS"; docker run -d --name "$NAME" -p "127.0.0.1:$PORT:7681" "$@" "$IMG" >/dev/null; sleep 2; }
ws() { # $1 = scheme, $2 = Origin; prints the HTTP code of the WebSocket handshake
	curl -sk -o /dev/null -m 3 -w '%{http_code}' -u "admin:$PASS" \
		-H 'Connection: Upgrade' -H 'Upgrade: websocket' -H 'Sec-WebSocket-Version: 13' \
		-H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' -H 'Sec-WebSocket-Protocol: tty' \
		-H "Origin: $2" "$1://127.0.0.1:$PORT/ws" || true
}

echo "== Refuses to start"
docker run --rm "$IMG" >/dev/null 2>&1 && ko "without password" || ok "without password"
docker run --rm -e BTOP_PASS=short "$IMG" >/dev/null 2>&1 && ko "short password" || ok "short password"

echo "== HTTP + auth (BTOP_* variables)"
start -e BTOP_PASS="$PASS"
check "no credentials -> 401" "$(code "http://127.0.0.1:$PORT/")" 401
check "wrong password -> 401" "$(code -u admin:wrong "http://127.0.0.1:$PORT/")" 401
check "valid credentials -> 200" "$(code -u "admin:$PASS" "http://127.0.0.1:$PORT/")" 200
check "WebSocket same origin -> 101" "$(ws http "http://127.0.0.1:$PORT")" 101
refused "WebSocket other origin refused" "$(ws http http://evil.example)"
docker logs "$NAME" 2>&1 | grep -q "$PASS" && ko "password not in logs" || ok "password not in logs"
t0=$(date +%s); docker stop "$NAME" >/dev/null; t=$(( $(date +%s) - t0 ))
[ "$t" -le 3 ] && ok "docker stop in ${t}s" || ko "docker stop too slow (${t}s)"

echo "== GOTTY_* compatibility"
start -e GOTTY_AUTH_ENABLED=true -e GOTTY_AUTH_USER=admin -e GOTTY_AUTH_PASS="$PASS"
check "GOTTY_*: valid credentials -> 200" "$(code -u "admin:$PASS" "http://127.0.0.1:$PORT/")" 200
check "GOTTY_*: no credentials -> 401" "$(code "http://127.0.0.1:$PORT/")" 401
start -e GOTTY_AUTH_USER=admin -e GOTTY_AUTH_PASS=short
check "GOTTY_* short password: starts (warning)" "$(code -u admin:short "http://127.0.0.1:$PORT/")" 200

echo "== TLS auto"
start -e BTOP_PASS="$PASS" -e BTOP_TLS=auto -v "$CERTS:/certs"
check "HTTPS valid credentials -> 200" "$(code -u "admin:$PASS" "https://127.0.0.1:$PORT/")" 200
refused "plain HTTP not served" "$(code -u "admin:$PASS" "http://127.0.0.1:$PORT/")"
[ -s "$CERTS/cert.pem" ] && ok "certificate written to /certs" || ko "certificate missing"
sum1="$(cat "$CERTS/cert.pem" | sha256sum)"; docker restart "$NAME" >/dev/null; sleep 2
check "certificate kept across restart" "$(cat "$CERTS/cert.pem" | sha256sum)" "$sum1"
check "healthcheck over HTTPS" "$(docker exec "$NAME" /usr/local/bin/healthcheck.sh >/dev/null 2>&1 && echo 0 || echo 1)" 0

echo "== Config volume with the hardened capabilities"
CONF="$(mktemp -d)"; chmod 755 "$CONF"   # like ./config made by Docker or a default umask (mktemp is 0700, closed to root without DAC)
# like after a first htop run: htop/ is 0700 and owned by the monitor; btop.conf is root's (older image)
docker run --rm -v "$CONF:/c" --entrypoint sh "$IMG" -c 'mkdir -m 700 /c/htop && touch /c/htop/htoprc /c/btop.conf && chown -R 10001:10001 /c/htop'
start -e BTOP_PASS="$PASS" --cap-drop ALL --cap-add CHOWN --cap-add SETUID --cap-add SETGID -v "$CONF:/root/.config/btop"
docker logs "$NAME" 2>&1 | grep -q 'cannot chown' && ko "no chown warning" || ok "no chown warning"
check "btop.conf given to the monitor" "$(docker run --rm -v "$CONF:/c" --entrypoint stat "$IMG" -c %u /c/btop.conf)" 10001
docker rm -f "$NAME" >/dev/null; docker run --rm -v "$CONF:/c" --entrypoint sh "$IMG" -c 'rm -rf /c/htop /c/btop.conf'; rmdir "$CONF"

echo "== btop non-root"
start -e BTOP_PASS="$PASS"
python3 -I "$(dirname "$0")/ws_client.py" 127.0.0.1 "$PORT" admin "$PASS" 5 & sleep 3   # a real client starts btop
uid="$(docker exec "$NAME" sh -c 'for p in /proc/[0-9]*; do [ "$(cat $p/comm 2>/dev/null)" = btop ] && awk "/^Uid/{print \$2}" $p/status; done' | head -1)"
check "btop runs as UID 10001" "${uid:-none}" 10001
docker run --rm --pid host --entrypoint su-exec "$IMG" 10001:10001 kill -0 1 2>/dev/null \
	&& ko "UID 10001 can signal host PID 1" || ok "UID 10001 cannot signal host PID 1"

echo "== htop and nvtop (BTOP_TOOL)"
docker run --rm -e BTOP_PASS="$PASS" -e BTOP_TOOL=top "$IMG" >/dev/null 2>&1 && ko "unknown BTOP_TOOL refused" || ok "unknown BTOP_TOOL refused"
start -e BTOP_PASS="$PASS" -e BTOP_TOOL=htop
python3 -I "$(dirname "$0")/ws_client.py" 127.0.0.1 "$PORT" admin "$PASS" 15 & sleep 3   # session kept open for the checks below
uid="$(docker exec "$NAME" sh -c 'for p in /proc/[0-9]*; do [ "$(cat $p/comm 2>/dev/null)" = htop ] && awk "/^Uid/{print \$2}" $p/status; done' | head -1)"
check "htop runs as UID 10001" "${uid:-none}" 10001
check "nvtop binary runs" "$(docker run --rm --entrypoint nvtop "$IMG" --version >/dev/null 2>&1 && echo 0 || echo 1)" 0
# read as the tool's own UID: root in the container may not read another user's environ
envs="$(docker exec -u 10001:10001 "$NAME" sh -c 'for p in /proc/[0-9]*; do [ "$(cat $p/comm 2>/dev/null)" = htop ] && tr "\0" "\n" < $p/environ; done; true')"
check "tools environment readable for the check" "$(printf '%s\n' "$envs" | grep -c '^BTOP_TOOL=' | sed 's/^[1-9][0-9]*$/yes/')" yes
printf '%s\n' "$envs" | grep -qE '^(BTOP|GOTTY_AUTH)_PASS=' && ko "password not in the tools environment" || ok "password not in the tools environment"
check "tmux layer under the tool" "$(docker exec "$NAME" sh -c 'for p in /proc/[0-9]*; do cat $p/comm 2>/dev/null; done' | grep -c '^tmux' | sed 's/^[1-9][0-9]*$/yes/')" yes

echo "== tmux layer: no way to a shell"
keys="$(docker run --rm --entrypoint sh "$IMG" -c 'export TMUX_TMPDIR=/tmp; grep -v destroy-unattached /usr/local/share/topviewr/tmux.conf > /tmp/t.conf; tmux -L t -f /tmp/t.conf new-session -d "sleep 5" && tmux -L t list-keys')"
check "only the TopviewR bindings (10)" "$(printf '%s\n' "$keys" | grep -c .)" 10
printf '%s\n' "$keys" | grep -qE 'command-prompt|new-window|split-window|new-pane|run-shell|copy-mode|pipe' \
	&& ko "no binding can open a shell" || ok "no binding can open a shell"

echo "== BTOP_MENU=false: tool started directly"
start -e BTOP_PASS="$PASS" -e BTOP_MENU=false
python3 -I "$(dirname "$0")/ws_client.py" 127.0.0.1 "$PORT" admin "$PASS" 5 & sleep 3
check "no tmux, btop directly" "$(docker exec "$NAME" sh -c 'for p in /proc/[0-9]*; do cat $p/comm 2>/dev/null; done' | grep -xE 'tmux|btop' | sort -u | paste -sd,)" btop

echo
[ "$fails" -eq 0 ] && echo "All tests passed." || { echo "$fails test(s) failed."; exit 1; }
