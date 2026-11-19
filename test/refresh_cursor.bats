#!/usr/bin/env bats
# shellcheck disable=SC2016,SC2030,SC2031
load test_helper

setup() {
  setup_env
  setup_cursor unified
  unset CURL_SHIM_HTTP CURL_SHIM_EXIT CURSOR_SHIM_KEYCHAIN_EXIT
}

NOW=1795074751
# Plain JWT: exp 2029, sub auth0|testuser
export CURSOR_TEST_JWT='eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJhdXRoMHx0ZXN0dXNlciIsImV4cCI6MTg5MzQ1NjAwMH0.sig'

@test "refresh writes a live unified Cursor snapshot" {
  seed_snapshot_cursor unified-weekly $((NOW - 120))
  AI_USAGE_NOW=$NOW run refresh cursor
  [ "$(jq -r .status "$CACHE/cursor.json")" = "ok" ]
  [ "$(jq -c '[.windows[].label]' "$CACHE/cursor.json")" = '["wk"]' ]
  [ "$(curl_calls)" = 1 ]
}

@test "legacy refresh calls usage-summary after sand" {
  seed_snapshot_cursor legacy-two-pools $((NOW - 120))
  export CURL_SHIM_SAND_RESPONSE="$FIXTURES/cursor/sand-legacy-flag.json"
  export CURL_SHIM_SUMMARY_RESPONSE="$FIXTURES/cursor/summary-legacy.json"
  AI_USAGE_NOW=$NOW run refresh cursor
  [ "$(jq -r .status "$CACHE/cursor.json")" = "ok" ]
  [ "$(jq -c '[.windows[].label]' "$CACHE/cursor.json")" = '["mo-auto","mo-api"]' ]
  [ "$(curl_calls)" = 2 ]
}

@test "missing curl is missing_dep" {
  rm -f "$CACHE/cursor.json"
  export AI_USAGE_TEST_NO_CURL=1
  AI_USAGE_NOW=$NOW run refresh cursor
  unset AI_USAGE_TEST_NO_CURL
  [ "$(jq -r .status "$CACHE/cursor.json")" = "missing_dep" ]
}

@test "missing sqlite3 is missing_dep" {
  rm -f "$CACHE/cursor.json"
  export AI_USAGE_TEST_NO_SQLITE3=1
  AI_USAGE_NOW=$NOW run refresh cursor
  unset AI_USAGE_TEST_NO_SQLITE3
  [ "$(jq -r .status "$CACHE/cursor.json")" = "missing_dep" ]
}

@test "missing openssl is missing_dep" {
  rm -f "$CACHE/cursor.json"
  export AI_USAGE_TEST_NO_OPENSSL=1
  AI_USAGE_NOW=$NOW run refresh cursor
  unset AI_USAGE_TEST_NO_OPENSSL
  [ "$(jq -r .status "$CACHE/cursor.json")" = "missing_dep" ]
}

@test "no token in state DB is signed_out" {
  rm -f "$CACHE/cursor.json"
  unset CURSOR_SHIM_TOKEN
  AI_USAGE_NOW=$((NOW + 120)) run refresh cursor
  [ "$(jq -r .status "$CACHE/cursor.json")" = "signed_out" ]
  [ "$(curl_calls)" = 0 ]
}

@test "expired JWT is signed_out without a request" {
  export CURSOR_SHIM_TOKEN='eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJhdXRoMHx0ZXN0dXNlciIsImV4cCI6MTAwMDAwMDAwMH0.sig'
  AI_USAGE_NOW=$NOW run refresh cursor
  [ "$(jq -r .status "$CACHE/cursor.json")" = "signed_out" ]
  [ "$(curl_calls)" = 0 ]
}

@test "HTTP 401 from get-sand-usage-status is signed_out" {
  export CURL_SHIM_HTTP=401
  export CURL_SHIM_SAND_RESPONSE=/dev/null
  AI_USAGE_NOW=$NOW run refresh cursor
  [ "$(jq -r .status "$CACHE/cursor.json")" = "signed_out" ]
}

@test "refused Keychain access is missing_dep" {
  rm -f "$CACHE/cursor.json"
  export CURSOR_SHIM_TOKEN='cursor-safe-storage:v1:bm9uZQ=='
  unset CURSOR_TEST_JWT
  export CURSOR_SHIM_KEYCHAIN_EXIT=1
  printf 'User canceled the operation.\n' >"$BATS_TEST_TMPDIR/sec-err.txt"
  export CURSOR_SHIM_KEYCHAIN_STDERR="$BATS_TEST_TMPDIR/sec-err.txt"
  AI_USAGE_NOW=$((NOW + 120)) run refresh cursor
  unset CURSOR_SHIM_KEYCHAIN_EXIT CURSOR_SHIM_KEYCHAIN_STDERR
  export CURSOR_TEST_JWT='eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJhdXRoMHx0ZXN0dXNlciIsImV4cCI6MTg5MzQ1NjAwMH0.sig'
  [ "$(jq -r .status "$CACHE/cursor.json")" = "missing_dep" ]
}