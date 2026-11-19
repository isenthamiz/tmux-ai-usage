#!/usr/bin/env bats
# wait_for conditions are single-quoted on purpose: they are evaluated when polled.
# Each @test runs in its own subshell, so per-test exports are meant to be local.
# shellcheck disable=SC2016,SC2030,SC2031,SC2123
load test_helper

setup() {
  setup_env
  setup_codex primary-secondary
  unset CURL_SHIM_EXIT CURL_SHIM_HTTP CURL_SHIM_RETRY_AFTER
}

NOW=1795074751

@test "a stale snapshot is served at once and refreshed exactly once" {
  seed_snapshot primary-only $((NOW - 120))
  AI_USAGE_NOW=$NOW run render codex
  [ "$output" = '#[fg=#bac2de]cx #[fg=#6c7086]wk #[fg=#f9e2af]▰▰▰▱▱ 66% #[fg=#6c7086]2d1h#[fg=default]' ]
  wait_for '[ "$(jq .fetched_at "$CACHE/codex.json")" = "$NOW" ]'
  wait_for refresh_idle
  [ "$(curl_calls)" = 1 ]
  [ "$(jq -c '[.windows[].label]' "$CACHE/codex.json")" = '["5h","wk"]' ]
  [ "$(stat -f %Lp "$CACHE")" = 700 ]
}

@test "a fresh snapshot starts no refresh" {
  seed_snapshot primary-only $((NOW - 59))
  AI_USAGE_NOW=$NOW run render codex
  sleep 1
  [ "$(curl_calls)" = 0 ]
}

@test "concurrent renders of a stale snapshot start one refresh" {
  seed_snapshot primary-only $((NOW - 120))
  export CURL_SHIM_DELAY=1
  for _ in 1 2 3 4 5 6 7 8; do AI_USAGE_NOW=$NOW render codex >/dev/null & done
  wait
  wait_for '[ "$(jq .fetched_at "$CACHE/codex.json")" = "$NOW" ]'
  wait_for refresh_idle
  [ "$(curl_calls)" = 1 ]
}

@test "a lock held by a live refresh is respected" {
  seed_snapshot primary-only $((NOW - 120))
  mkdir "$CACHE/codex.lock" && echo $$ > "$CACHE/codex.lock/pid"
  AI_USAGE_NOW=$NOW run render codex
  sleep 1
  [ "$(curl_calls)" = 0 ]
}

@test "a lock whose owner is dead is broken" {
  seed_snapshot primary-only $((NOW - 120))
  sh -c 'exit 0' & dead=$!; wait $dead
  mkdir "$CACHE/codex.lock" && echo "$dead" > "$CACHE/codex.lock/pid"
  AI_USAGE_NOW=$NOW run render codex
  wait_for '[ "$(jq .fetched_at "$CACHE/codex.json")" = "$NOW" ]'
  [ "$(curl_calls)" = 1 ]
}

@test "a lock older than 120 seconds is broken even if its owner lives" {
  seed_snapshot primary-only $((NOW - 120))
  mkdir "$CACHE/codex.lock" && echo $$ > "$CACHE/codex.lock/pid"
  touch -t "$(date -v-3M +%Y%m%d%H%M.%S)" "$CACHE/codex.lock"
  AI_USAGE_NOW=$NOW run render codex
  wait_for '[ "$(jq .fetched_at "$CACHE/codex.json")" = "$NOW" ]'
  [ "$(curl_calls)" = 1 ]
}

@test "concurrent renders breaking a dead owner's lock still start one refresh" {
  seed_snapshot primary-only $((NOW - 120))
  sh -c 'exit 0' & dead=$!; wait $dead
  mkdir "$CACHE/codex.lock" && echo "$dead" > "$CACHE/codex.lock/pid"
  export CURL_SHIM_DELAY=1
  for _ in 1 2 3 4 5 6 7 8; do AI_USAGE_NOW=$NOW render codex >/dev/null & done
  wait
  wait_for '[ "$(jq .fetched_at "$CACHE/codex.json")" = "$NOW" ]'
  wait_for refresh_idle
  sleep 1.5
  [ "$(curl_calls)" = 1 ] || { echo "curl called $(curl_calls) times"; return 1; }
}

@test "a malformed response keeps the last good windows and records bad_shape" {
  seed_snapshot primary-only $((NOW - 120))
  export CURL_SHIM_RESPONSE="$FIXTURES/codex/malformed.json"
  AI_USAGE_NOW=$NOW run render codex
  wait_for '[ "$(jq .fetched_at "$CACHE/codex.json")" = "$NOW" ]'
  [ "$(jq -c '{status, ok_at, labels: [.windows[].label]}' "$CACHE/codex.json")" = "{\"status\":\"bad_shape\",\"ok_at\":$((NOW - 120)),\"labels\":[\"wk\"]}" ]
}

