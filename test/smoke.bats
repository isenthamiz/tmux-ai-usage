#!/usr/bin/env bats
# Live smoke is manual; these tests use PATH shims only.
# shellcheck disable=SC2030,SC2031
load test_helper

smoke() { "$ROOT/scripts/smoke.sh"; }

setup() {
  setup_env
  NOW=1795074751
}

@test "smoke fetches each provider and prints usage-only JSON" {
  setup_codex primary-only
  setup_claude five-hour-weekly
  setup_cursor unified
  AI_USAGE_NOW=$NOW run smoke
  [ "$status" -eq 0 ]
  [ "$(curl_calls)" -ge 1 ]
  [ "$(claude_calls)" -ge 1 ]
  echo "$output" | grep -q '"used_pct"'
  echo "$output" | grep -qE '"provider":\s*"(codex|claude|cursor)"'
  [[ "$output" != *access_token* ]]
  [[ "$output" != *test-token* ]]
}