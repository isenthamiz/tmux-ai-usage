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

# One jq call: when the snapshot was fetched, and its most-used window.
fetched_at="" window_label="" used_pct="" resets_at=""
[ -f "$snapshot" ] && IFS=$'\t' read -r fetched_at window_label used_pct resets_at < <(
  jq -r '[.fetched_at, (.windows | max_by(.used_pct) // {} | .label, .used_pct, .resets_at)] | @tsv' "$snapshot"
)

# Stale-while-revalidate: start a detached refresh, then draw what's cached.
if [ -z "$fetched_at" ] || [ $((now - fetched_at)) -ge "$REFRESH_INTERVAL" ]; then
  ( "$DIR/refresh.sh" "$provider" </dev/null >/dev/null 2>&1 & )
fi
[ -n "$window_label" ] || exit 0

color=$(usage_color "$used_pct")
printf '#[fg=%s]%s #[fg=%s]%s #[fg=%s]%s %s%% #[fg=%s]%s#[fg=default]\n' \
  "$COLOR_TEXT" "$CODEX_LABEL" "$COLOR_DIM" "$window_label" \
  "$color" "$(bar "$used_pct" "$BAR_WIDTH" "$BAR_FILLED" "$BAR_EMPTY")" "$used_pct" \
  "$COLOR_DIM" "$(countdown $((resets_at - now)))"
