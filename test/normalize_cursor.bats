#!/usr/bin/env bats
load test_helper

normalize() { # fixture now
  jq --argjson now "$2" -L "$ROOT/scripts/lib" -f "$ROOT/scripts/providers/cursor/normalize.jq" "$FIXTURES/cursor/$1.json"
}

NOW=1795074751

@test "a unified account yields one wk window from usagePercent" {
  run normalize unified-weekly "$NOW"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r .status)" = "ok" ]
  [ "$(echo "$output" | jq -c '[.windows[].label]')" = '["wk"]' ]
  [ "$(echo "$output" | jq '.windows[0].used_pct')" = 58 ]
  [ "$(echo "$output" | jq '.windows[0].resets_at')" = 1795252665 ]
  [ "$(echo "$output" | jq '.windows[0].window_seconds')" = 604800 ]
}

@test "a legacy account yields mo-auto and mo-api" {
  run normalize legacy-two-pools "$NOW"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -c '[.windows[] | {label, used_pct}]')" = '[{"label":"mo-auto","used_pct":45},{"label":"mo-api","used_pct":12}]' ]
}

@test "an unrecognised shape is bad_shape with no windows" {
  run normalize malformed "$NOW"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -c '{status, windows, error}')" = '{"status":"bad_shape","windows":[],"error":"unrecognised Cursor usage response"}' ]
}