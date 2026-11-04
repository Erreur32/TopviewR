#!/bin/sh
# Tests de bout en bout de l'image : ./tests/test.sh [image]
set -eu
IMG="${1:-btop-web:dev}"
PASS="test-$(head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n')"
PORT=17681
NAME=btop-test-$$
CERTS="$(mktemp -d)"
fails=0

ok()   { echo "  OK   $*"; }
ko()   { echo "  ECHEC $*"; fails=$((fails + 1)); }
check() { if [ "$2" = "$3" ]; then ok "$1"; else ko "$1 (attendu $3, obtenu $2)"; fi; }
refused() { case "$2" in 200|101) ko "$1 (obtenu $2)" ;; *) ok "$1 ($2)" ;; esac; }
code() { curl -sk -o /dev/null -m 4 -w '%{http_code}' "$@" || true; }
cleanup() { docker rm -f "$NAME" >/dev/null 2>&1 || true; rm -rf "$CERTS"; }
trap cleanup EXIT
start() { cleanup; mkdir -p "$CERTS"; docker run -d --name "$NAME" -p "127.0.0.1:$PORT:7681" "$@" "$IMG" >/dev/null; sleep 2; }
ws() { # $1 = schéma, $2 = Origin ; affiche le code HTTP de la poignée de main WebSocket
	curl -sk -o /dev/null -m 3 -w '%{http_code}' -u "admin:$PASS" \
		-H 'Connection: Upgrade' -H 'Upgrade: websocket' -H 'Sec-WebSocket-Version: 13' \
		-H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' -H 'Sec-WebSocket-Protocol: tty' \
		-H "Origin: $2" "$1://127.0.0.1:$PORT/ws" || true
}

echo "== Refus de démarrer"
docker run --rm "$IMG" >/dev/null 2>&1 && ko "sans mot de passe" || ok "sans mot de passe"
docker run --rm -e BTOP_PASS=court "$IMG" >/dev/null 2>&1 && ko "mot de passe court" || ok "mot de passe court"

echo "== HTTP + auth (variables BTOP_*)"
start -e BTOP_PASS="$PASS"
check "sans identifiants -> 401" "$(code "http://127.0.0.1:$PORT/")" 401
check "mauvais mot de passe -> 401" "$(code -u admin:faux "http://127.0.0.1:$PORT/")" 401
check "bons identifiants -> 200" "$(code -u "admin:$PASS" "http://127.0.0.1:$PORT/")" 200
check "WebSocket même origine -> 101" "$(ws http "http://127.0.0.1:$PORT")" 101
refused "WebSocket autre origine refusée" "$(ws http http://evil.example)"
docker logs "$NAME" 2>&1 | grep -q "$PASS" && ko "mot de passe absent des logs" || ok "mot de passe absent des logs"
t0=$(date +%s); docker stop "$NAME" >/dev/null; t=$(( $(date +%s) - t0 ))
[ "$t" -le 3 ] && ok "docker stop en ${t}s" || ko "docker stop trop lent (${t}s)"

echo "== Compatibilité GOTTY_*"
start -e GOTTY_AUTH_ENABLED=true -e GOTTY_AUTH_USER=admin -e GOTTY_AUTH_PASS="$PASS"
check "GOTTY_* : bons identifiants -> 200" "$(code -u "admin:$PASS" "http://127.0.0.1:$PORT/")" 200
check "GOTTY_* : sans identifiants -> 401" "$(code "http://127.0.0.1:$PORT/")" 401
start -e GOTTY_AUTH_USER=admin -e GOTTY_AUTH_PASS=court
check "GOTTY_* mot de passe court : démarre (avertissement)" "$(code -u admin:court "http://127.0.0.1:$PORT/")" 200

echo "== TLS auto"
start -e BTOP_PASS="$PASS" -e BTOP_TLS=auto -v "$CERTS:/certs"
check "HTTPS bons identifiants -> 200" "$(code -u "admin:$PASS" "https://127.0.0.1:$PORT/")" 200
refused "HTTP sans TLS non servi" "$(code -u "admin:$PASS" "http://127.0.0.1:$PORT/")"
[ -s "$CERTS/cert.pem" ] && ok "certificat écrit dans /certs" || ko "certificat absent"
sum1="$(cat "$CERTS/cert.pem" | sha256sum)"; docker restart "$NAME" >/dev/null; sleep 2
check "certificat conservé au redémarrage" "$(cat "$CERTS/cert.pem" | sha256sum)" "$sum1"
check "healthcheck en HTTPS" "$(docker exec "$NAME" /usr/local/bin/healthcheck.sh >/dev/null 2>&1 && echo 0 || echo 1)" 0

echo "== btop non root"
start -e BTOP_PASS="$PASS"
python3 -I "$(dirname "$0")/ws_client.py" 127.0.0.1 "$PORT" admin "$PASS" 5 & sleep 3   # un vrai client lance btop
uid="$(docker exec "$NAME" sh -c 'for p in /proc/[0-9]*; do [ "$(cat $p/comm 2>/dev/null)" = btop ] && awk "/^Uid/{print \$2}" $p/status; done' | head -1)"
check "btop tourne avec l'UID 10001" "${uid:-aucun}" 10001
docker run --rm --pid host --entrypoint su-exec "$IMG" 10001:10001 kill -0 1 2>/dev/null \
	&& ko "UID 10001 peut signaler le PID 1 de l'hôte" || ok "UID 10001 ne peut pas signaler le PID 1 de l'hôte"

echo
[ "$fails" -eq 0 ] && echo "Tous les tests sont passés." || { echo "$fails test(s) en échec."; exit 1; }
