#!/bin/bash
# Manual live check: one real fetch per provider, usage numbers only. Not for CI.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/options.sh
. "$DIR/lib/options.sh"
# shellcheck source=scripts/lib/snapshot.sh
. "$DIR/lib/snapshot.sh"
# shellcheck source=scripts/lib/deps.sh
. "$DIR/lib/deps.sh"
# shellcheck source=scripts/lib/watchdog.sh
. "$DIR/lib/watchdog.sh"
# shellcheck source=scripts/lib/providers.sh
. "$DIR/lib/providers.sh"

now=${AI_USAGE_NOW:-$(date +%s)}
load_options

_acquire_failure_snapshot() { # provider status err
  jq -n --arg p "$1" --argjson now "$now" --arg st "$2" --arg err "$3" \
    '{provider: $p, status: $st, fetched_at: $now, ok_at: null, error: $err, windows: []}'
}

_smoke_fetch() { # provider
  local provider=$1 err acquire_rc raw new_snapshot acquire_script normalize_jq
  acquire_script=$(provider_acquire_path "$DIR" "$provider" "$PROFILE") || {
    echo "smoke: no acquire for profile $PROFILE provider $provider" >&2
    return 1
  }
  normalize_jq=$(provider_normalize_path "$DIR" "$provider" "$PROFILE") || {
    echo "smoke: no normalize for profile $PROFILE provider $provider" >&2
    return 1
  }
  err=$(mktemp)
  acquire_rc=0
  raw=$(run_with_timeout 20 "$acquire_script" 2>"$err") || acquire_rc=$?
  if [ "$acquire_rc" -ne 0 ]; then
    case "$acquire_rc" in
      2) new_snapshot=$(_acquire_failure_snapshot "$provider" signed_out "$(head -1 "$err")") ;;
      3) new_snapshot=$(_acquire_failure_snapshot "$provider" missing_dep "$(head -1 "$err")") ;;
      124) new_snapshot=$(_acquire_failure_snapshot "$provider" error "acquire timed out") ;;
      *)
        new_snapshot=$(_acquire_failure_snapshot "$provider" error "$(head -1 "$err")")
        ;;
    esac
  elif ! new_snapshot=$(printf '%s' "$raw" |
      jq --argjson now "$now" -L "$DIR/lib" -f "$normalize_jq"); then
    new_snapshot=$(_acquire_failure_snapshot "$provider" error "normalize failed")
  fi
  rm -f "$err"
  printf '%s\n' "$new_snapshot" | jq -f "$DIR/lib/smoke_print.jq"
}

if ! command -v jq >/dev/null 2>&1; then
  echo "smoke: jq not found" >&2
  exit 1
fi

_print_missing_dep() { # provider dep_name
  _acquire_failure_snapshot "$1" missing_dep "$2 not found" | jq -f "$DIR/lib/smoke_print.jq"
}

for p in $(list_providers "$DIR"); do
  if ! provider_refresh_deps_ok "$p" "$PROFILE" >/dev/null 2>&1; then
    dep=$(provider_refresh_deps_ok "$p" "$PROFILE" 2>&1 || true)
    _print_missing_dep "$p" "$dep"
    continue
  fi
  _smoke_fetch "$p"
done