#!/usr/bin/env bats
# Stale, problem and pending states at every step, as exact strings.
# shellcheck disable=SC2030,SC2031,SC2016
load test_helper

setup() { setup_env; }

NOW=1795074751

# The nested client_width conditional render.sh prints for `auto`.
nested() { # full s1 s2 s3 s4
  printf '#{?#{e|>=:#{client_width},180},%s,#{?#{e|>=:#{client_width},140},%s,#{?#{e|>=:#{client_width},110},%s,#{?#{e|>=:#{client_width},80},%s,%s}}}}#[fg=default]' \
    "$1" "$2" "$3" "$4" "$5"
}

opt() { echo "$1 $2" >> "$TMUX_SHIM_OPTIONS"; }

@test "a stale reading puts ~ before the usage at each step and dims step 4 without it" {
  seed_window 5h 81 $((NOW + 2820)) $((NOW - 901))
  AI_USAGE_NOW=$NOW run render codex
  [ "$output" = "$(nested \
    '#[fg=#6c7086]cx #[fg=#6c7086]5h #[fg=#6c7086]~▰▰▰▰▱ #[fg=#6c7086]47m' \
    '#[fg=#6c7086]cx #[fg=#6c7086]~▰▰▰▰▱ #[fg=#6c7086]47m' \
    '#[fg=#6c7086]cx #[fg=#6c7086]~▰▰▰▰▱' \
    '#[fg=#6c7086]cx #[fg=#6c7086]~81%' \
    '#[fg=#6c7086]cx')" ]
}

@test "problem states keep their words through step 3 and become label! at step 4" {
  for case in "signed_out !login" "missing_dep !deps" "bad_shape !format" "error !error"; do
    read -r st word <<<"$case"
    seed_status "$st"
    AI_USAGE_NOW=$NOW run render codex
    local p="#[fg=#f38ba8]cx $word"
    [ "$output" = "$(nested "$p" "$p" "$p" "$p" '#[fg=#f38ba8]cx!')" ] || { echo "$st: $output"; return 1; }
  done
}

@test "pending is a dim ellipsis through step 3 and a dim label at step 4" {
  rm -f "$CACHE/codex.json"
  AI_USAGE_NOW=$NOW AI_USAGE_NO_REFRESH=1 run render codex
  local p='#[fg=#6c7086]cx …'
  [ "$output" = "$(nested "$p" "$p" "$p" "$p" '#[fg=#6c7086]cx')" ]
}

@test "a passed reset shows 0% and no countdown at every step" {
  seed_window 5h 81 $((NOW - 120))
  AI_USAGE_NOW=$NOW run render codex
  [ "$output" = "$(nested \
    '#[fg=#bac2de]cx #[fg=#6c7086]5h #[fg=#a6e3a1]▱▱▱▱▱' \
    '#[fg=#bac2de]cx #[fg=#a6e3a1]▱▱▱▱▱' \
    '#[fg=#bac2de]cx #[fg=#a6e3a1]▱▱▱▱▱' \
    '#[fg=#bac2de]cx #[fg=#a6e3a1]0%' \
    '#[fg=#a6e3a1]cx')" ]
}

@test "a transient error that isn't stale shows the last good value unmarked at every step" {
  seed_snapshot primary-only $NOW
  patch_snapshot '.status = "error"'
  AI_USAGE_NOW=$NOW run render codex
  [ "$output" = "$(nested \
    '#[fg=#bac2de]cx #[fg=#6c7086]wk #[fg=#f9e2af]▰▰▰▱▱ #[fg=#6c7086]2d1h' \
    '#[fg=#bac2de]cx #[fg=#f9e2af]▰▰▰▱▱ #[fg=#6c7086]2d1h' \
    '#[fg=#bac2de]cx #[fg=#f9e2af]▰▰▰▱▱' \
    '#[fg=#bac2de]cx #[fg=#f9e2af]66%' \
    '#[fg=#f9e2af]cx')" ]
}

@test "an error whose last good value is stale renders as stale at every step" {
  seed_snapshot primary-only $NOW
  patch_snapshot --argjson ok $((NOW - 901)) '.status = "error" | .ok_at = $ok'
  AI_USAGE_NOW=$NOW run render codex
  [ "$output" = "$(nested \
    '#[fg=#6c7086]cx #[fg=#6c7086]wk #[fg=#6c7086]~▰▰▰▱▱ #[fg=#6c7086]2d1h' \
    '#[fg=#6c7086]cx #[fg=#6c7086]~▰▰▰▱▱ #[fg=#6c7086]2d1h' \
    '#[fg=#6c7086]cx #[fg=#6c7086]~▰▰▰▱▱' \
    '#[fg=#6c7086]cx #[fg=#6c7086]~66%' \
    '#[fg=#6c7086]cx')" ]
}

@test "with bar width 0 a stale reading puts ~ before the percentage at every step" {
  seed_snapshot primary-only $NOW
  patch_snapshot --argjson ok $((NOW - 901)) '.ok_at = $ok'
  opt @ai_usage_bar_width 0
  AI_USAGE_NOW=$NOW run render codex
  [ "$output" = "$(nested \
    '#[fg=#6c7086]cx #[fg=#6c7086]wk #[fg=#6c7086]~66% #[fg=#6c7086]2d1h' \
    '#[fg=#6c7086]cx #[fg=#6c7086]~66% #[fg=#6c7086]2d1h' \
    '#[fg=#6c7086]cx #[fg=#6c7086]~66%' \
    '#[fg=#6c7086]cx #[fg=#6c7086]~66%' \
    '#[fg=#6c7086]cx')" ]
}

@test "signed_out hides an earlier good value behind !login at every step" {
  seed_status signed_out "$NOW"
  AI_USAGE_NOW=$NOW run render codex
  local p='#[fg=#f38ba8]cx !login'
  [ "$output" = "$(nested "$p" "$p" "$p" "$p" '#[fg=#f38ba8]cx!')" ]
}

seed_mixed_states() { # claude pending, codex signed_out, cursor ok
  rm -f "$CACHE/claude.json"
  seed_status signed_out
  seed_snapshot_cursor unified-weekly "$NOW"
}

@test "in #{ai_usage} a provider in a problem state keeps its place and separator at step 1" {
  seed_mixed_states
  opt @ai_usage_step 1
  AI_USAGE_NOW=$NOW AI_USAGE_NO_REFRESH=1 run render all
  [ "$output" = '#[fg=#6c7086]cl …#[fg=#6c7086] │ #[fg=#f38ba8]cx !login#[fg=#6c7086] │ #[fg=#bac2de]cu #[fg=#a6e3a1]▰▰▰▱▱ #[fg=#6c7086]2d1h#[fg=default]' ]
}

@test "in #{ai_usage} at step 4 pending is a dim label and a problem is label!" {
  seed_mixed_states
  opt @ai_usage_step 4
  AI_USAGE_NOW=$NOW AI_USAGE_NO_REFRESH=1 run render all
  [ "$output" = '#[fg=#6c7086]cl #[fg=#f38ba8]cx! #[fg=#a6e3a1]cu#[fg=default]' ]
}