@test "a failed fetch keeps the last good windows and is not retried for a refresh interval" {
  seed_snapshot primary-only $((NOW - 120))
  export CURL_SHIM_EXIT=22
  unset CURL_SHIM_HTTP
  AI_USAGE_NOW=$NOW run render codex
  wait_for '[ "$(jq .fetched_at "$CACHE/codex.json")" = "$NOW" ]'
  [ "$(jq -c '{status, ok_at, retry_at, labels: [.windows[].label]}' "$CACHE/codex.json")" = "{\"status\":\"error\",\"ok_at\":$((NOW - 120)),\"retry_at\":$((NOW + 60)),\"labels\":[\"wk\"]}" ]
}

@test "missing Codex sign-in is signed_out" {
  seed_snapshot primary-only $((NOW - 120))
  rm -f "$CODEX_HOME/auth.json"
  AI_USAGE_NOW=$NOW run render codex
  wait_for '[ "$(jq -r .status "$CACHE/codex.json")" = "signed_out" ]'
  [ "$(jq -c '{status, labels: [.windows[].label]}' "$CACHE/codex.json")" = "{\"status\":\"signed_out\",\"labels\":[\"wk\"]}" ]
}

@test "HTTP 401 from wham/usage is signed_out" {
  seed_snapshot primary-only $((NOW - 120))
  unset CURL_SHIM_EXIT
  export CURL_SHIM_HTTP=401
  export CURL_SHIM_RESPONSE=/dev/null
  AI_USAGE_NOW=$NOW run render codex
  wait_for '[ "$(jq -r .status "$CACHE/codex.json")" = "signed_out" ]'
}

@test "429 honours Retry-After in retry_at" {
  seed_snapshot primary-only $((NOW - 120))
  unset CURL_SHIM_EXIT
  export CURL_SHIM_HTTP=429
  export CURL_SHIM_RETRY_AFTER=120
  export CURL_SHIM_RESPONSE=/dev/null
  AI_USAGE_NOW=$NOW run render codex
  wait_for '[ "$(jq -r .retry_at "$CACHE/codex.json")" = "$((NOW + 120))" ]'
}

@test "a second consecutive error doubles the back-off" {
  seed_snapshot primary-only $((NOW - 120))
  export CURL_SHIM_EXIT=22
  unset CURL_SHIM_HTTP
  AI_USAGE_NOW=$NOW run refresh codex
  [ "$(jq .retry_at "$CACHE/codex.json")" = "$((NOW + 60))" ]
  patch_snapshot --argjson fa "$NOW" --argjson ra $((NOW + 60)) \
    '.status = "error" | .fetched_at = $fa | .retry_at = $ra'
  unset CURL_SHIM_EXIT
  export CURL_SHIM_HTTP=500
  export CURL_SHIM_RESPONSE=/dev/null
  AI_USAGE_NOW=$((NOW + 60)) run refresh codex
  [ "$(jq .retry_at "$CACHE/codex.json")" = "$((NOW + 180))" ]
}

@test "no refresh runs before retry_at" {
  seed_snapshot primary-only $((NOW - 120))
  export CURL_SHIM_EXIT=22
  AI_USAGE_NOW=$NOW run render codex
  wait_for '[ "$(jq .fetched_at "$CACHE/codex.json")" = "$NOW" ]'
  unset CURL_SHIM_EXIT CURL_SHIM_HTTP
  export CURL_SHIM_RESPONSE="$FIXTURES/codex/primary-only.json"
  AI_USAGE_NOW=$((NOW + 30)) run render codex
  sleep 0.5
  [ "$(curl_calls)" = 1 ]
}

@test "missing curl produces missing_dep" {
  seed_snapshot primary-only $((NOW - 120))
  export AI_USAGE_TEST_NO_CURL=1
  AI_USAGE_NOW=$NOW run refresh codex
  unset AI_USAGE_TEST_NO_CURL
  [ "$(jq -r .status "$CACHE/codex.json")" = "missing_dep" ]
}

@test "refresh with a missing or unknown provider writes nothing and fails" {
  run "$ROOT/scripts/refresh.sh"
  [ "$status" -eq 2 ]
  run "$ROOT/scripts/refresh.sh" nope
  [ "$status" -eq 2 ]
  [ -z "$(ls -A "$CACHE")" ]
}
