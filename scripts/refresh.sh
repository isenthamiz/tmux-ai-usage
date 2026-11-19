#!/bin/bash
# Refreshes one provider's usage snapshot: lock -> acquire | normalize -> atomic write.
# Started detached by render.sh; never prints to the status line.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/options.sh
. "$DIR/lib/options.sh"
# shellcheck source=scripts/lib/snapshot.sh
. "$DIR/lib/snapshot.sh"
# shellcheck source=scripts/lib/lock.sh
. "$DIR/lib/lock.sh"

provider=$1
now=${AI_USAGE_NOW:-$(date +%s)}
cache=$(cache_dir)
snapshot=$(snapshot_path "$provider")
lock="$cache/$provider.lock"

mkdir -p "$cache" && chmod 700 "$cache"
lock_acquire "$lock" || exit 0
trap 'lock_release "$lock"' EXIT

# Another refresh may have finished between the render's check and this lock.
load_options
fetched_at=$(jq -r '.fetched_at // 0' "$snapshot" 2>/dev/null || echo 0)
[ $((now - ${fetched_at:-0})) -lt "$REFRESH_INTERVAL" ] && exit 0

if raw=$("$DIR/providers/$provider/acquire.sh") &&
   new=$(printf '%s' "$raw" | jq --argjson now "$now" -L "$DIR/lib" -f "$DIR/providers/$provider/normalize.jq"); then
  :
else
  # Keep the last good windows; record the attempt so the renderer doesn't retry at once.
  new=$({ cat "$snapshot" 2>/dev/null || echo null; } | jq --argjson now "$now" --arg p "$provider" '
    (. // {provider: $p, ok_at: null, windows: []})
    | .status = "error" | .fetched_at = $now | .retry_at = $now | .error = "fetch failed"')
fi

tmp=$(mktemp "$cache/.$provider.XXXXXX") || exit 1
printf '%s\n' "$new" > "$tmp" && mv -f "$tmp" "$snapshot"
