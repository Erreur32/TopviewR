#!/bin/sh
# Prépare la config et les certificats puis remplace le shell par ttyd (exec).
set -eu

log() { echo "[btop-web] $*" >&2; }
die() { log "ERREUR : $*"; exit 1; }
is_true() { case "$(echo "${1:-}" | tr '[:upper:]' '[:lower:]')" in true|1|yes|on) return 0 ;; *) return 1 ;; esac; }

# --- Identifiants : BTOP_* prioritaire, GOTTY_* pour les anciens compose ---
USER_NAME="${BTOP_USER:-${GOTTY_AUTH_USER:-admin}}"
USER_PASS="${BTOP_PASS:-${GOTTY_AUTH_PASS:-}}"
NO_AUTH=false
if is_true "${BTOP_NO_AUTH:-}"; then NO_AUTH=true; fi
if [ -n "${GOTTY_AUTH_ENABLED:-}" ] && ! is_true "$GOTTY_AUTH_ENABLED" && [ -z "${BTOP_PASS:-}" ]; then NO_AUTH=true; fi

PORT="${BTOP_PORT:-7681}"
BTOP_UID="${BTOP_UID:-10001}"
BTOP_GID="${BTOP_GID:-10001}"
CONF_DIR="${XDG_CONFIG_HOME:-/root/.config}/btop"
CERT_DIR="${BTOP_CERT_DIR:-/certs}"
TLS_MODE="$(echo "${BTOP_TLS:-off}" | tr '[:upper:]' '[:lower:]')"

case "$BTOP_UID$BTOP_GID" in *[!0-9]*) die "BTOP_UID et BTOP_GID doivent être numériques" ;; esac
case "$PORT" in ''|*[!0-9]*) die "BTOP_PORT doit être numérique" ;; esac
[ "$BTOP_UID" = 0 ] && log "ATTENTION : btop tourne en root, la touche k peut tuer n'importe quel processus de l'hôte."

set -- ttyd -W -O -p "$PORT" -w /tmp \
	-m "${BTOP_MAX_CLIENTS:-3}" \
	-t "titleFixed=${BTOP_TITLE:-btop @ $(hostname)}" \
	-t "fontSize=${BTOP_FONT_SIZE:-14}" \
	-t "disableLeaveAlert=true"

if [ "${BTOP_THEME:-dark}" = light ]; then
	set -- "$@" -t 'theme={"background":"#ffffff","foreground":"#000000","cursor":"#000000"}'
fi
[ -n "${BTOP_BIND:-}" ] && set -- "$@" -i "$BTOP_BIND"

# --- Authentification ---
if [ -n "${BTOP_AUTH_HEADER:-}" ]; then
	log "Auth déléguée au reverse proxy (en-tête $BTOP_AUTH_HEADER). Le port ne doit être joignable que par le proxy."
	set -- "$@" -H "$BTOP_AUTH_HEADER"
elif [ "$NO_AUTH" = true ]; then
	log "ATTENTION : authentification désactivée, n'importe qui sur le réseau voit et pilote btop."
else
	[ -n "$USER_PASS" ] || die "aucun mot de passe. Définir BTOP_PASS (ou GOTTY_AUTH_PASS), ou BTOP_NO_AUTH=true pour désactiver l'auth."
	if [ "${#USER_PASS}" -lt 12 ] && ! is_true "${BTOP_ALLOW_WEAK_PASS:-}"; then
		# anciens compose (GOTTY_*) : on avertit sans bloquer, pour un remplacement transparent
		[ -z "${BTOP_PASS:-}" ] || die "mot de passe trop court (12 caractères minimum). BTOP_ALLOW_WEAK_PASS=true pour forcer."
		log "ATTENTION : mot de passe de moins de 12 caractères (GOTTY_AUTH_PASS). Le changer ou passer à BTOP_PASS."
	fi
	case "$USER_NAME" in *:*) die "BTOP_USER ne doit pas contenir ':'" ;; esac
	set -- "$@" -c "$USER_NAME:$USER_PASS"
fi

# --- TLS ---
case "$TLS_MODE" in
	off|false|0) ;;
	auto|on|true|1)
		CERT="$CERT_DIR/cert.pem"; KEY="$CERT_DIR/key.pem"
		if [ ! -s "$CERT" ] || [ ! -s "$KEY" ]; then
			[ "$TLS_MODE" = on ] && die "BTOP_TLS=on mais $CERT ou $KEY absent (utiliser auto pour générer un certificat auto-signé)"
			SAN="DNS:$(hostname),DNS:localhost,IP:127.0.0.1"
			for s in $(echo "${BTOP_TLS_SAN:-}" | tr ',' ' '); do
				case "$s" in *[!0-9.]*) SAN="$SAN,DNS:$s" ;; *) SAN="$SAN,IP:$s" ;; esac
			done
			log "Génération d'un certificat auto-signé ($SAN) dans $CERT_DIR"
			( umask 077; openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 3650 \
				-subj "/CN=$(hostname)" -addext "subjectAltName=$SAN" -keyout "$KEY" -out "$CERT" 2>/dev/null ) \
				|| die "impossible d'écrire dans $CERT_DIR (monter un volume sur /certs)"
		fi
		set -- "$@" -S -C "$CERT" -K "$KEY"
		;;
	*) die "BTOP_TLS doit valoir off, auto ou on" ;;
esac

# --- Config btop persistante ---
if [ ! -f "$CONF_DIR/btop.conf" ]; then
	log "Pas de btop.conf : copie de la config par défaut"
	cp /usr/local/share/btop/btop.conf.default "$CONF_DIR/btop.conf" || log "config non copiée (volume en lecture seule ?)"
fi
# btop (non root) doit pouvoir enregistrer ses réglages ; erreur ignorée si volume en lecture seule
chown -R "$BTOP_UID:$BTOP_GID" "$CONF_DIR" 2>/dev/null || log "chown de $CONF_DIR impossible, les réglages ne seront pas sauvegardés"

# Arguments ttyd supplémentaires (découpés sur les espaces, volontairement)
# shellcheck disable=SC2086
# ttyd -u ne change pas l'UID du programme lancé, su-exec si
set -- "$@" ${TTYD_EXTRA_ARGS:-} su-exec "$BTOP_UID:$BTOP_GID" btop ${BTOP_ARGS:-}

log "ttyd sur le port $PORT, TLS=$TLS_MODE, btop UID=$BTOP_UID"
exec "$@"
