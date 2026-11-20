#!/bin/bash
# The #() target: one provider's usage bar, or all providers for #{ai_usage}.
# Never fetches; see refresh.sh.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/options.sh
. "$DIR/lib/options.sh"
# shellcheck source=scripts/lib/snapshot.sh
. "$DIR/lib/snapshot.sh"
# shellcheck source=scripts/lib/format.sh
. "$DIR/lib/format.sh"

target=$1
now=${AI_USAGE_NOW:-$(date +%s)}

load_options

_row_var() { # provider suffix
  printf 'ROW_%s_%s' "$(echo "$1" | tr '[:lower:]' '[:upper:]')" "$2"
}

_store_row() {
  local prov=$1 status=$2 fetched_at=$3 ok_at=$4 retry_at=$5
  local window_label=$6 used_pct=$7 resets_at=$8 has_windows=$9
  local v
  v=$(_row_var "$prov" STATUS); printf -v "$v" '%s' "$status"
  v=$(_row_var "$prov" FETCHED_AT); printf -v "$v" '%s' "$fetched_at"
  v=$(_row_var "$prov" OK_AT); printf -v "$v" '%s' "$ok_at"
  v=$(_row_var "$prov" RETRY_AT); printf -v "$v" '%s' "$retry_at"
  v=$(_row_var "$prov" WINDOW_LABEL); printf -v "$v" '%s' "$window_label"
  v=$(_row_var "$prov" USED_PCT); printf -v "$v" '%s' "$used_pct"
  v=$(_row_var "$prov" RESETS_AT); printf -v "$v" '%s' "$resets_at"
  v=$(_row_var "$prov" HAS_WINDOWS); printf -v "$v" '%s' "$has_windows"
}

load_all_render_rows() {
  while IFS=$'\t' read -r prov status fetched_at ok_at retry_at \
    window_label used_pct resets_at has_windows; do
    _store_row "$prov" "$status" "$fetched_at" "$ok_at" "$retry_at" \
      "$window_label" "$used_pct" "$resets_at" "$has_windows"
  done < <(jq -r -n \
    --argjson now "$now" \
    --arg claude_pin "$CLAUDE_WINDOW" \
    --arg codex_pin "$CODEX_WINDOW" \
    --arg cursor_pin "$CURSOR_WINDOW" \
    --argjson claude "$(snapshot_json_for claude)" \
    --argjson codex "$(snapshot_json_for codex)" \
    --argjson cursor "$(snapshot_json_for cursor)" \
    -f "$DIR/lib/render_read.jq")
}

_get_row_field() {
  eval "printf '%s' \"\${$(_row_var "$1" "$2")}\""
}

maybe_start_refresh() {
  [ -n "${AI_USAGE_NO_REFRESH:-}" ] && return 0
  local provider=$1 fetched=${2:-0} retry=${3:-0}
  local snapshot
  snapshot=$(snapshot_path "$provider")
  if [ ! -f "$snapshot" ] || { [ "$now" -ge "${retry:-0}" ] &&
      [ $((now - fetched)) -ge "$REFRESH_INTERVAL" ]; }; then
    ( "$DIR/refresh.sh" "$provider" </dev/null >/dev/null 2>&1 & )
  fi
}

# Sets PIECE[0..4]: one provider's usage bar at full, step 1, step 2, step 3
# and step 4.
_set_piece_all() { # text: the same piece at every step
  PIECE=("$1" "$1" "$1" "$1" "$1")
}

