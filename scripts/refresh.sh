#!/bin/bash
# Refreshes one provider's usage snapshot: lock -> dependency check -> acquire | normalize -> atomic write.
# Started detached by render.sh; never prints to the status line.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/options.sh
. "$DIR/lib/options.sh"
# shellcheck source=scripts/lib/snapshot.sh
. "$DIR/lib/snapshot.sh"
# shellcheck source=scripts/lib/lock.sh
. "$DIR/lib/lock.sh"
# shellcheck source=scripts/lib/deps.sh
. "$DIR/lib/deps.sh"
# shellcheck source=scripts/lib/watchdog.sh
. "$DIR/lib/watchdog.sh"

provider=$1
now=${AI_USAGE_NOW:-$(date +%s)}
cache=$(cache_dir)
snapshot=$(snapshot_path "$provider")
lock="$cache/$provider.lock"

_write_merged() {
  local merged ra=null
  [ -n "${retry_after:-}" ] && ra=$retry_after
  merged=$({ cat "$snapshot" 2>/dev/null || echo null; } |
    jq --argjson new "$1" --argjson now "$now" --argjson interval "$REFRESH_INTERVAL" \
       --argjson retry_after "$ra" -L "$DIR/lib" -f "$DIR/lib/merge.jq")
  tmp=$(mktemp "$cache/.$provider.XXXXXX") || exit 1
  printf '%s\n' "$merged" > "$tmp" && mv -f "$tmp" "$snapshot"
}

mkdir -p "$cache" && chmod 700 "$cache"
lock_acquire "$lock" || exit 0
trap 'lock_release "$lock"' EXIT

load_options

retry_at=$(jq -r '.retry_at // 0' "$snapshot" 2>/dev/null || echo 0)
[ "$now" -lt "${retry_at:-0}" ] && exit 0

fetched_at=$(jq -r '.fetched_at // 0' "$snapshot" 2>/dev/null || echo 0)
[ $((now - ${fetched_at:-0})) -lt "$REFRESH_INTERVAL" ] && exit 0

_acquire_failure_snapshot() { # status err
  jq -n --arg p "$provider" --argjson now "$now" --arg st "$1" --arg err "$2" \
    '{provider: $p, status: $st, fetched_at: $now, ok_at: null, error: $err, windows: []}'
}

if [ "$provider" = codex ]; then
  if ! find_binary curl >/dev/null; then
    _write_merged "$(_acquire_failure_snapshot missing_dep "curl not found")"
    exit 0
  fi
fi

err=$(mktemp)
retry_after=""
raw_response=""

acquire_rc=0
raw_response=$(run_with_timeout 20 "$DIR/providers/$provider/acquire.sh" 2>"$err") || acquire_rc=$?
if [ "$acquire_rc" -ne 0 ]; then
  case "$acquire_rc" in
    2)
      new_snapshot=$(_acquire_failure_snapshot signed_out "$(head -1 "$err")")
      ;;
    124)
      new_snapshot=$(_acquire_failure_snapshot error "acquire timed out")
      ;;
    *)
      err_msg=$(head -1 "$err")
      [ -z "$err_msg" ] && err_msg="fetch failed"
      if grep -q '^retry_after=' "$err" 2>/dev/null; then
        retry_after=$(grep '^retry_after=' "$err" | head -1 | cut -d= -f2-)
        err_msg="HTTP 429 from wham/usage"
      fi
      new_snapshot=$(_acquire_failure_snapshot error "$err_msg")
      ;;
  esac
elif ! new_snapshot=$(printf '%s' "$raw_response" |
    jq --argjson now "$now" -L "$DIR/lib" -f "$DIR/providers/$provider/normalize.jq"); then
  new_snapshot=$(_acquire_failure_snapshot error "normalize failed")
else
  retry_after=""
fi

rm -f "$err"
_write_merged "$new_snapshot"