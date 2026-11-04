#!/bin/sh
# One tmux server per browser session (its own socket in /tmp): closing the tab destroys it with its tools.
export TMUX_TMPDIR=/tmp
exec tmux -L "topviewr-$$" -f /usr/local/share/topviewr/tmux.conf new-session -s main /usr/local/bin/menu.sh
