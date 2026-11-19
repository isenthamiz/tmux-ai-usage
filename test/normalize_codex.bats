#!/usr/bin/env bats
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

@test "a response without the known rate_limit shape is bad_shape with no windows" {
  run normalize malformed 1795074751
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -c '{status, windows, error}')" = '{"status":"bad_shape","windows":[],"error":"unrecognised wham/usage response"}' ]
}

# A response holding one primary window with the given length and usage.
normalize_window() { # window_seconds used_percent
  jq -n --argjson s "$1" --argjson p "$2" \
    '{rate_limit: {primary_window: {used_percent: $p, limit_window_seconds: $s, reset_after_seconds: 1, reset_at: 1795074752}, secondary_window: null}}' |
    jq --argjson now 1795074751 -L "$ROOT/scripts/lib" -f "$ROOT/scripts/providers/codex/normalize.jq"
}

@test "unusual window lengths are labelled with the compact duration" {
  for case in "5400 1h30m" "86400 1d" "93600 1d2h" "2700 45m" "18000 5h" "604800 wk"; do
    read -r secs want <<<"$case"
    got=$(normalize_window "$secs" 10 | jq -r '.windows[0].label')
    [ "$got" = "$want" ] || { echo "for $secs s: got '$got', want '$want'"; return 1; }
  done
}

@test "a fractional usage is rounded to a whole percentage" {
  [ "$(normalize_window 18000 66.6 | jq '.windows[0].used_pct')" = 67 ]
  [ "$(normalize_window 18000 0.4 | jq '.windows[0].used_pct')" = 0 ]
}
