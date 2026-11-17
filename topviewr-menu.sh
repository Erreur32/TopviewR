#!/bin/sh
# Opens the TopviewR menu on the client that pressed Esc, with the current tool already selected.
# Fixed launcher: no user input; the Esc menu is keyboard-only because tmux -M would disable -C (3.7c).
# The -C index counts the six title rows and the separator before btop/htop/nvtop: 7, 8, 9.
set -eu

client="${1:-}"
pane="${2:-}"
[ -n "$client" ] && [ -n "$pane" ] || exit 0

tool="$(tmux show-options -gv @tool 2>/dev/null || true)"
case "$tool" in
	btop)  choice=7 ;;
	htop)  choice=8 ;;
	nvtop) choice=9 ;;
	*)     choice=7 ;;
esac

# Title rows end in the menu background colour: tmux compares an item's length in bytes (not its width) with the
# terminal width and appends a '>' to these UTF-8 rows, which this hides.
exec tmux display-menu -c "$client" -t "$pane" -C "$choice" -O \
	-T '#[align=centre]#[fg=#9ca3af] @ #h · v#{@version}#{?@update,#[fg=#fbbf24] · update v#{@update}#[fg=#9ca3af],}' \
	-x C -y C -- \
	'-#[nodim]#[fg=#f9fafb]  ████████╗ ██████╗ ██████╗ ██╗   ██╗██╗███████╗██╗    ██╗#[fg=#86efac]██████╗ #[fg=#111827]' '' '' \
	'-#[nodim]#[fg=#e5e7eb]  ╚══██╔══╝██╔═══██╗██╔══██╗██║   ██║██║██╔════╝██║    ██║#[fg=#4ade80]██╔══██╗#[fg=#111827]' '' '' \
	'-#[nodim]#[fg=#d1d5db]     ██║   ██║   ██║██████╔╝██║   ██║██║█████╗  ██║ █╗ ██║#[fg=#22c55e]██████╔╝#[fg=#111827]' '' '' \
	'-#[nodim]#[fg=#9ca3af]     ██║   ██║   ██║██╔═══╝ ╚██╗ ██╔╝██║██╔══╝  ██║███╗██║#[fg=#16a34a]██╔══██╗#[fg=#111827]' '' '' \
	'-#[nodim]#[fg=#6b7280]     ██║   ╚██████╔╝██║      ╚████╔╝ ██║███████╗╚███╔███╔╝#[fg=#15803d]██║  ██║#[fg=#111827]' '' '' \
	'-#[nodim]#[fg=#4b5563]     ╚═╝    ╚═════╝ ╚═╝       ╚═══╝  ╚═╝╚══════╝ ╚══╝╚══╝ #[fg=#166534]╚═╝  ╚═╝#[fg=#111827]' '' '' \
	'' \
	'#{?#{==:#{@tool},btop},  >  ,     }btop     Alt+1   CPU, memory, disks, network, GPU  ' 1 '{ respawn-pane -k "/usr/local/bin/menu.sh --run btop" }' \
	'#{?#{==:#{@tool},htop},  >  ,     }htop     Alt+2   processes                         ' 2 '{ respawn-pane -k "/usr/local/bin/menu.sh --run htop" }' \
	'#{?#{==:#{@tool},nvtop},  >  ,     }nvtop    Alt+3   GPU #{@gpu}                       ' 3 '{ respawn-pane -k "/usr/local/bin/menu.sh --run nvtop" }' \
	'' \
	'     Back to #{@tool}                               q    ' q '' \
	'     #{?#{==:#{@tool},nvtop},Close this menu,Esc to #{@tool}  (closes its own menus)}        Esc  ' Escape '{ if -F "#{!=:#{@tool},nvtop}" "send-keys Escape" }' \
	'     Close this session                             x    ' x '{ kill-server }'
