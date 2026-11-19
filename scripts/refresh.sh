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

if ! raw_response=$("$DIR/providers/$provider/acquire.sh") ||
   ! new_snapshot=$(printf '%s' "$raw_response" |
       jq --argjson now "$now" -L "$DIR/lib" -f "$DIR/providers/$provider/normalize.jq"); then
  new_snapshot=$(jq -n --arg p "$provider" --argjson now "$now" \
    '{provider: $p, status: "error", fetched_at: $now, ok_at: null, error: "fetch failed", windows: []}')
fi

# A reading that isn't ok never replaces the last good windows; it records the
# attempt and waits a refresh interval before the next one.
merged=$({ cat "$snapshot" 2>/dev/null || echo null; } |
  jq --argjson new "$new_snapshot" --argjson next $((now + REFRESH_INTERVAL)) '
    if $new.status == "ok" then $new
    else (. // {provider: $new.provider, ok_at: null, windows: []})
         + {status: $new.status, error: $new.error, fetched_at: $new.fetched_at, retry_at: $next}
    end')

tmp=$(mktemp "$cache/.$provider.XXXXXX") || exit 1
printf '%s\n' "$merged" > "$tmp" && mv -f "$tmp" "$snapshot"
