#!/bin/sh
# End-to-end tests for the image: ./tests/test.sh [image]
set -eu
IMG="${1:-topviewr:dev}"
VERSION="$(docker run --rm --entrypoint cat "$IMG" /usr/local/share/topviewr/version 2>/dev/null || true)"
VERSION="${VERSION:-dev}"
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
start() { cleanup; mkdir -p "$CERTS"; docker run -d --name "$NAME" -p "127.0.0.1:$PORT:7681" -e BTOP_UPDATE_CHECK=false "$@" "$IMG" >/dev/null; sleep 2; }
tool_running() { docker exec "$NAME" sh -c 'for p in /proc/[0-9]*; do cat $p/comm 2>/dev/null; done' | grep -qx "$1" && echo yes || echo no; }
switch_tool() { # $1 = tool; same command as the tmux bar/menu, without a browser
	sock=$(docker exec "$NAME" sh -c 'ls -d /tmp/tmux-*/topviewr-* 2>/dev/null | head -1' | sed 's|.*/||')
	[ -n "$sock" ] || return 1
	docker exec -u 10001:10001 "$NAME" env HOME=/tmp TMUX_TMPDIR=/tmp tmux -L "$sock" \
		respawn-pane -k -t main:0.0 "/usr/local/bin/menu.sh --run $1"
}
tmux_opt() { # $1 = user option; prints its value, or nothing if there is no session
	sock=$(docker exec "$NAME" sh -c 'ls -d /tmp/tmux-*/topviewr-* 2>/dev/null | head -1' | sed 's|.*/||')
	[ -n "$sock" ] || return 0
	docker exec -u 10001:10001 "$NAME" env HOME=/tmp TMUX_TMPDIR=/tmp tmux -L "$sock" show-options -g -v "$1" 2>/dev/null || true
}
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
docker logs "$NAME" 2>&1 | grep -q '╔' && ok "startup header shown" || ko "startup header missing"
docker logs "$NAME" 2>&1 | grep -q 'lws_gate_accepts\|credential:' && ko "no ttyd notices by default" || ok "no ttyd notices by default"
# what any other account sees in ps (/proc/*/cmdline is world-readable)
cmdlines="$(docker exec -u 10001:10001 "$NAME" sh -c 'for p in /proc/[0-9]*; do tr "\0" " " < $p/cmdline; echo; done')"
check "ttyd command line readable for the check" "$(printf '%s\n' "$cmdlines" | grep -c '^ttyd .*-c TTYD_CREDENTIAL ' | sed 's/^[1-9][0-9]*$/yes/')" yes
printf '%s\n' "$cmdlines" | grep -qF "$PASS" && ko "password not in any command line" || ok "password not in any command line"
t0=$(date +%s); docker stop "$NAME" >/dev/null; t=$(( $(date +%s) - t0 ))
[ "$t" -le 3 ] && ok "docker stop in ${t}s" || ko "docker stop too slow (${t}s)"

echo "== BTOP_DEBUG: ttyd notices, credential still hidden"
start -e BTOP_PASS="$PASS" -e BTOP_DEBUG=true
code -u "admin:$PASS" "http://127.0.0.1:$PORT/" >/dev/null
docker logs "$NAME" 2>&1 | grep -q 'HTTP / - ' && ok "debug: connection notices" || ko "debug: connection notices missing"
docker logs "$NAME" 2>&1 | grep -q 'credential: (hidden' && ok "debug: credential line masked" || ko "debug: credential line not masked"
B64="$(printf 'admin:%s' "$PASS" | base64 | tr -d '\n')"
docker logs "$NAME" 2>&1 | grep -qF "$B64" && ko "debug: base64 credential not in logs" || ok "debug: base64 credential not in logs"

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
# read from the container: cert.pem is root's 0600, unreadable for a non-root CI runner
sum1="$(docker exec "$NAME" sha256sum /certs/cert.pem)"; docker restart "$NAME" >/dev/null; sleep 2
check "certificate kept across restart" "$(docker exec "$NAME" sha256sum /certs/cert.pem)" "$sum1"
check "healthcheck over HTTPS" "$(docker exec "$NAME" /usr/local/bin/healthcheck.sh >/dev/null 2>&1 && echo 0 || echo 1)" 0

