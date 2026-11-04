#!/bin/sh
# Prepares config and certificates, then replaces the shell with ttyd (exec).
set -eu

log() { echo "[btop-web] $*" >&2; }
die() { log "ERROR: $*"; exit 1; }
is_true() { case "$(echo "${1:-}" | tr '[:upper:]' '[:lower:]')" in true|1|yes|on) return 0 ;; *) return 1 ;; esac; }

# --- Credentials: BTOP_* wins, GOTTY_* kept for legacy compose files ---
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

case "$BTOP_UID$BTOP_GID" in *[!0-9]*) die "BTOP_UID and BTOP_GID must be numeric" ;; esac
case "$PORT" in ''|*[!0-9]*) die "BTOP_PORT must be numeric" ;; esac
[ "$BTOP_UID" = 0 ] && log "WARNING: btop runs as root, the k key can kill any host process."

set -- ttyd -W -O -p "$PORT" -w /tmp \
	-m "${BTOP_MAX_CLIENTS:-3}" \
	-t "titleFixed=${BTOP_TITLE:-btop @ $(hostname)}" \
	-t "fontSize=${BTOP_FONT_SIZE:-14}" \
	-t "disableLeaveAlert=true"

if [ "${BTOP_THEME:-dark}" = light ]; then
	set -- "$@" -t 'theme={"background":"#ffffff","foreground":"#000000","cursor":"#000000"}'
fi
[ -n "${BTOP_BIND:-}" ] && set -- "$@" -i "$BTOP_BIND"

# --- Authentication ---
if [ -n "${BTOP_AUTH_HEADER:-}" ]; then
	log "Auth delegated to the reverse proxy (header $BTOP_AUTH_HEADER). The port must only be reachable by the proxy."
	set -- "$@" -H "$BTOP_AUTH_HEADER"
elif [ "$NO_AUTH" = true ]; then
	log "WARNING: authentication disabled, anyone on the network can see and control btop."
else
	[ -n "$USER_PASS" ] || die "no password. Set BTOP_PASS (or GOTTY_AUTH_PASS), or BTOP_NO_AUTH=true to disable auth."
	if [ "${#USER_PASS}" -lt 12 ] && ! is_true "${BTOP_ALLOW_WEAK_PASS:-}"; then
		# legacy compose files (GOTTY_*): warn without blocking, for a drop-in replacement
		[ -z "${BTOP_PASS:-}" ] || die "password too short (12 characters minimum). Set BTOP_ALLOW_WEAK_PASS=true to force."
		log "WARNING: password shorter than 12 characters (GOTTY_AUTH_PASS). Change it or switch to BTOP_PASS."
	fi
	case "$USER_NAME" in *:*) die "BTOP_USER must not contain ':'" ;; esac
	set -- "$@" -c "$USER_NAME:$USER_PASS"
fi

# --- TLS ---
case "$TLS_MODE" in
	off|false|0) ;;
	auto|on|true|1)
		CERT="$CERT_DIR/cert.pem"; KEY="$CERT_DIR/key.pem"
		if [ ! -s "$CERT" ] || [ ! -s "$KEY" ]; then
			[ "$TLS_MODE" = on ] && die "BTOP_TLS=on but $CERT or $KEY is missing (use auto to generate a self-signed certificate)"
			SAN="DNS:$(hostname),DNS:localhost,IP:127.0.0.1"
			for s in $(echo "${BTOP_TLS_SAN:-}" | tr ',' ' '); do
				case "$s" in *[!0-9.]*) SAN="$SAN,DNS:$s" ;; *) SAN="$SAN,IP:$s" ;; esac
			done
			log "Generating a self-signed certificate ($SAN) in $CERT_DIR"
			( umask 077; openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 3650 \
				-subj "/CN=$(hostname)" -addext "subjectAltName=$SAN" -keyout "$KEY" -out "$CERT" 2>/dev/null ) \
				|| die "cannot write to $CERT_DIR (mount a volume on /certs)"
		fi
		set -- "$@" -S -C "$CERT" -K "$KEY"
		;;
	*) die "BTOP_TLS must be off, auto or on" ;;
esac

# --- Persistent btop config ---
if [ ! -f "$CONF_DIR/btop.conf" ]; then
	log "No btop.conf: copying the default config"
	cp /usr/local/share/btop/btop.conf.default "$CONF_DIR/btop.conf" || log "config not copied (read-only volume?)"
fi
# btop (non-root) must be able to save its settings; error ignored on a read-only volume
chown -R "$BTOP_UID:$BTOP_GID" "$CONF_DIR" 2>/dev/null || log "cannot chown $CONF_DIR, settings will not be saved"

# Extra ttyd arguments (split on spaces, on purpose)
# shellcheck disable=SC2086
# ttyd -u does not change the UID of the launched program, su-exec does
set -- "$@" ${TTYD_EXTRA_ARGS:-} su-exec "$BTOP_UID:$BTOP_GID" btop ${BTOP_ARGS:-}

log "ttyd on port $PORT, TLS=$TLS_MODE, btop UID=$BTOP_UID"
exec "$@"
