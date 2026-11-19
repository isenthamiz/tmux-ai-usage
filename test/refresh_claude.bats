#!/usr/bin/env bats
# shellcheck disable=SC2016,SC2030,SC2031
load test_helper

setup() {
  setup_env
  setup_claude five-hour-weekly
  unset CLAUDE_SHIM_EXIT CLAUDE_SHIM_STDERR
}

NOW=1795074751

@test "refresh writes a live Claude snapshot from get_usage" {
  seed_snapshot_claude five-hour-weekly $((NOW - 120))
  AI_USAGE_NOW=$NOW run refresh claude
  [ "$(jq -r '.status' "$CACHE/claude.json")" = "ok" ]
  # A live reading is stamped now; the cache fallback would carry its own older fetchedAtMs.
  [ "$(jq -r '.ok_at' "$CACHE/claude.json")" = "$NOW" ]
  [ "$(jq -c '[.windows[].label]' "$CACHE/claude.json")" = '["5h","wk"]' ]
  [ "$(claude_calls)" = 1 ]
}

@test "missing claude CLI is missing_dep" {
  seed_snapshot_claude five-hour-weekly $((NOW - 120))
  export AI_USAGE_TEST_NO_CLAUDE=1
  AI_USAGE_NOW=$NOW run refresh claude
  unset AI_USAGE_TEST_NO_CLAUDE
  [ "$(jq -r .status "$CACHE/claude.json")" = "missing_dep" ]
}

@test "not signed in is signed_out" {
  seed_snapshot_claude five-hour-weekly $((NOW - 120))
  export CLAUDE_SHIM_EXIT=2
  printf 'not logged in\n' >"$BATS_TEST_TMPDIR/claude-err.txt"
  export CLAUDE_SHIM_STDERR="$BATS_TEST_TMPDIR/claude-err.txt"
  AI_USAGE_NOW=$NOW run refresh claude
  [ "$(jq -r .status "$CACHE/claude.json")" = "signed_out" ]
}

@test "429 on get_usage records error with Retry-After back-off" {
  seed_snapshot_claude five-hour-weekly $((NOW - 120))
  export CLAUDE_SHIM_EXIT=1
  printf 'HTTP 429 rate limit\nretry_after: 120\n' >"$BATS_TEST_TMPDIR/claude-429.txt"
  export CLAUDE_SHIM_STDERR="$BATS_TEST_TMPDIR/claude-429.txt"
  AI_USAGE_NOW=$NOW run refresh claude
  [ "$(jq -r .status "$CACHE/claude.json")" = "error" ]
  [ "$(jq .retry_at "$CACHE/claude.json")" = "$((NOW + 120))" ]
}

@test "get_usage failure falls back to cachedUsageUtilization" {
  seed_snapshot_claude five-hour-weekly $((NOW - 120))
  export CLAUDE_SHIM_EXIT=1
  unset CLAUDE_SHIM_STDERR
  export CLAUDE_CONFIG="$BATS_TEST_TMPDIR/claude.json"
  jq -n --argjson ms $((NOW * 1000 - 60000)) \
    '{cachedUsageUtilization:{fetchedAtMs:$ms,utilization:{five_hour:{utilization:9,resets_at:"2026-11-19T15:00:00Z"},seven_day:{utilization:33,resets_at:"2026-11-26T10:00:00Z"}}}}' \
    >"$CLAUDE_CONFIG"
  AI_USAGE_NOW=$NOW run refresh claude
  [ "$(jq -r .status "$CACHE/claude.json")" = "ok" ]
  [ "$(jq .ok_at "$CACHE/claude.json")" = "$((NOW - 60))" ]
  [ "$(claude_calls)" = 1 ]
}