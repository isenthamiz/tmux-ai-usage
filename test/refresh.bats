load test_helper

setup() { setup_env; setup_codex primary-secondary; }

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
