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

  if [ "$status" = pending ] || [ ! -f "$snapshot" ]; then
    maybe_start_refresh "$provider" 0 0
    printf '#[fg=%s]%s …' "$COLOR_DIM" "$provider_label"
    return 0
  fi

  maybe_start_refresh "$provider" "${fetched_at:-0}" "${retry_at:-0}"

  case $status in
    signed_out)
      printf '#[fg=%s]%s !login' "$COLOR_CRIT" "$provider_label"
      return 0 ;;
    missing_dep)
      printf '#[fg=%s]%s !deps' "$COLOR_CRIT" "$provider_label"
      return 0 ;;
    bad_shape)
      printf '#[fg=%s]%s !format' "$COLOR_CRIT" "$provider_label"
      return 0 ;;
  esac

  if [ "${has_windows:-0}" != 1 ] || [ -z "$window_label" ]; then
    if [ "$status" = error ]; then
      printf '#[fg=%s]%s !error' "$COLOR_CRIT" "$provider_label"
    else
      printf '#[fg=%s]%s …' "$COLOR_DIM" "$provider_label"
    fi
    return 0
  fi

  if [ -z "${ok_at:-}" ] || [ "$ok_at" = 0 ]; then
    printf '#[fg=%s]%s …' "$COLOR_DIM" "$provider_label"
    return 0
  fi

  local countdown_str=""
  if [ "${resets_at:-0}" -le "$now" ]; then
    used_pct=0
  else
    countdown_str=$(countdown $((resets_at - now)))
  fi

  local stale=0 label_color dim_color bar_color tilde pct bar
  if [ $((now - ok_at)) -gt "$STALE_AFTER" ]; then
    stale=1
  fi

  label_color=$COLOR_TEXT
  dim_color=$COLOR_DIM
  bar_color=$(usage_color "$used_pct")
  tilde=""
  if [ "$stale" -eq 1 ]; then
    label_color=$COLOR_DIM
    bar_color=$COLOR_DIM
    tilde='~'
  fi

  pct="${tilde}${used_pct}%"
  bar=""
  if [ "$BAR_WIDTH" -gt 0 ]; then
    bar=$(bar "$used_pct" "$BAR_WIDTH" "$BAR_FILLED" "$BAR_EMPTY")
  fi

  if [ -n "$countdown_str" ]; then
    if [ -n "$bar" ]; then
      printf '#[fg=%s]%s #[fg=%s]%s #[fg=%s]%s %s #[fg=%s]%s' \
        "$label_color" "$provider_label" "$dim_color" "$window_label" \
        "$bar_color" "$bar" "$pct" "$dim_color" "$countdown_str"
    else
      printf '#[fg=%s]%s #[fg=%s]%s #[fg=%s]%s #[fg=%s]%s' \
        "$label_color" "$provider_label" "$dim_color" "$window_label" \
        "$bar_color" "$pct" "$dim_color" "$countdown_str"
    fi
  else
    if [ -n "$bar" ]; then
      printf '#[fg=%s]%s #[fg=%s]%s #[fg=%s]%s %s' \
        "$label_color" "$provider_label" "$dim_color" "$window_label" \
        "$bar_color" "$bar" "$pct"
    else
      printf '#[fg=%s]%s #[fg=%s]%s #[fg=%s]%s' \
        "$label_color" "$provider_label" "$dim_color" "$window_label" \
        "$bar_color" "$pct"
    fi
  fi
}

render_piece() {
  _format_piece "$1"
}

render_provider() {
  local provider=$1
  render_piece "$provider"
  printf '#[fg=default]\n'
}

load_all_render_rows

if [ "$target" = all ]; then
  combined=""
  for provider in $PROVIDERS; do
    if [ -n "$combined" ]; then
      combined="${combined}#[fg=${COLOR_DIM}]${SEPARATOR}"
    fi
    piece=$(_format_piece "$provider")
    combined="${combined}${piece}"
  done
  printf '%s#[fg=default]\n' "$combined"
  exit 0
fi

render_provider "$target"