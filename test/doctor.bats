#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031
load test_helper

doctor() { "$ROOT/scripts/doctor.sh"; }

setup() {
  setup_env
  setup_codex primary-only
  NOW=1795074751
}

@test "doctor reads snapshots only and never fetches" {
  seed_snapshot primary-only "$NOW"
  AI_USAGE_NOW=$NOW run doctor
  [ "$status" -eq 0 ]
  [ "$(curl_calls)" = 0 ]
  echo "$output" | grep -q 'provider=codex'
  echo "$output" | grep -q 'status=ok'
  echo "$output" | grep -q 'ok_age=0m'
  echo "$output" | grep -q 'deps curl='
  echo "$output" | grep -q 'options providers='
}

@test "doctor shows pending when no snapshot exists" {
  rm -f "$CACHE/codex.json"
  AI_USAGE_NOW=$NOW run doctor
  echo "$output" | grep -q 'provider=codex'
  echo "$output" | grep -q 'status=pending'
}

@test "doctor reports error text and retry_at from snapshot" {
  jq -n --argjson now "$NOW" \
    '{provider:"codex",status:"error",fetched_at:$now,ok_at:$now,retry_at:($now+300),
      error:"HTTP 429",windows:[{label:"wk",used_pct:40,resets_at:($now+1000),window_seconds:604800}]}' \
    > "$CACHE/codex.json"
  AI_USAGE_NOW=$NOW run doctor
  echo "$output" | grep -q 'status=error'
  echo "$output" | grep -q 'error=HTTP 429'
  echo "$output" | grep -q "retry_at=$((NOW + 300))"
}
@test "doctor prints the separator as readable text, even under the C locale" {
  LC_ALL=C LANG=C AI_USAGE_NOW=$NOW run doctor
  echo "$output" | grep -qxF "options separator=' │ '"
}
