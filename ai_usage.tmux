#!/bin/bash
# TPM entrypoint: validate options, check jq, replace the plugin's tokens in status-left/right with #() calls.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/validate.sh
. "$DIR/scripts/lib/validate.sh"

interpolate_cmd() {
  local value=$1 all_args=''
  # Focus needs the active pane's command and tty; tmux expands these per
  # client and re-runs the job at once when they change.
  if [ "$FOCUS" = on ]; then
    all_args=' #{q:pane_current_command} #{q:pane_tty}'
  fi
  value=${value//\#\{ai_usage\}/#(\'$DIR/scripts/render.sh\' all$all_args)}
  value=${value//\#\{ai_usage_claude\}/#(\'$DIR/scripts/render.sh\' claude)}
  value=${value//\#\{ai_usage_codex\}/#(\'$DIR/scripts/render.sh\' codex)}
  value=${value//\#\{ai_usage_cursor\}/#(\'$DIR/scripts/render.sh\' cursor)}
  printf '%s' "$value"
}

interpolate_jq_missing() {
  local value=$1 crit=$2
  local token='#[fg='"$crit"']!jq'
  value=${value//\#\{ai_usage\}/$token}
  value=${value//\#\{ai_usage_claude\}/$token}
  value=${value//\#\{ai_usage_codex\}/$token}
  value=${value//\#\{ai_usage_cursor\}/$token}
  printf '%s' "$value"
}

validate_ai_usage_options
# Read once here: it changes the token rewrite, so it needs a reload.
FOCUS=$(tmux show-options -gqv @ai_usage_focus 2>/dev/null)

if ! command -v jq >/dev/null 2>&1 || ! jq -n null >/dev/null 2>&1; then
  tmux display-message 'tmux-ai-usage: jq not found'
  crit=$(_crit_colour_at_load)
  for option in status-left status-right; do
    value=$(tmux show-option -gqv "$option")
    tmux set-option -gq "$option" "$(interpolate_jq_missing "$value" "$crit")"
  done
  exit 0
fi

for option in status-left status-right; do
  value=$(tmux show-option -gqv "$option")
  tmux set-option -gq "$option" "$(interpolate_cmd "$value")"
done

# prefix + @ai_usage_details_key opens the details popup. Unset means `u`;
# set to "" binds nothing, which only the name-and-value form can tell apart.
details_key=u
line=$(tmux show-options -gq @ai_usage_details_key 2>/dev/null)
if [ -n "$line" ]; then
  details_key=${line#* }
  case $details_key in \"*\"|\'*\') details_key=${details_key:1:${#details_key}-2} ;; esac
fi
if [ -n "$details_key" ]; then
  # details.sh measures its body and opens a popup of that size; tmux fills
  # in which client pressed the key and how big it is.
  tmux bind-key -T prefix "$details_key" run-shell -b \
    "'$DIR/scripts/details.sh' --open #{q:client_name} #{client_width} #{client_height}"
fi
