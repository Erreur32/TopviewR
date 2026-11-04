#!/bin/sh
# Tool loop of a browser session: starts the default tool (or the one given with --run), and when it is quitted
# shows a small chooser. Inside tmux (session.sh), Esc and the bottom bar switch tools at any time.
# Already running as the non-root user (su-exec), and only the listed keys do something: no way to reach a shell.
DEFAULT="${BTOP_TOOL:-btop}"
CONF_DIR="${BTOP_CONF_DIR:-/root/.config/btop}"

B=$(printf '\033[1m'); D=$(printf '\033[2m'); G=$(printf '\033[32m'); Y=$(printf '\033[33m'); N=$(printf '\033[0m')

GPU="(no GPU found)"; ls /dev/dri/renderD* >/dev/null 2>&1 && GPU=""
[ -n "${TMUX:-}" ] && tmux set -g @gpu "$GPU"

run() {
	[ -n "${TMUX:-}" ] && tmux set -g @tool "$1"
	# the tool's own args only apply to the default tool
	args=""; [ "$1" = "$DEFAULT" ] && args="${BTOP_ARGS:-}"
	case "$1" in
		btop) btop $args ;;
		# htop and nvtop follow XDG_CONFIG_HOME: keep their settings in the mounted config volume
		htop|nvtop) XDG_CONFIG_HOME="$CONF_DIR" "$1" $args ;;
	esac
	# nvtop exits at once without a GPU: say why instead of leaving a bare line on screen
	if [ "$1" = nvtop ] && [ -n "$GPU" ]; then
		printf '\n%snvtop: no GPU found on %s.%s\n\n' "$Y" "$(hostname)" "$N"
		printf 'nvtop needs an AMD or Intel GPU and /dev/dri mounted in the compose file\n'
		printf '(devices: - /dev/dri:/dev/dri). NVIDIA is not supported by this image.\n\n'
		printf '%sEsc or the bottom bar: switch to btop or htop · any other key: back to the list%s' "$D" "$N"
		read -r -n 1 _ </dev/tty
	fi
}

case "${1:-}" in
	--run) case "${2:-}" in btop|htop|nvtop) run "$2" ;; *) run "$DEFAULT" ;; esac ;;
	*) run "$DEFAULT" ;;
esac

# Ctrl+C here redraws the chooser instead of closing the session (a handler, not an ignore: tools get default signals)
trap ':' INT
hint="Enter = $DEFAULT"; [ -n "${TMUX:-}" ] && hint="$hint · Esc or the bottom bar switch tools at any time"
while :; do
	[ -n "${TMUX:-}" ] && tmux set -g @tool ""
	printf '\033[H\033[2J\033[3J'
	printf '%sTopview%sR%s %s@ %s%s\n\n' "$B" "$G" "$N" "$D" "$(hostname)" "$N"
	for t in btop htop nvtop; do
		case $t in btop) k=1 d="CPU, memory, disks, network, GPU, processes" ;; htop) k=2 d="processes" ;; nvtop) k=3 d="GPU $GPU" ;; esac
		mark="  "; [ "$t" = "$DEFAULT" ] && mark="${G}>${N} "
		printf '%s%s%s%s  %-6s %s%s%s\n' "$mark" "$B" "$k" "$N" "$t" "$D" "$d" "$N"
	done
	printf '\n  %sq%s  close this session\n\n%s%s%s\n\nChoice: ' "$B" "$N" "$D" "$hint" "$N"
	c=""; read -r -n 1 c </dev/tty || exit 0
	case "$c" in
		"") run "$DEFAULT" ;;
		1) run btop ;;
		2) run htop ;;
		3) run nvtop ;;
		q|Q) exit 0 ;;
		*) printf '\n%sunknown key%s' "$Y" "$N"; sleep 1 ;;
	esac
done
