#!/usr/bin/env bats
# Rotation of #{ai_usage}: one provider at a time, chosen from the clock.
# shellcheck disable=SC2030,SC2031,SC2016
load test_helper

setup() {
  setup_env
  opt status-interval 5
  seed_snapshot_claude five-hour-weekly "$NOW"
  seed_snapshot primary-secondary "$NOW"
  seed_snapshot_cursor unified-weekly "$NOW"
}

# floor(NOW / 10) is a multiple of 3, so slot 0 is the first provider.
NOW=1795074750

CL='#[fg=#f9e2af]cl#[fg=default]'
CX='#[fg=#f9e2af]cx#[fg=default]'
CU='#[fg=#a6e3a1]cu#[fg=default]'

at() { AI_USAGE_NOW=$1 AI_USAGE_NO_REFRESH=1 render all; }

@test "rotation shows each enabled provider in order, one interval each" {
  opt @ai_usage_rotate on
  opt @ai_usage_step 4
  [ "$(at $NOW)" = "$CL" ]
  [ "$(at $((NOW + 9)))" = "$CL" ]
  [ "$(at $((NOW + 10)))" = "$CX" ]
  [ "$(at $((NOW + 20)))" = "$CU" ]
  [ "$(at $((NOW + 30)))" = "$CL" ]
}

@test "the interval is rounded up to whole status-interval ticks" {
  opt status-interval 15
  opt @ai_usage_rotate on
  opt @ai_usage_step 4
  [ "$(at $((NOW + 14)))" = "$CL" ]
  [ "$(at $((NOW + 15)))" = "$CX" ]
  [ "$(at $((NOW + 30)))" = "$CU" ]
}

@test "every provider gets its turn whatever its state" {
  rm -f "$CACHE/claude.json"
  NOW=$NOW seed_status signed_out
  opt @ai_usage_rotate on
  opt @ai_usage_step 4
  [ "$(at $NOW)" = '#[fg=#6c7086]cl#[fg=default]' ]
  [ "$(at $((NOW + 10)))" = '#[fg=#f38ba8]cx!#[fg=default]' ]
  [ "$(at $((NOW + 20)))" = "$CU" ]
}

@test "rotation follows the order of @ai_usage_providers" {
  opt @ai_usage_providers '"cursor codex"'
  opt @ai_usage_rotate on
  opt @ai_usage_step 4
  # floor(NOW / 10) is odd: slot 1 of two, then back to slot 0.
  [ "$(at $NOW)" = "$CX" ]
  [ "$(at $((NOW + 10)))" = "$CU" ]
  [ "$(at $((NOW + 20)))" = "$CX" ]
}

@test "one enabled provider means no rotation" {
  opt @ai_usage_providers codex
  opt @ai_usage_rotate on
  opt @ai_usage_step 4
  [ "$(at $NOW)" = "$CX" ]
  [ "$(at $((NOW + 10)))" = "$CX" ]
  [ "$(at $((NOW + 20)))" = "$CX" ]
}

@test "a per-provider token ignores rotation" {
  opt @ai_usage_rotate on
  opt @ai_usage_step 4
  [ "$(AI_USAGE_NOW=$((NOW + 10)) AI_USAGE_NO_REFRESH=1 render claude)" = "$CL" ]
  [ "$(AI_USAGE_NOW=$((NOW + 20)) AI_USAGE_NO_REFRESH=1 render claude)" = "$CL" ]
}

@test "with rotation off #{ai_usage} shows every provider" {
  opt @ai_usage_step 4
  [ "$(at $NOW)" = '#[fg=#f9e2af]cl #[fg=#f9e2af]cx #[fg=#a6e3a1]cu#[fg=default]' ]
}

@test "steps apply to the rotating provider" {
  opt @ai_usage_rotate on
  [ "$(at $NOW)" = "$(nested \
    '#[fg=#bac2de]cl #[fg=#6c7086]wk #[fg=#f9e2af]▰▰▰▱▱ #[fg=#6c7086]7d2h' \
    '#[fg=#bac2de]cl #[fg=#f9e2af]▰▰▰▱▱ #[fg=#6c7086]7d2h' \
    '#[fg=#bac2de]cl #[fg=#f9e2af]▰▰▰▱▱' \
    '#[fg=#bac2de]cl #[fg=#f9e2af]67%' \
    '#[fg=#f9e2af]cl')" ]
}

@test "invalid rotation options silently fall back to off and 10 s" {
  opt @ai_usage_rotate maybe
  opt @ai_usage_rotate_interval 0
  opt @ai_usage_step 4
  [ "$(at $NOW)" = '#[fg=#f9e2af]cl #[fg=#f9e2af]cx #[fg=#a6e3a1]cu#[fg=default]' ]
}

@test "a provider waiting for its turn is still refreshed when due" {
  setup_codex primary-secondary
  seed_snapshot primary-only $((NOW - 120))
  opt @ai_usage_rotate on
  opt @ai_usage_step 4
  [ "$(AI_USAGE_NOW=$NOW render all)" = "$CL" ]
  wait_for '[ "$(jq .fetched_at "$CACHE/codex.json")" = "$NOW" ]'
  wait_for refresh_idle
  [ "$(curl_calls)" = 1 ]
}

@test "a provider named twice in @ai_usage_providers gets one turn" {
  opt @ai_usage_providers '"claude claude codex"'
  opt @ai_usage_rotate on
  opt @ai_usage_step 4
  # Two distinct providers; floor(NOW / 10) is odd, so slot 1 comes first.
  [ "$(at $NOW)" = "$CX" ]
  [ "$(at $((NOW + 10)))" = "$CL" ]
  [ "$(at $((NOW + 20)))" = "$CX" ]
}
