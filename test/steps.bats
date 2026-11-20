#!/usr/bin/env bats
# Width-aware steps: render.sh output for every step, as exact strings.
# shellcheck disable=SC2030,SC2031,SC2016
load test_helper

setup() { setup_env; }

NOW=1795074751

@test "auto prints every step inside one client_width conditional" {
  seed_snapshot primary-only $NOW
  AI_USAGE_NOW=$NOW run render codex
  [ "$status" -eq 0 ]
  [ "$output" = "$(nested \
    '#[fg=#bac2de]cx #[fg=#6c7086]wk #[fg=#f9e2af]▰▰▰▱▱ #[fg=#6c7086]2d1h' \
    '#[fg=#bac2de]cx #[fg=#f9e2af]▰▰▰▱▱ #[fg=#6c7086]2d1h' \
    '#[fg=#bac2de]cx #[fg=#f9e2af]▰▰▰▱▱' \
    '#[fg=#bac2de]cx #[fg=#f9e2af]66%' \
    '#[fg=#f9e2af]cx')" ]
}

seed_all_providers() {
  seed_snapshot_claude five-hour-weekly "$NOW"
  seed_snapshot primary-secondary "$NOW"
  seed_snapshot_cursor unified-weekly "$NOW"
}

@test "#{ai_usage} at full joins pieces with the separator, with no percentage" {
  seed_all_providers
  opt @ai_usage_step full
  AI_USAGE_NOW=$NOW run render all
  [ "$output" = '#[fg=#bac2de]cl #[fg=#6c7086]wk #[fg=#f9e2af]▰▰▰▱▱ #[fg=#6c7086]7d2h#[fg=#6c7086] │ #[fg=#bac2de]cx #[fg=#6c7086]5h #[fg=#f9e2af]▰▰▰▰▱ #[fg=#6c7086]47m#[fg=#6c7086] │ #[fg=#bac2de]cu #[fg=#6c7086]wk #[fg=#a6e3a1]▰▰▰▱▱ #[fg=#6c7086]2d1h#[fg=default]' ]
}

@test "step 1 drops the window label and keeps the separator" {
  seed_all_providers
  opt @ai_usage_step 1
  AI_USAGE_NOW=$NOW run render all
  [ "$output" = '#[fg=#bac2de]cl #[fg=#f9e2af]▰▰▰▱▱ #[fg=#6c7086]7d2h#[fg=#6c7086] │ #[fg=#bac2de]cx #[fg=#f9e2af]▰▰▰▰▱ #[fg=#6c7086]47m#[fg=#6c7086] │ #[fg=#bac2de]cu #[fg=#a6e3a1]▰▰▰▱▱ #[fg=#6c7086]2d1h#[fg=default]' ]
}

@test "step 2 joins with one space and drops the countdown unless crit" {
  seed_all_providers
  seed_window 5h 90 $((NOW + 2820))
  opt @ai_usage_step 2
  AI_USAGE_NOW=$NOW run render all
  [ "$output" = '#[fg=#bac2de]cl #[fg=#f9e2af]▰▰▰▱▱ #[fg=#bac2de]cx #[fg=#f38ba8]▰▰▰▰▰ #[fg=#6c7086]47m #[fg=#bac2de]cu #[fg=#a6e3a1]▰▰▰▱▱#[fg=default]' ]
}

@test "step 3 shows the percentage in place of the progress bar" {
  seed_all_providers
  seed_window 5h 90 $((NOW + 2820))
  opt @ai_usage_step 3
  AI_USAGE_NOW=$NOW run render all
  [ "$output" = '#[fg=#bac2de]cl #[fg=#f9e2af]67% #[fg=#bac2de]cx #[fg=#f38ba8]90% #[fg=#6c7086]47m #[fg=#bac2de]cu #[fg=#a6e3a1]58%#[fg=default]' ]
}

@test "step 4 shows each provider label in its usage colour" {
  seed_all_providers
  opt @ai_usage_step 4
  AI_USAGE_NOW=$NOW run render all
  [ "$output" = '#[fg=#f9e2af]cl #[fg=#f9e2af]cx #[fg=#a6e3a1]cu#[fg=default]' ]
}

@test "a custom separator is used at full and step 1 only" {
  seed_all_providers
  opt @ai_usage_providers 'codex cursor'
  opt @ai_usage_separator '::'
  AI_USAGE_NOW=$NOW run render all
  [ "$output" = "$(nested \
    '#[fg=#bac2de]cx #[fg=#6c7086]5h #[fg=#f9e2af]▰▰▰▰▱ #[fg=#6c7086]47m#[fg=#6c7086]::#[fg=#bac2de]cu #[fg=#6c7086]wk #[fg=#a6e3a1]▰▰▰▱▱ #[fg=#6c7086]2d1h' \
    '#[fg=#bac2de]cx #[fg=#f9e2af]▰▰▰▰▱ #[fg=#6c7086]47m#[fg=#6c7086]::#[fg=#bac2de]cu #[fg=#a6e3a1]▰▰▰▱▱ #[fg=#6c7086]2d1h' \
    '#[fg=#bac2de]cx #[fg=#f9e2af]▰▰▰▰▱ #[fg=#bac2de]cu #[fg=#a6e3a1]▰▰▰▱▱' \
    '#[fg=#bac2de]cx #[fg=#f9e2af]81% #[fg=#bac2de]cu #[fg=#a6e3a1]58%' \
    '#[fg=#f9e2af]cx #[fg=#a6e3a1]cu')" ]
}

