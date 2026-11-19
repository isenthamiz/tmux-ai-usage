#!/bin/bash
# TPM entrypoint: replaces the plugin's tokens in status-left/right with #() calls.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

interpolate() {
  local value=$1
  value=${value//\#\{ai_usage\}/#(\'$DIR/scripts/render.sh\' all)}
  value=${value//\#\{ai_usage_claude\}/#(\'$DIR/scripts/render.sh\' claude)}
  value=${value//\#\{ai_usage_codex\}/#(\'$DIR/scripts/render.sh\' codex)}
  value=${value//\#\{ai_usage_cursor\}/#(\'$DIR/scripts/render.sh\' cursor)}
  printf '%s' "$value"
}

for option in status-left status-right; do
  value=$(tmux show-option -gqv "$option")
  tmux set-option -gq "$option" "$(interpolate "$value")"
done