echo "== Config volume with the hardened capabilities"
CONF="$(mktemp -d)"; chmod 755 "$CONF"   # like ./config made by Docker or a default umask (mktemp is 0700, closed to root without DAC)
# like after a first htop run: htop/ is 0700 and owned by the monitor; btop.conf is root's (older image)
docker run --rm -v "$CONF:/c" --entrypoint sh "$IMG" -c 'mkdir -m 700 /c/htop && touch /c/htop/htoprc /c/btop.conf && chown -R 10001:10001 /c/htop'
start -e BTOP_PASS="$PASS" --cap-drop ALL --cap-add CHOWN --cap-add SETUID --cap-add SETGID -v "$CONF:/root/.config/btop"
docker logs "$NAME" 2>&1 | grep -q 'cannot chown' && ko "no chown warning" || ok "no chown warning"
check "btop.conf given to the monitor" "$(docker run --rm -v "$CONF:/c" --entrypoint stat "$IMG" -c %u /c/btop.conf)" 10001
# hand the folder back (it now belongs to 10001, and /tmp is sticky) before removing it
docker rm -f "$NAME" >/dev/null; docker run --rm -v "$CONF:/c" --entrypoint sh "$IMG" -c "rm -rf /c/htop /c/btop.conf && chown $(id -u):$(id -g) /c"; rmdir "$CONF"

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
printf '%s\n' "$envs" | grep -qE '^((BTOP|GOTTY_AUTH)_PASS|TTYD_CREDENTIAL|LD_PRELOAD)=' && ko "password not in the tools environment" || ok "password not in the tools environment"
check "tmux layer under the tool" "$(docker exec "$NAME" sh -c 'for p in /proc/[0-9]*; do cat $p/comm 2>/dev/null; done' | grep -c '^tmux' | sed 's/^[1-9][0-9]*$/yes/')" yes

echo "== tmux layer: no way to a shell"
keys="$(docker run --rm --entrypoint sh "$IMG" -c 'export TMUX_TMPDIR=/tmp; grep -v destroy-unattached /usr/local/share/topviewr/tmux.conf > /tmp/t.conf; tmux -L t -f /tmp/t.conf new-session -d "sleep 5" && tmux -L t list-keys')"
check "only the TopviewR bindings (16)" "$(printf '%s\n' "$keys" | grep -c .)" 16
check "nvtop Esc guard" "$(docker run --rm --entrypoint sh "$IMG" -c 'grep -qF "==:#{@tool},nvtop" /usr/local/bin/topviewr-menu.sh && echo yes || echo no')" yes
printf '%s\n' "$keys" | grep -qE 'command-prompt|new-window|split-window|new-pane|copy-mode|pipe' \
	&& ko "no binding can open a shell" || ok "no binding can open a shell"
printf '%s\n' "$keys" | grep 'run-shell' | grep -vF '/usr/local/bin/topviewr-menu.sh' | grep -q . \
	&& ko "unexpected run-shell" || ok "only the fixed menu launcher"

echo "== menu launcher: current tool selected"
FAKE="$(mktemp -d)"
cat > "$FAKE/tmux" <<'EOF'
#!/bin/sh
case "$1" in
	show-options) printf '%s\n' htop ;;
	display-menu) printf '%s\n' "$*" ;;
esac
EOF
chmod 755 "$FAKE/tmux"
check "menu starts on the current tool" \
	"$(docker run --rm -v "$FAKE:/fake:ro" --entrypoint sh "$IMG" -c 'PATH=/fake:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; /usr/local/bin/topviewr-menu.sh /dev/pts/0 %0' | grep -o -- '-C [0-9]*')" "-C 8"
rm -rf "$FAKE"

echo "== BTOP_MENU=false: tool started directly"
start -e BTOP_PASS="$PASS" -e BTOP_MENU=false
python3 -I "$(dirname "$0")/ws_client.py" 127.0.0.1 "$PORT" admin "$PASS" 5 & sleep 3
check "no tmux, btop directly" "$(docker exec "$NAME" sh -c 'for p in /proc/[0-9]*; do cat $p/comm 2>/dev/null; done' | grep -xE 'tmux|btop' | sort -u | paste -sd,)" btop