_format_piece() {
  local provider=$1
  local status fetched_at ok_at retry_at window_label used_pct resets_at has_windows
  local provider_label snapshot
  provider_label=$(provider_label_for "$provider")
  snapshot=$(snapshot_path "$provider")

  status=$(_get_row_field "$provider" STATUS)
  fetched_at=$(_get_row_field "$provider" FETCHED_AT)
  ok_at=$(_get_row_field "$provider" OK_AT)
  retry_at=$(_get_row_field "$provider" RETRY_AT)
  window_label=$(_get_row_field "$provider" WINDOW_LABEL)
  used_pct=$(_get_row_field "$provider" USED_PCT)
  resets_at=$(_get_row_field "$provider" RESETS_AT)
  has_windows=$(_get_row_field "$provider" HAS_WINDOWS)

  local pending="#[fg=$COLOR_DIM]$provider_label …"
  local pending4="#[fg=$COLOR_DIM]$provider_label"

  if [ "$status" = pending ] || [ ! -f "$snapshot" ]; then
    maybe_start_refresh "$provider" 0 0
    _set_piece_all "$pending"; PIECE[4]=$pending4
    return 0
  fi

  maybe_start_refresh "$provider" "${fetched_at:-0}" "${retry_at:-0}"

  local marker=""
  case $status in
    signed_out) marker='!login' ;;
    missing_dep) marker='!deps' ;;
    bad_shape) marker='!format' ;;
    error)
      if [ "${has_windows:-0}" != 1 ] || [ -z "$window_label" ]; then
        marker='!error'
      fi ;;
  esac
  if [ -n "$marker" ]; then
    _set_piece_all "#[fg=$COLOR_CRIT]$provider_label $marker"
    PIECE[4]="#[fg=$COLOR_CRIT]$provider_label!"
    return 0
  fi

  if [ "${has_windows:-0}" != 1 ] || [ -z "$window_label" ] ||
     [ -z "${ok_at:-}" ] || [ "$ok_at" = 0 ]; then
    _set_piece_all "$pending"; PIECE[4]=$pending4
    return 0
  fi

  local countdown_str=""
  if [ "${resets_at:-0}" -le "$now" ]; then
    used_pct=0
  else
    countdown_str=$(countdown $((resets_at - now)))
  fi

  local label_color=$COLOR_TEXT dim=$COLOR_DIM bar_color tilde=""
  bar_color=$(usage_color "$used_pct")
  if [ $((now - ok_at)) -gt "$STALE_AFTER" ]; then
    label_color=$COLOR_DIM
    bar_color=$COLOR_DIM
    tilde='~'
  fi

  # What shows usage: the progress bar, or the percentage in its place.
  local pct="${tilde}${used_pct}%" usage
  if [ "$BAR_WIDTH" -gt 0 ]; then
    usage="${tilde}$(bar "$used_pct" "$BAR_WIDTH" "$BAR_FILLED" "$BAR_EMPTY")"
  else
    usage=$pct
  fi

  local cdn="" cd_crit=""
  [ -n "$countdown_str" ] && cdn=" #[fg=$dim]$countdown_str"
  [ "$used_pct" -ge "$CRIT_AT" ] && cd_crit=$cdn

  local head="#[fg=$label_color]$provider_label "
  PIECE[0]="$head#[fg=$dim]$window_label #[fg=$bar_color]$usage$cdn"
  PIECE[1]="$head#[fg=$bar_color]$usage$cdn"
  PIECE[2]="$head#[fg=$bar_color]$usage$cd_crit"
  PIECE[3]="$head#[fg=$bar_color]$pct$cd_crit"
  PIECE[4]="#[fg=$bar_color]$provider_label"
}

# Pieces for the providers in $@, joined per step into STEP_TEXT[0..4].
_build_steps() {
  local provider i
  STEP_TEXT=("" "" "" "" "")
  for provider in "$@"; do
    _format_piece "$provider"
    for i in 0 1 2 3 4; do
      if [ -n "${STEP_TEXT[$i]}" ]; then
        if [ "$i" -le 1 ]; then
          STEP_TEXT[i]="${STEP_TEXT[$i]}#[fg=${COLOR_DIM}]${SEPARATOR}"
        else
          STEP_TEXT[i]="${STEP_TEXT[$i]} "
        fi
      fi
      STEP_TEXT[i]="${STEP_TEXT[$i]}${PIECE[$i]}"
    done
  done
}

# Literal commas and closing braces would end a conditional branch early.
# Sets BRANCH (no subshell: render.sh runs on every redraw).
_escape_branch() {
  BRANCH=${1//,/#,}
  BRANCH=${BRANCH//\}/#\}}
}

# One step's text, or (auto on tmux >= 3.2) every step in a client_width
# conditional that tmux expands per client on each redraw.
_print_steps() {
  local i out widths
  case $STEP in
    full) out=${STEP_TEXT[0]} ;;
    1|2|3|4) out=${STEP_TEXT[$STEP]} ;;
    *)
      if [ "$TMUX_HAS_EXPR" != 1 ]; then
        out=${STEP_TEXT[0]}
      else
        # shellcheck disable=SC2206  # four integers, validated in load_options
        widths=($STEP_WIDTHS)
        _escape_branch "${STEP_TEXT[4]}"
        out=$BRANCH
        for i in 3 2 1 0; do
          _escape_branch "${STEP_TEXT[$i]}"
          out="#{?#{e|>=:#{client_width},${widths[$i]}},$BRANCH,$out}"
        done
      fi ;;
  esac
  printf '%s#[fg=default]\n' "$out"
}

load_all_render_rows

if [ "$target" = all ]; then
  # shellcheck disable=SC2086  # PROVIDERS is a space-separated list
  _build_steps $PROVIDERS
else
  _build_steps "$target"
fi
_print_steps
