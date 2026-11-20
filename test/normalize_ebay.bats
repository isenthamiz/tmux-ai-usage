#!/usr/bin/env bats
load test_helper

NOW=1795074751

@test "ebay monthly capture normalizes to mo window" {
  run jq --argjson now "$NOW" -L "$ROOT/scripts/lib" -f "$ROOT/scripts/lib/normalize.ebay.jq" <<'JSON'
{"provider":"claude","mtd_usd":75,"cap_usd":150,"resets_at":1795687200,"window_seconds":2592000}
JSON
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -c '{status,label:.windows[0].label,pct:.windows[0].used_pct}')" = \
    '{"status":"ok","label":"mo","pct":50}' ]
}

@test "ebay bad capture is bad_shape" {
  run jq --argjson now "$NOW" -L "$ROOT/scripts/lib" -f "$ROOT/scripts/lib/normalize.ebay.jq" \
    <<< '{"provider":"cursor","mtd_usd":10,"cap_usd":0}'
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.status')" = bad_shape ]
}