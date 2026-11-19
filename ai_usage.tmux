#!/bin/bash
# TPM entrypoint: replaces the plugin's tokens in status-left/right with #() calls.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

interpolate() {
  local value=$1
  value=${value//\#\{ai_usage_codex\}/#(\'$DIR/scripts/render.sh\' codex)}
  printf '%s' "$value"
}

for option in status-left status-right; do
  value=$(tmux show-option -gqv "$option")
  tmux set-option -gq "$option" "$(interpolate "$value")"
done
