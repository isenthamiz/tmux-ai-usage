#!/bin/bash
# The #() target: prints one provider's usage bar from its cached usage snapshot.
# Never fetches; see refresh.sh.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/options.sh
. "$DIR/lib/options.sh"
# shellcheck source=scripts/lib/snapshot.sh
. "$DIR/lib/snapshot.sh"
# shellcheck source=scripts/lib/format.sh
. "$DIR/lib/format.sh"

provider=$1
now=${AI_USAGE_NOW:-$(date +%s)}
snapshot=$(snapshot_path "$provider")

load_options
case $provider in
  claude) PROVIDER_LABEL=$CLAUDE_LABEL ;;
  codex) PROVIDER_LABEL=$CODEX_LABEL ;;
  cursor) PROVIDER_LABEL=${CURSOR_LABEL:-cu} ;;
  *) PROVIDER_LABEL=$provider ;;
esac

maybe_start_refresh() {
  local fetched=${1:-0} retry=${2:-0}
  if [ ! -f "$snapshot" ] || { [ "$now" -ge "${retry:-0}" ] &&
      [ $((now - fetched)) -ge "$REFRESH_INTERVAL" ]; }; then
    ( "$DIR/refresh.sh" "$provider" </dev/null >/dev/null 2>&1 & )
  fi
}

if [ ! -f "$snapshot" ]; then
  maybe_start_refresh 0 0
  printf '#[fg=%s]%s …#[fg=default]\n' "$COLOR_DIM" "$PROVIDER_LABEL"
  exit 0
fi

# One jq call: status, ages, and the selected window (max used_pct).
read -r status fetched_at ok_at retry_at window_label used_pct resets_at has_windows < <(
  jq -r --argjson now "$now" '
    (.status // "error") as $st
    | (.fetched_at // 0) as $fa
    | (.ok_at // 0) as $oa
    | (.retry_at // 0) as $ra
    | (.windows | if length == 0 then null else max_by(.used_pct) end) as $w
    | [
        $st, $fa, $oa, $ra,
        ($w.label // ""), ($w.used_pct // 0), ($w.resets_at // 0),
        (if (.windows | length) > 0 then 1 else 0 end)
      ] | @tsv
  ' "$snapshot"
)

maybe_start_refresh "${fetched_at:-0}" "${retry_at:-0}"

case $status in
  signed_out)
    printf '#[fg=%s]%s !login#[fg=default]\n' "$COLOR_CRIT" "$PROVIDER_LABEL"
    exit 0 ;;
  missing_dep)
    printf '#[fg=%s]%s !deps#[fg=default]\n' "$COLOR_CRIT" "$PROVIDER_LABEL"
    exit 0 ;;
  bad_shape)
    printf '#[fg=%s]%s !format#[fg=default]\n' "$COLOR_CRIT" "$PROVIDER_LABEL"
    exit 0 ;;
esac

if [ "${has_windows:-0}" != 1 ] || [ -z "$window_label" ]; then
  if [ "$status" = error ]; then
    printf '#[fg=%s]%s !error#[fg=default]\n' "$COLOR_CRIT" "$PROVIDER_LABEL"
  else
    printf '#[fg=%s]%s …#[fg=default]\n' "$COLOR_DIM" "$PROVIDER_LABEL"
  fi
  exit 0
fi

# Pending: no successful reading yet, but windows present should not happen; treat as pending.
if [ -z "${ok_at:-}" ] || [ "$ok_at" = 0 ]; then
  printf '#[fg=%s]%s …#[fg=default]\n' "$COLOR_DIM" "$PROVIDER_LABEL"
  exit 0
fi

if [ "${resets_at:-0}" -le "$now" ]; then
  used_pct=0
  countdown_str=""
else
  countdown_str=$(countdown $((resets_at - now)))
fi

stale=0
if [ $((now - ok_at)) -gt "$STALE_AFTER" ]; then
  stale=1
fi

label_color=$COLOR_TEXT
dim_color=$COLOR_DIM
bar_color=$(usage_color "$used_pct")
tilde=""
if [ "$stale" -eq 1 ]; then
  label_color=$COLOR_DIM
  dim_color=$COLOR_DIM
  bar_color=$COLOR_DIM
  tilde='~'
fi

pct="${tilde}${used_pct}%"
bar=$(bar "$used_pct" "$BAR_WIDTH" "$BAR_FILLED" "$BAR_EMPTY")

if [ -n "$countdown_str" ]; then
  printf '#[fg=%s]%s #[fg=%s]%s #[fg=%s]%s %s #[fg=%s]%s#[fg=default]\n' \
    "$label_color" "$PROVIDER_LABEL" "$dim_color" "$window_label" \
    "$bar_color" "$bar" "$pct" "$dim_color" "$countdown_str"
else
  printf '#[fg=%s]%s #[fg=%s]%s #[fg=%s]%s %s#[fg=default]\n' \
    "$label_color" "$PROVIDER_LABEL" "$dim_color" "$window_label" \
    "$bar_color" "$bar" "$pct"
fi