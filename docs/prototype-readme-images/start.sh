#!/bin/bash
# PROTOTYPE: start the demo server and attach it through the outer server. Usage: start.sh <repo>
R=$1; H=$(cd "$(dirname "$0")" && pwd); N=$(date +%s); C=$(mktemp -d)/cache
"$H/make-snapshots.sh" "$C" "$N"
tmux -L demo kill-server 2>/dev/null; tmux -L outer kill-server 2>/dev/null
export AI_USAGE_NO_REFRESH=1 AI_USAGE_NOW="$N"
tmux -L demo -f "$H/demo.conf" new-session -d -s demo -x 110 -y 8 "PS1='~/project \$ ' bash --norc -i" \; set -g @ai_usage_cache_dir "$C"
tmux -L demo run-shell "$R/ai_usage.tmux"
tmux -L outer -f "$H/outer.conf" new-session -d -s o -x "$(tput cols)" -y "$(tput lines)" "env -u TMUX tmux -L demo attach -t demo"
tmux -L outer split-window -h -t o:0 "exec sleep 9999" \; resize-pane -t o:0.0 -x 110 \; select-pane -t o:0.0
exec env -u TMUX tmux -L outer attach -t o
