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
# shellcheck source=scripts/lib/providers.sh
. "$DIR/lib/providers.sh"

provider=${1:-}
# An empty or unknown name would write a snapshot such as ".json" in the cache.
if [ -z "$provider" ] || ! list_providers "$DIR" | grep -qx "$provider"; then
  echo "usage: refresh.sh <$(list_providers "$DIR" | paste -sd'|' -)>" >&2
  exit 2
fi
now=${AI_USAGE_NOW:-$(date +%s)}
load_options
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

retry_at=$(jq -r '.retry_at // 0' "$snapshot" 2>/dev/null || echo 0)
[ "$now" -lt "${retry_at:-0}" ] && exit 0

fetched_at=$(jq -r '.fetched_at // 0' "$snapshot" 2>/dev/null || echo 0)
[ $((now - ${fetched_at:-0})) -lt "$REFRESH_INTERVAL" ] && exit 0

_acquire_failure_snapshot() { # status err
  jq -n --arg p "$provider" --argjson now "$now" --arg st "$1" --arg err "$2" \
    '{provider: $p, status: $st, fetched_at: $now, ok_at: null, error: $err, windows: []}'
}

if ! provider_refresh_deps_ok "$provider" "$PROFILE" >/dev/null; then
  dep_msg=$(provider_refresh_deps_ok "$provider" "$PROFILE" 2>&1 || true)
  _write_merged "$(_acquire_failure_snapshot missing_dep "$dep_msg")"
  exit 0
fi

acquire_script=""
if ! acquire_script=$(provider_acquire_path "$DIR" "$provider" "$PROFILE"); then
  _write_merged "$(_acquire_failure_snapshot error "no acquire script for profile $PROFILE")"
  exit 0
fi

normalize_jq=""
if ! normalize_jq=$(provider_normalize_path "$DIR" "$provider" "$PROFILE"); then
  _write_merged "$(_acquire_failure_snapshot error "no normalize filter for profile $PROFILE")"
  exit 0
fi

err=$(mktemp)
retry_after=""
raw_response=""

acquire_rc=0
raw_response=$(run_with_timeout 20 "$acquire_script" 2>"$err") || acquire_rc=$?
if [ "$acquire_rc" -ne 0 ]; then
  case "$acquire_rc" in
    2)
      new_snapshot=$(_acquire_failure_snapshot signed_out "$(head -1 "$err")")
      ;;
    3)
      new_snapshot=$(_acquire_failure_snapshot missing_dep "$(head -1 "$err")")
      ;;
    124)
      new_snapshot=$(_acquire_failure_snapshot error "acquire timed out")
      ;;
    *)
      err_msg=$(head -1 "$err")
      [ -z "$err_msg" ] && err_msg="fetch failed"
      if grep -q '^retry_after=' "$err" 2>/dev/null; then
        retry_after=$(grep '^retry_after=' "$err" | head -1 | cut -d= -f2-)
        err_msg="HTTP 429"
      fi
      new_snapshot=$(_acquire_failure_snapshot error "$err_msg")
      ;;
  esac
elif ! new_snapshot=$(printf '%s' "$raw_response" |
    jq --argjson now "$now" -L "$DIR/lib" -f "$normalize_jq"); then
  new_snapshot=$(_acquire_failure_snapshot error "normalize failed")
else
  retry_after=""
fi

rm -f "$err"
_write_merged "$new_snapshot"