@test "bar width 0 puts the percentage where the progress bar would be at every step" {
  seed_window 5h 67 $((NOW + 274000))
  opt @ai_usage_bar_width 0
  AI_USAGE_NOW=$NOW run render codex
  [ "$output" = "$(nested \
    '#[fg=#bac2de]cx #[fg=#6c7086]5h #[fg=#f9e2af]67% #[fg=#6c7086]3d4h' \
    '#[fg=#bac2de]cx #[fg=#f9e2af]67% #[fg=#6c7086]3d4h' \
    '#[fg=#bac2de]cx #[fg=#f9e2af]67%' \
    '#[fg=#bac2de]cx #[fg=#f9e2af]67%' \
    '#[fg=#f9e2af]cx')" ]
}

@test "@ai_usage_step_widths sets the conditional's thresholds" {
  seed_window 5h 10 $((NOW + 3600))
  opt @ai_usage_step_widths '"200 150 100 50"'
  AI_USAGE_NOW=$NOW run render codex
  [ "$output" = "$(nested \
    '#[fg=#bac2de]cx #[fg=#6c7086]5h #[fg=#a6e3a1]▰▱▱▱▱ #[fg=#6c7086]1h' \
    '#[fg=#bac2de]cx #[fg=#a6e3a1]▰▱▱▱▱ #[fg=#6c7086]1h' \
    '#[fg=#bac2de]cx #[fg=#a6e3a1]▰▱▱▱▱' \
    '#[fg=#bac2de]cx #[fg=#a6e3a1]10%' \
    '#[fg=#a6e3a1]cx' 200 150 100 50)" ]
}

@test "invalid step options silently fall back to auto and the default widths" {
  seed_window 5h 10 $((NOW + 3600))
  opt @ai_usage_step_widths '"80 110 140 180"'
  opt @ai_usage_step 5
  AI_USAGE_NOW=$NOW run render codex
  [ "$output" = "$(nested \
    '#[fg=#bac2de]cx #[fg=#6c7086]5h #[fg=#a6e3a1]▰▱▱▱▱ #[fg=#6c7086]1h' \
    '#[fg=#bac2de]cx #[fg=#a6e3a1]▰▱▱▱▱ #[fg=#6c7086]1h' \
    '#[fg=#bac2de]cx #[fg=#a6e3a1]▰▱▱▱▱' \
    '#[fg=#bac2de]cx #[fg=#a6e3a1]10%' \
    '#[fg=#a6e3a1]cx')" ]
}

@test "before tmux 3.2 auto renders the full step" {
  seed_window 5h 10 $((NOW + 3600))
  opt @ai_usage_tmux_version 3.1c
  AI_USAGE_NOW=$NOW run render codex
  [ "$output" = '#[fg=#bac2de]cx #[fg=#6c7086]5h #[fg=#a6e3a1]▰▱▱▱▱ #[fg=#6c7086]1h#[fg=default]' ]
}

@test "before tmux 3.2 #{ai_usage} renders the full step" {
  seed_all_providers
  opt @ai_usage_providers 'codex cursor'
  opt @ai_usage_tmux_version 3.1c
  AI_USAGE_NOW=$NOW run render all
  [ "$output" = '#[fg=#bac2de]cx #[fg=#6c7086]5h #[fg=#f9e2af]▰▰▰▰▱ #[fg=#6c7086]47m#[fg=#6c7086] │ #[fg=#bac2de]cu #[fg=#6c7086]wk #[fg=#a6e3a1]▰▰▰▱▱ #[fg=#6c7086]2d1h#[fg=default]' ]
}

@test "before tmux 3.2 a forced step still applies" {
  seed_window 5h 10 $((NOW + 3600))
  opt @ai_usage_tmux_version 3.1c
  opt @ai_usage_step 3
  AI_USAGE_NOW=$NOW run render codex
  [ "$output" = '#[fg=#bac2de]cx #[fg=#a6e3a1]10%#[fg=default]' ]
}

@test "commas and closing braces in step text are escaped inside the conditional" {
  seed_window 5h 10 $((NOW + 3600))
  opt @ai_usage_codex_label 'c,x}'
  AI_USAGE_NOW=$NOW run render codex
  [ "$output" = "$(nested \
    '#[fg=#bac2de]c#,x#} #[fg=#6c7086]5h #[fg=#a6e3a1]▰▱▱▱▱ #[fg=#6c7086]1h' \
    '#[fg=#bac2de]c#,x#} #[fg=#a6e3a1]▰▱▱▱▱ #[fg=#6c7086]1h' \
    '#[fg=#bac2de]c#,x#} #[fg=#a6e3a1]▰▱▱▱▱' \
    '#[fg=#bac2de]c#,x#} #[fg=#a6e3a1]10%' \
    '#[fg=#a6e3a1]c#,x#}')" ]
}
