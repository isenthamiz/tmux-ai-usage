#!/usr/bin/env bats
# Each @test runs in its own subshell; bats' run sets $output there on purpose.
# shellcheck disable=SC2030,SC2031,SC2016
load test_helper

setup() { setup_env; force_step full; }

NOW=1795074751

@test "codex piece shows its most-used window in the theme's colours" {
  cat >> "$TMUX_SHIM_OPTIONS" <<'OPTS'
@thm_green "#00aa00"
@thm_yellow "#aaaa00"
@thm_red "#aa0000"
@thm_subtext_0 "#cccccc"
@thm_overlay_0 "#666666"
status-interval 5
OPTS
  seed_snapshot primary-secondary $NOW
  AI_USAGE_NOW=$NOW run render codex
  [ "$status" -eq 0 ]
  [ "$output" = '#[fg=#cccccc]cx #[fg=#666666]5h #[fg=#aaaa00]▰▰▰▰▱ #[fg=#666666]47m#[fg=default]' ]
}

@test "without theme options the Catppuccin Mocha colours are used" {
  seed_snapshot primary-only $NOW
  AI_USAGE_NOW=$NOW run render codex
  [ "$output" = '#[fg=#bac2de]cx #[fg=#6c7086]wk #[fg=#f9e2af]▰▰▰▱▱ #[fg=#6c7086]2d1h#[fg=default]' ]
}

# Bar and colour only: everything between the window label and the countdown.
bar_part() { sed -E 's/^.*5h #\[fg=([^]]*)\]([^ ]*) .*$/\1 \2/' <<<"$output"; }

@test "below 60% the bar is green" {
  seed_window 5h 59 $((NOW + 3600))
  AI_USAGE_NOW=$NOW run render codex
  [ "$(bar_part)" = '#a6e3a1 ▰▰▰▱▱' ]
}

@test "from 60% the bar is yellow" {
  seed_window 5h 60 $((NOW + 3600))
  AI_USAGE_NOW=$NOW run render codex
  [ "$(bar_part)" = '#f9e2af ▰▰▰▱▱' ]
}

@test "from 85% the bar is red" {
  seed_window 5h 85 $((NOW + 3600))
  AI_USAGE_NOW=$NOW run render codex
  [ "$(bar_part)" = '#f38ba8 ▰▰▰▰▱' ]
}

@test "a full window fills every cell" {
  seed_window 5h 100 $((NOW + 3600))
  AI_USAGE_NOW=$NOW run render codex
  [ "$(bar_part)" = '#f38ba8 ▰▰▰▰▰' ]
}

@test "an empty window fills no cell" {
  seed_window 5h 0 $((NOW + 3600))
  AI_USAGE_NOW=$NOW run render codex
  [ "$(bar_part)" = '#a6e3a1 ▱▱▱▱▱' ]
}

countdown_part() { sed -E 's/^.*#\[fg=[^]]*\]([^#]*)#\[fg=default\]$/\1/' <<<"$output"; }

@test "the countdown shows the two largest units and drops a zero remainder" {
  for case in "2820 47m" "7980 2h13m" "274000 3d4h" "86400 1d" "3600 1h" "59 0m"; do
    read -r secs want <<<"$case"
    seed_window 5h 10 $((NOW + secs))
    AI_USAGE_NOW=$NOW run render codex
    [ "$(countdown_part)" = "$want" ] || { echo "for $secs s: got '$(countdown_part)', want '$want'"; return 1; }
  done
}

@test "the bar glyphs survive the C locale tmux may run #() with" {
  seed_snapshot primary-only $NOW
  LC_ALL=C LANG=C AI_USAGE_NOW=$NOW run render codex
  [ "$output" = '#[fg=#bac2de]cx #[fg=#6c7086]wk #[fg=#f9e2af]▰▰▰▱▱ #[fg=#6c7086]2d1h#[fg=default]' ]
}

@test "pending with no snapshot yet shows a dim ellipsis" {
  rm -f "$CACHE/codex.json"
  AI_USAGE_NOW=$NOW run render codex
  [ "$output" = '#[fg=#6c7086]cx …#[fg=default]' ]
}

@test "signed_out shows !login in the crit colour immediately" {
  seed_status signed_out "$NOW"
  AI_USAGE_NOW=$NOW run render codex
  [ "$output" = '#[fg=#f38ba8]cx !login#[fg=default]' ]
}

@test "missing_dep shows !deps in the crit colour immediately" {
  seed_status missing_dep
  AI_USAGE_NOW=$NOW run render codex
  [ "$output" = '#[fg=#f38ba8]cx !deps#[fg=default]' ]
}

@test "bad_shape shows !format in the crit colour immediately" {
  seed_status bad_shape
  AI_USAGE_NOW=$NOW run render codex
  [ "$output" = '#[fg=#f38ba8]cx !format#[fg=default]' ]
}

@test "error with no prior good reading shows !error in the crit colour" {
  seed_status error
  AI_USAGE_NOW=$NOW run render codex
  [ "$output" = '#[fg=#f38ba8]cx !error#[fg=default]' ]
}

@test "a transient error still shows the last good value unmarked" {
  seed_snapshot primary-only $NOW
  patch_snapshot --argjson now "$NOW" '.status = "error" | .fetched_at = $now'
  AI_USAGE_NOW=$NOW run render codex
  [ "$output" = '#[fg=#bac2de]cx #[fg=#6c7086]wk #[fg=#f9e2af]▰▰▰▱▱ #[fg=#6c7086]2d1h#[fg=default]' ]
}

@test "a stale reading is dim with a tilde before the percentage" {
  seed_snapshot primary-only $NOW
  patch_snapshot --argjson ok $((NOW - 901)) '.ok_at = $ok'
  AI_USAGE_NOW=$NOW run render codex
  [ "$output" = '#[fg=#6c7086]cx #[fg=#6c7086]wk #[fg=#6c7086]~▰▰▰▱▱ #[fg=#6c7086]2d1h#[fg=default]' ]
}

@test "a window past its reset time shows 0% with no countdown" {
  seed_window 5h 81 $((NOW - 120))
  AI_USAGE_NOW=$NOW run render codex
  [ "$output" = '#[fg=#bac2de]cx #[fg=#6c7086]5h #[fg=#a6e3a1]▱▱▱▱▱#[fg=default]' ]
}