echo "== Closing the tab ends the session (hardened capabilities: no CAP_KILL)"
start -e BTOP_PASS="$PASS" --cap-drop ALL --cap-add CHOWN --cap-add SETUID --cap-add SETGID
procs() { docker exec "$NAME" sh -c 'for p in /proc/[0-9]*; do cat $p/comm 2>/dev/null; done' | grep -cE '^(tmux|btop)' || true; }
python3 -I "$(dirname "$0")/ws_client.py" 127.0.0.1 "$PORT" admin "$PASS" 4 & client=$!; sleep 3
check "session runs while the tab is open" "$(procs | sed 's/^[1-9][0-9]*$/yes/')" yes
wait "$client" || true; sleep 2
check "nothing left once the tab is closed" "$(procs)" 0

echo "== Last tool remembered across reconnections"
LASTCONF="$(mktemp -d)"; chmod 755 "$LASTCONF"
start -e BTOP_PASS="$PASS" -e BTOP_TOOL=htop -v "$LASTCONF:/root/.config/btop"
python3 -I "$(dirname "$0")/ws_client.py" 127.0.0.1 "$PORT" admin "$PASS" 14 & client=$!; sleep 3
check "starts on BTOP_TOOL" "$(tool_running htop)" yes
check "version in tmux" "$(tmux_opt @version)" "$VERSION"
check "no update when the check is off" "$(tmux_opt @update)" ""
switch_tool btop && ok "switch to btop" || ko "switch to btop"
sleep 2
check "last tool saved" "$(cat "$LASTCONF/.last-tool" 2>/dev/null)" btop
check "btop runs after the switch" "$(tool_running btop)" yes
wait "$client" || true; sleep 2
check "session closed after the disconnect" "$(tool_running btop)" no
python3 -I "$(dirname "$0")/ws_client.py" 127.0.0.1 "$PORT" admin "$PASS" 8 & client=$!; sleep 3
check "reconnect opens the last tool" "$(tool_running btop)" yes
check "reconnect does not open BTOP_TOOL" "$(tool_running htop)" no
wait "$client" || true; sleep 2
start -e BTOP_PASS="$PASS" -e BTOP_TOOL=htop -e BTOP_RESTORE_LAST=false -v "$LASTCONF:/root/.config/btop"
python3 -I "$(dirname "$0")/ws_client.py" 127.0.0.1 "$PORT" admin "$PASS" 6 & client=$!; sleep 3
check "BTOP_RESTORE_LAST=false ignores the last tool" "$(tool_running htop)" yes
wait "$client" || true
cleanup
# the config volume now belongs to UID 10001: empty it as root, then hand it back to the CI user
docker run --rm -v "$LASTCONF:/c" --entrypoint sh "$IMG" \
	-c "find /c -mindepth 1 -maxdepth 1 -exec rm -rf {} +; chown $(id -u):$(id -g) /c"
rmdir "$LASTCONF"

echo "== Update check (fake GitHub API)"
FAKE="$(mktemp -d)"
cat > "$FAKE/curl" <<'EOF'
#!/bin/sh
printf '{"tag_name": "v99.0.0"}\n'
EOF
chmod 755 "$FAKE/curl"
start -e BTOP_PASS="$PASS" -e BTOP_UPDATE_CHECK=true \
	-e PATH=/fake:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
	-v "$FAKE:/fake:ro"
check "newer release cached" "$(docker exec "$NAME" cat /tmp/.topviewr-update 2>/dev/null)" 99.0.0
docker logs "$NAME" 2>&1 | grep -q 'Update.*v99\.0\.0' && ok "update in the startup header" || ko "update in the startup header"
python3 -I "$(dirname "$0")/ws_client.py" 127.0.0.1 "$PORT" admin "$PASS" 6 & client=$!; sleep 3
check "update exposed to tmux" "$(tmux_opt @update)" 99.0.0
wait "$client" || true
cleanup; rm -rf "$FAKE"

echo
[ "$fails" -eq 0 ] && echo "All tests passed." || { echo "$fails test(s) failed."; exit 1; }
