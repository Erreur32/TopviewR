#!/bin/sh
# End-to-end tests for the image: ./tests/test.sh [image]
set -eu
IMG="${1:-btop-web:dev}"
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

echo "== btop non-root"
start -e BTOP_PASS="$PASS"
python3 -I "$(dirname "$0")/ws_client.py" 127.0.0.1 "$PORT" admin "$PASS" 5 & sleep 3   # a real client starts btop
uid="$(docker exec "$NAME" sh -c 'for p in /proc/[0-9]*; do [ "$(cat $p/comm 2>/dev/null)" = btop ] && awk "/^Uid/{print \$2}" $p/status; done' | head -1)"
check "btop runs as UID 10001" "${uid:-none}" 10001
docker run --rm --pid host --entrypoint su-exec "$IMG" 10001:10001 kill -0 1 2>/dev/null \
	&& ko "UID 10001 can signal host PID 1" || ok "UID 10001 cannot signal host PID 1"

echo
[ "$fails" -eq 0 ] && echo "All tests passed." || { echo "$fails test(s) failed."; exit 1; }
