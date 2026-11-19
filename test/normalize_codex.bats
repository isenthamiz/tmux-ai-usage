load test_helper

normalize() { # fixture now
  jq --argjson now "$2" -L "$ROOT/scripts/lib" -f "$ROOT/scripts/providers/codex/normalize.jq" "$FIXTURES/codex/$1.json"
}

@test "a Plus account with only a weekly window yields one wk window" {
  run normalize primary-only 1795074751
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | canon)" = '{"error":null,"fetched_at":1795074751,"ok_at":1795074751,"provider":"codex","retry_at":1795074751,"status":"ok","windows":[{"label":"wk","resets_at":1795252665,"used_pct":66,"window_seconds":604800}]}' ]
}

@test "an account with 5-hour and weekly windows yields 5h then wk" {
  run normalize primary-secondary 1795074751
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -c '.windows')" = '[{"label":"5h","used_pct":81,"resets_at":1795077571,"window_seconds":18000},{"label":"wk","used_pct":35,"resets_at":1795514751,"window_seconds":604800}]' ]
}
