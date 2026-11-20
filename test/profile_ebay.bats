#!/usr/bin/env bats
load test_helper

NOW=1795074751

setup() {
  setup_env
  export AI_USAGE_PROFILE=ebay
  mkdir -p "$CACHE/ebay-capture"
  jq -n '{provider:"codex",mtd_usd:30,cap_usd:150}' >"$CACHE/ebay-capture/codex.json"
}

teardown() {
  unset AI_USAGE_PROFILE
}

@test "ebay refresh uses capture and writes ok snapshot" {
  AI_USAGE_NOW=$NOW run refresh codex
  [ "$status" -eq 0 ]
  [ "$(jq -r '.status' "$CACHE/codex.json")" = ok ]
  [ "$(jq -r '.windows[0].label' "$CACHE/codex.json")" = mo ]
  [ "$(jq -r '.windows[0].used_pct' "$CACHE/codex.json")" = 20 ]
}