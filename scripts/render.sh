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

maybe_start_refresh() {
  local provider=$1 fetched=${2:-0} retry=${3:-0}
  local snapshot
  snapshot=$(snapshot_path "$provider")
  if [ ! -f "$snapshot" ] || { [ "$now" -ge "${retry:-0}" ] &&
      [ $((now - fetched)) -ge "$REFRESH_INTERVAL" ]; }; then
    ( "$DIR/refresh.sh" "$provider" </dev/null >/dev/null 2>&1 & )
  fi
}

# Prints one provider piece (no trailing #[fg=default]).
render_piece() {
  local provider=$1 window_pin=$2
  local snapshot provider_label
  snapshot=$(snapshot_path "$provider")
  provider_label=$(provider_label_for "$provider")

  if [ ! -f "$snapshot" ]; then
    maybe_start_refresh "$provider" 0 0
    printf '#[fg=%s]%s …' "$COLOR_DIM" "$provider_label"
    return 0
  fi

  read -r status fetched_at ok_at retry_at window_label used_pct resets_at has_windows < <(
    jq -r --argjson now "$now" --arg pin "$window_pin" '
      def effective_pct($w):
        if ($w.resets_at // 0) <= $now then 0 else $w.used_pct end;
      def auto_pick($ws):
        $ws | max_by(effective_pct(.));
      def pick($ws):
        if ($ws | length) == 0 then null
        elif $pin != "auto" then
          (([$ws[] | select(.label == $pin)][0]) // null) as $fixed
          | if $fixed == null then auto_pick($ws) else $fixed end
        else auto_pick($ws) end;
      (.status // "error") as $st
      | (.fetched_at // 0) as $fa
      | (.ok_at // 0) as $oa
      | (.retry_at // 0) as $ra
      | (.windows // []) as $ws
      | (pick($ws)) as $w
      | [
          $st, $fa, $oa, $ra,
          ($w.label // ""), ($w.used_pct // 0), ($w.resets_at // 0),
          (if ($ws | length) > 0 then 1 else 0 end)
        ] | @tsv
    ' "$snapshot"
  )

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
  bar=$(bar "$used_pct" "$BAR_WIDTH" "$BAR_FILLED" "$BAR_EMPTY")

  if [ -n "$countdown_str" ]; then
    printf '#[fg=%s]%s #[fg=%s]%s #[fg=%s]%s %s #[fg=%s]%s' \
      "$label_color" "$provider_label" "$dim_color" "$window_label" \
      "$bar_color" "$bar" "$pct" "$dim_color" "$countdown_str"
  else
    printf '#[fg=%s]%s #[fg=%s]%s #[fg=%s]%s %s' \
      "$label_color" "$provider_label" "$dim_color" "$window_label" \
      "$bar_color" "$bar" "$pct"
  fi
}

render_provider() {
  local provider=$1
  render_piece "$provider" "$(window_pin_for "$provider")"
  printf '#[fg=default]\n'
}

if [ "$target" = all ]; then
  combined=""
  for provider in $PROVIDERS; do
    if [ -n "$combined" ]; then
      combined="${combined}#[fg=${COLOR_DIM}]${SEPARATOR}"
    fi
    piece=$(render_piece "$provider" "$(window_pin_for "$provider")")
    combined="${combined}${piece}"
  done
  printf '%s#[fg=default]\n' "$combined"
  exit 0
fi

render_provider "$target"