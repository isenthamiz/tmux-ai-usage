#!/bin/bash
# Write hand-made usage snapshots for the README images (see docs/demo/start.sh).
# Usage: make-snapshots.sh <normal|popup|problems> <cache_dir> <now>
# Times are relative to <now>; fetched_at and retry_at lie far in the future,
# so the plugin never starts a refresh over these files.
set -eu

preset=$1 cache=$2 now=$3
HOUR=3600 WEEK=604800 FIVE_H=18000 NEVER=9999999999

mkdir -p "$cache"
chmod 700 "$cache"

window() { # label used_pct seconds_to_reset window_seconds
  printf '{"label":"%s","used_pct":%s,"resets_at":%s,"window_seconds":%s}' \
    "$1" "$2" $((now + $3)) "$4"
}

snapshot() { # provider status ok_at window_json...
  local provider=$1 status=$2 ok_at=$3 windows=""
  shift 3
  windows=$(IFS=,; printf '%s' "$*")
  printf '{"provider":"%s","status":"%s","fetched_at":%s,"ok_at":%s,"retry_at":%s,"error":null,"windows":[%s]}\n' \
    "$provider" "$status" "$NEVER" "$ok_at" "$NEVER" "$windows" >"$cache/$provider.json"
}

claude_5h=$(window 5h 30 7980 $FIVE_H)
claude_wk=$(window wk 71 274000 $WEEK)
codex_5h=$(window 5h 42 2820 $FIVE_H)
codex_wk=$(window wk 20 400000 $WEEK)
cursor_wk=$(window wk 23 353000 $WEEK)

# Codex has signed out; Cursor's last good reading is 3 hours old.
signed_out_codex() { snapshot codex signed_out "$((now - HOUR))" "$codex_5h" "$codex_wk"; }
stale_cursor() { snapshot cursor ok "$((now - 3 * HOUR))" "$(window wk 15 353000 $WEEK)"; }

case $preset in
  normal)
    snapshot claude ok "$now" "$claude_5h" "$claude_wk"
    snapshot codex ok "$now" "$codex_5h" "$codex_wk"
    snapshot cursor ok "$now" "$cursor_wk"
    ;;
  popup)
    snapshot claude ok "$now" "$claude_5h" "$claude_wk" "$(window wk-opus 48 274000 $WEEK)"
    signed_out_codex
    stale_cursor
    ;;
  problems)
    snapshot claude ok "$now" "$claude_5h" "$(window wk 62 274000 $WEEK)"
    signed_out_codex
    stale_cursor
    ;;
  *)
    echo "make-snapshots.sh: unknown preset '$preset'" >&2
    exit 1
    ;;
esac
