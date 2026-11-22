#!/bin/bash
# Set the scene for one README image and attach to it. The tapes in
# docs/demo/tapes/ run this inside VHS: bash docs/demo/start.sh <image>
# `start.sh --stop` tears everything down (make images runs it after each tape).
#
# Two private tmux servers, never the default one:
#   ai-usage-demo   runs the plugin from this checkout on hand-made usage
#                   snapshots, configured only by demo.conf
#   ai-usage-outer  holds the demo client in a pane, so the steps GIF can
#                   narrow it with resize-pane (VHS can't resize mid-tape)
set -eu

image=$1
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
# One fixed work dir, emptied on every run: the cache, agent stubs, and the
# pids of the delayed jobs, so a leftover job never acts on the next scene.
WORK=${TMPDIR:-/tmp}/tmux-ai-usage-demo
NOW=$(date +%s)

demo() { tmux -L ai-usage-demo "$@"; }
outer() { tmux -L ai-usage-outer "$@"; }

stop() {
  local pid
  if [ -f "$WORK/later.pids" ]; then
    while read -r pid; do kill "$pid" 2>/dev/null || true; done <"$WORK/later.pids"
  fi
  demo kill-server 2>/dev/null || true
  outer kill-server 2>/dev/null || true
  rm -rf "$WORK"
  mkdir -p "$WORK"
}

# Run a command in the background after a delay, while VHS records.
later() { # seconds command...
  local delay=$1
  shift
  (sleep "$delay"; "$@") >/dev/null 2>&1 </dev/null &
  echo $! >>"$WORK/later.pids"
}

# A shell with a plain prompt. Any arguments are printed first, as if typed.
shell_cmd() { # [line...]
  local lines=""
  [ $# -gt 0 ] && lines=$(printf '%s\\n' "$@")
  printf "printf '%s'; PS1='~/project \$ ' exec bash --norc --noprofile -i" "$lines"
}

# Copies of jq named like the agents: focus matches the pane's program name,
# and jq -n input waits on the terminal without forking. macOS kills copies
# of its own signed binaries (/bin/sleep, /usr/bin/jq), and a symlink reports
# its target's name, so this needs a jq installed outside /bin and /usr/bin.
stub_agents() {
  local jq
  jq=$(type -ap jq | grep -v -e '^/bin/' -e '^/usr/bin/' | head -n 1)
  if [ -z "$jq" ]; then
    echo "start.sh: the focus image needs a jq outside /usr/bin (brew install jq)" >&2
    exit 1
  fi
  mkdir -p "$WORK/bin"
  cp "$jq" "$WORK/bin/claude"
  cp "$jq" "$WORK/bin/codex"
}

preset=normal
real_clock=0 # 1: let time pass (rotation needs it); 0: freeze it at NOW
split=0      # 1: narrowable demo pane (steps)
pane=$(shell_cmd)
options=()

stop
if [ "$image" = --stop ]; then
  rm -rf "$WORK"
  exit 0
fi

case $image in
  hero)
    # shellcheck disable=SC2088 # a literal ~, printed as part of the prompt
    pane=$(shell_cmd '~/project $ git log --oneline -3' \
      'a41c2e9 Parse the new config format' \
      '7d03b18 Retry uploads on timeout' \
      'e9f2c47 Add the export command')
    ;;
  steps) split=1 ;;
  rotation)
    real_clock=1
    options=(@ai_usage_rotate on @ai_usage_rotate_interval 2)
    ;;
  focus)
    real_clock=1
    stub_agents
    options=(@ai_usage_focus on @ai_usage_rotate on @ai_usage_rotate_interval 2)
    ;;
  popup) preset=popup ;;
  problems) preset=problems ;;
  *)
    echo "start.sh: unknown image '$image'" >&2
    exit 1
    ;;
esac

"$HERE/make-snapshots.sh" "$preset" "$WORK/cache" "$NOW"

export AI_USAGE_NO_REFRESH=1 TZ=UTC BASH_SILENCE_DEPRECATION_WARNING=1
if [ "$real_clock" -eq 1 ]; then unset AI_USAGE_NOW; else export AI_USAGE_NOW=$NOW; fi
unset TMUX

# -f on the command that starts the server: a bare start-server would exit
# at once, and the next command would start one that reads ~/.tmux.conf.
demo -f "$HERE/demo.conf" new-session -d -s demo -x 110 -y 12 "$pane" \
  \; set -g @ai_usage_cache_dir "$WORK/cache"
for ((i = 0; i < ${#options[@]}; i += 2)); do
  demo set -g "${options[i]}" "${options[i + 1]}"
done

if [ "$image" = focus ]; then
  demo split-window -h -b -t demo:0.0 \
    "printf '~/project \$ claude\n'; exec '$WORK/bin/claude' -n input"
  demo split-window -h -t demo:0.0 \
    "printf '~/project \$ codex\n'; exec '$WORK/bin/codex' -n input"
  demo select-layout -t demo:0 even-horizontal
  demo select-pane -t demo:0.0
  later 6 demo select-pane -t demo:0.1
  later 9 demo select-pane -t demo:0.2
fi

demo run-shell "$REPO/ai_usage.tmux"

outer -f "$HERE/outer.conf" new-session -d -s outer -x "$(tput cols)" -y "$(tput lines)" \
  "tmux -L ai-usage-demo attach -t demo"
if [ "$split" -eq 1 ]; then
  outer split-window -h -t outer:0 "exec sleep 600" \; resize-pane -t outer:0.0 -x 110 \
    \; select-pane -t outer:0.0
  # Narrow through every step (with demo.conf's widths) and back.
  delay=3
  for width in 92 76 60 46 60 76 92 110; do
    later "$delay" outer resize-pane -t outer:0.0 -x "$width"
    delay=$((delay + 2))
  done
fi

exec tmux -L ai-usage-outer attach -t outer
