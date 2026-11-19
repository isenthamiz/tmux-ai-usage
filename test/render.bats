load test_helper

setup() { setup_env; }

NOW=1795074751

@test "codex piece shows its most-used window in the theme's colours" {
  cat > "$TMUX_SHIM_OPTIONS" <<'OPTS'
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
  [ "$output" = '#[fg=#cccccc]cx #[fg=#666666]5h #[fg=#aaaa00]▰▰▰▰▱ 81% #[fg=#666666]47m#[fg=default]' ]
}

@test "without theme options the Catppuccin Mocha colours are used" {
  seed_snapshot primary-only $NOW
  AI_USAGE_NOW=$NOW run render codex
  [ "$output" = '#[fg=#bac2de]cx #[fg=#6c7086]wk #[fg=#f9e2af]▰▰▰▱▱ 66% #[fg=#6c7086]2d1h#[fg=default]' ]
}

# Bar and colour only: everything between the window label and the countdown.
bar_part() { sed -E 's/^.*5h #\[fg=([^]]*)\]([^ ]*) ([0-9]+%).*$/\1 \2 \3/' <<<"$output"; }

@test "below 60% the bar is green" {
  seed_window 5h 59 $((NOW + 3600))
  AI_USAGE_NOW=$NOW run render codex
  [ "$(bar_part)" = '#a6e3a1 ▰▰▰▱▱ 59%' ]
}

@test "from 60% the bar is yellow" {
  seed_window 5h 60 $((NOW + 3600))
  AI_USAGE_NOW=$NOW run render codex
  [ "$(bar_part)" = '#f9e2af ▰▰▰▱▱ 60%' ]
}

@test "from 85% the bar is red" {
  seed_window 5h 85 $((NOW + 3600))
  AI_USAGE_NOW=$NOW run render codex
  [ "$(bar_part)" = '#f38ba8 ▰▰▰▰▱ 85%' ]
}

@test "a full window fills every cell" {
  seed_window 5h 100 $((NOW + 3600))
  AI_USAGE_NOW=$NOW run render codex
  [ "$(bar_part)" = '#f38ba8 ▰▰▰▰▰ 100%' ]
}

@test "an empty window fills no cell" {
  seed_window 5h 0 $((NOW + 3600))
  AI_USAGE_NOW=$NOW run render codex
  [ "$(bar_part)" = '#a6e3a1 ▱▱▱▱▱ 0%' ]
}

countdown_part() { sed -E 's/^.*#\[fg=[^]]*\]([^#]*)#\[fg=default\]$/\1/' <<<"$output"; }

@test "the countdown shows the two largest units and drops a zero remainder" {
  for case in "2820 47m" "7980 2h13m" "274000 3d4h" "86400 1d" "3600 1h" "59 0m"; do
    set -- $case
    seed_window 5h 10 $((NOW + $1))
    AI_USAGE_NOW=$NOW run render codex
    [ "$(countdown_part)" = "$2" ] || { echo "for $1 s: got '$(countdown_part)', want '$2'"; return 1; }
  done
}

@test "the bar glyphs survive the C locale tmux may run #() with" {
  seed_snapshot primary-only $NOW
  LC_ALL=C LANG=C AI_USAGE_NOW=$NOW run render codex
  [ "$output" = '#[fg=#bac2de]cx #[fg=#6c7086]wk #[fg=#f9e2af]▰▰▰▱▱ 66% #[fg=#6c7086]2d1h#[fg=default]' ]
}
