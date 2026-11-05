#!/bin/sh
# Prepares config and certificates, then replaces the shell with ttyd (exec).
set -eu

log() { echo "[topviewr] $*" >&2; }
die() { log "ERROR: $*"; exit 1; }
is_true() { case "$(echo "${1:-}" | tr '[:upper:]' '[:lower:]')" in true|1|yes|on) return 0 ;; *) return 1 ;; esac; }

# Startup header: settings and host summary, never a secret (only the user name)
banner() {
	b=$(printf '\033[1;36m'); d=$(printf '\033[2m'); g=$(printf '\033[1;32m'); r=$(printf '\033[0m')
	line="════════════════════════════════════════════════════════════"
	row() { printf '%s║%s  %-10s %s\n' "$b" "$r" "$1" "$2"; }
	host="$(hostname)"
	case "${BTOP_BIND:-}" in *[0-9].*[0-9]) host="$BTOP_BIND" ;; *)
		for s in $(echo "${BTOP_TLS_SAN:-}" | tr ',' ' '); do case "$s" in *[!0-9.]*) ;; *) host="$s"; break ;; esac; done ;;
	esac
	case "$TLS_MODE" in off|false|0) scheme=http ;; *) scheme=https ;; esac
	cpu="$(sed -n 's/^model name[[:space:]]*: //p' /proc/cpuinfo | head -1)"
	ram="$(awk '/^MemTotal:/ { printf "%.1f GiB", $2 / 1048576 }' /proc/meminfo)"
	set -- /dev/dri/renderD*
	if [ -e "$1" ]; then gpu="$# render node(s) in /dev/dri"; else gpu="none (mount /dev/dri for nvtop)"; fi
	ver() { "$@" 2>/dev/null | head -1 | tr -d '\033' | grep -o '[0-9][0-9.]*[0-9]' | head -1; }
	{
		printf '%s╔%s%s\n' "$b" "$line" "$r"
		printf '%s║%s   %sTopviewR %s%s\n' "$b" "$r" "$g" "v$(cat /usr/local/share/topviewr/version 2>/dev/null || echo dev)" "$r"
		printf '%s║%s   %sbtop, htop and nvtop in the browser%s\n' "$b" "$r" "$d" "$r"
		printf '%s╠%s%s\n' "$b" "$line" "$r"
		row "URL" "$scheme://$host:$PORT/"
		row "Auth" "$AUTH_LABEL"
		row "TLS" "$TLS_MODE"
		row "Menu" "${BTOP_MENU:-true}, default $TOOL"
		row "Runs as" "UID $BTOP_UID, GID $BTOP_GID"
		row "Logs" "$LOG_LABEL"
		printf '%s╠══ Host %s%s\n' "$b" "${line#════════}" "$r"
		row "Host" "$(hostname)"
		row "CPU" "${cpu:+$cpu, }$(nproc) threads"
		row "RAM" "$ram"
		row "GPU" "$gpu"
		row "Tools" "btop $(ver btop --version), htop $(ver htop --version), nvtop $(ver nvtop --version), ttyd $(ver ttyd --version)"
		printf '%s╚%s%s\n' "$b" "$line" "$r"
	} >&2
}

# --- Credentials: BTOP_* wins, GOTTY_* kept for legacy compose files ---
USER_NAME="${BTOP_USER:-${GOTTY_AUTH_USER:-admin}}"
USER_PASS="${BTOP_PASS:-${GOTTY_AUTH_PASS:-}}"
NO_AUTH=false
if is_true "${BTOP_NO_AUTH:-}"; then NO_AUTH=true; fi
if [ -n "${GOTTY_AUTH_ENABLED:-}" ] && ! is_true "$GOTTY_AUTH_ENABLED" && [ -z "${BTOP_PASS:-}" ]; then NO_AUTH=true; fi

PORT="${BTOP_PORT:-7681}"
BTOP_UID="${BTOP_UID:-10001}"
TOOL="${BTOP_TOOL:-btop}"
case "$TOOL" in btop|htop|nvtop) ;; *) die "BTOP_TOOL must be btop, htop or nvtop" ;; esac
# GPU render nodes are root:render 0660 on most hosts: without that group nvtop (and btop's GPU view) see no GPU.
# su-exec sets a single group, so by default the monitor runs with the render group as its group.
GPU_GID="$(stat -c %g /dev/dri/renderD* 2>/dev/null | head -1)"
BTOP_GID="${BTOP_GID:-${GPU_GID:-10001}}"
CONF_DIR="${XDG_CONFIG_HOME:-/root/.config}/btop"
CERT_DIR="${BTOP_CERT_DIR:-/certs}"
TLS_MODE="$(echo "${BTOP_TLS:-off}" | tr '[:upper:]' '[:lower:]')"

case "$BTOP_UID$BTOP_GID" in *[!0-9]*) die "BTOP_UID and BTOP_GID must be numeric" ;; esac
case "$PORT" in ''|*[!0-9]*) die "BTOP_PORT must be numeric" ;; esac
[ "$BTOP_UID" = 0 ] && log "WARNING: $TOOL runs as root, its kill key can end any host process."

set -- ttyd -W -O -p "$PORT" -w /tmp \
	-m "${BTOP_MAX_CLIENTS:-3}" \
	-t "titleFixed=${BTOP_TITLE:-TopviewR @ $(hostname)}" \
	-t "fontSize=${BTOP_FONT_SIZE:-16}" \
	-t "disableLeaveAlert=true" \
	-I /usr/local/share/topviewr/index.html

