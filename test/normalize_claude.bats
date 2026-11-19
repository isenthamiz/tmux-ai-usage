#!/usr/bin/env bats
load test_helper

normalize() { # fixture now
  jq --argjson now "$2" -L "$ROOT/scripts/lib" -f "$ROOT/scripts/providers/claude/normalize.jq" \
    "$FIXTURES/claude/$1.json"
}

NOW=1795074751

@test "five_hour and seven_day become 5h then wk" {
  windows=$(normalize five-hour-weekly "$NOW" | jq -S -c '.windows')
  [ "$windows" = '[{"label":"5h","resets_at":1795100400,"used_pct":28,"window_seconds":18000},{"label":"wk","resets_at":1795687200,"used_pct":67,"window_seconds":604800}]' ]
}

@test "model-scoped weekly windows are labelled wk-opus" {
  run normalize with-model-scoped "$NOW"
  [ "$status" -eq 0 ]
  labels=$(echo "$output" | jq -c '[.windows[].label]')
  [ "$labels" = '["5h","wk","wk-opus"]' ]
}

@test "a response without quota windows is bad_shape" {
  run normalize malformed "$NOW"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -c '{status, windows, error}')" = \
    '{"status":"bad_shape","windows":[],"error":"unrecognised Claude usage response"}' ]
}

@test "cache fallback uses fetchedAtMs as ok_at" {
  out=$(jq -n \
    '{source:"cache",fetchedAtMs:1795070000000,
      rate_limits:{five_hour:{utilization:5,resets_at:"2026-11-19T15:00:00Z"},seven_day:null}}' |
    jq --argjson now "$NOW" -L "$ROOT/scripts/lib" -f "$ROOT/scripts/providers/claude/normalize.jq")
  [ "$(echo "$out" | jq -c '{ok_at, fetched_at, windows: [.windows[].label]}')" = \
    '{"ok_at":1795070000,"fetched_at":1795074751,"windows":["5h"]}' ]
}