# ttyd log level: errors and warnings only (refused origins stay visible); BTOP_DEBUG adds libwebsockets notices
# (every connection, the startup config). The credential line is masked by ttyd-cred.so either way.
if is_true "${BTOP_DEBUG:-}"; then LOG_LEVEL=7; LOG_LABEL="debug (ttyd notices)"; else LOG_LEVEL=3; LOG_LABEL="errors and warnings (BTOP_DEBUG=true for more)"; fi
set -- "$@" -d "$LOG_LEVEL"

if [ "${BTOP_THEME:-dark}" = light ]; then
	set -- "$@" -t 'theme={"background":"#ffffff","foreground":"#000000","cursor":"#000000"}'
fi
[ -n "${BTOP_BIND:-}" ] && set -- "$@" -i "$BTOP_BIND"

# --- Authentication ---
if [ -n "${BTOP_AUTH_HEADER:-}" ]; then
	AUTH_LABEL="reverse proxy (header $BTOP_AUTH_HEADER)"
	log "Auth delegated to the reverse proxy (header $BTOP_AUTH_HEADER). The port must only be reachable by the proxy."
	set -- "$@" -H "$BTOP_AUTH_HEADER"
elif [ "$NO_AUTH" = true ]; then
	AUTH_LABEL="DISABLED"
	log "WARNING: authentication disabled, anyone on the network can see and control $TOOL."
else
	[ -n "$USER_PASS" ] || die "no password. Set BTOP_PASS (or GOTTY_AUTH_PASS), or BTOP_NO_AUTH=true to disable auth."
	if [ "${#USER_PASS}" -lt 12 ] && ! is_true "${BTOP_ALLOW_WEAK_PASS:-}"; then
		# legacy compose files (GOTTY_*): warn without blocking, for a drop-in replacement
		[ -z "${BTOP_PASS:-}" ] || die "password too short (12 characters minimum). Set BTOP_ALLOW_WEAK_PASS=true to force."
		log "WARNING: password shorter than 12 characters (GOTTY_AUTH_PASS). Change it or switch to BTOP_PASS."
	fi
	case "$USER_NAME" in *:*) die "BTOP_USER must not contain ':'" ;; esac
	# not in ttyd's command line (world-readable in ps): ttyd-cred.so swaps the TTYD_CREDENTIAL placeholder for its value
	export TTYD_CREDENTIAL="$USER_NAME:$USER_PASS"
	AUTH_LABEL="password, user $USER_NAME"
	set -- "$@" -c TTYD_CREDENTIAL
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

# --- Persistent config: btop.conf at the root of the volume, htop/ and nvtop/ subfolders ---
# always: with the menu, btop can be started whatever the default tool
if [ ! -f "$CONF_DIR/btop.conf" ]; then
	log "No btop.conf: copying the default config"
	cp /usr/local/share/btop/btop.conf.default "$CONF_DIR/btop.conf" || log "config not copied (read-only volume?)"
fi
# the monitor (non-root) must be able to save its settings: chown only what it does not own yet (older image, new
# BTOP_GID), contents before folders (-depth), since htop keeps its folder 0700, closed to root without DAC_OVERRIDE
find "$CONF_DIR" -depth \( ! -user "$BTOP_UID" -o ! -group "$BTOP_GID" \) -exec chown "$BTOP_UID:$BTOP_GID" {} + 2>/dev/null || true
[ "$(stat -c %u "$CONF_DIR" 2>/dev/null)" = "$BTOP_UID" ] || log "cannot chown $CONF_DIR, settings will not be saved"

# Extra ttyd arguments (split on spaces, on purpose)
# shellcheck disable=SC2086
# ttyd -u does not change the UID of the launched program, su-exec does
# the tools inherit ttyd's environment: drop the passwords so htop's environment view (e) cannot show them
# a root sh stays as ttyd's child: without CAP_KILL ttyd cannot signal the non-root tool, so a closed tab would leave
# it running forever; it can signal this sh, whose exit closes the terminal and the kernel hangs up the whole session
# ('; exit' keeps sh from exec-ing su-exec in its place)
set -- "$@" ${TTYD_EXTRA_ARGS:-} env -u BTOP_PASS -u GOTTY_AUTH_PASS BTOP_TOOL="$TOOL" BTOP_CONF_DIR="$CONF_DIR" \
	sh -c 'su-exec "$@"; exit' topviewr "$BTOP_UID:$BTOP_GID"
if is_true "${BTOP_MENU:-true}"; then
	# tmux layer: Esc menu and clickable bottom bar to switch between btop, htop and nvtop
	set -- "$@" /usr/local/bin/session.sh
elif [ "$TOOL" = btop ]; then
	set -- "$@" btop ${BTOP_ARGS:-}
else
	# htop and nvtop follow XDG_CONFIG_HOME: point it at the mounted volume so their settings persist too
	set -- "$@" env XDG_CONFIG_HOME="$CONF_DIR" "$TOOL" ${BTOP_ARGS:-}
fi

banner
# only for ttyd: the shim swaps the value of any -c option (busybox stat -c above)
[ -z "${TTYD_CREDENTIAL:-}" ] || export LD_PRELOAD=/usr/local/lib/ttyd-cred.so
exec "$@"
