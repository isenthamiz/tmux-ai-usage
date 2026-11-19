#!/usr/bin/env bats
# load-time validation and renderer golden strings for bar/label/colour options.
# shellcheck disable=SC2030,SC2031,SC2016
load test_helper

setup() { setup_env; }

NOW=1795074751

@test "invalid @ai_usage_bar_width falls back to default in render output" {
  cat >>"$TMUX_SHIM_OPTIONS" <<'OPTS'
@ai_usage_bar_width xy
OPTS
  seed_snapshot primary-only $NOW
  AI_USAGE_NOW=$NOW run render codex
  [ "$output" = '#[fg=#bac2de]cx #[fg=#6c7086]wk #[fg=#f9e2af]▰▰▰▱▱ 66% #[fg=#6c7086]2d1h#[fg=default]' ]
}

@test "warn_at >= crit_at falls back to 60/85 thresholds" {
  cat >>"$TMUX_SHIM_OPTIONS" <<'OPTS'
@ai_usage_warn_at 90
@ai_usage_crit_at 85
OPTS
  seed_window 5h 86 $((NOW + 3600))
  AI_USAGE_NOW=$NOW run render codex
  [[ "$output" == *'#[fg=#f38ba8]'*▰▰▰▰▱*'86%'* ]]
}

@test "stale_after below refresh interval falls back to default stale behaviour" {
  cat >>"$TMUX_SHIM_OPTIONS" <<'OPTS'
@ai_usage_refresh_interval 60
@ai_usage_stale_after 30
OPTS
  seed_snapshot primary-only $NOW
  patch_snapshot --argjson ok $((NOW - 901)) '.ok_at = $ok'
  AI_USAGE_NOW=$NOW run render codex
  [ "$output" = '#[fg=#6c7086]cx #[fg=#6c7086]wk #[fg=#6c7086]▰▰▰▱▱ ~66% #[fg=#6c7086]2d1h#[fg=default]' ]
}

@test "@ai_usage_bar_width 0 shows percentage only" {
  cat >>"$TMUX_SHIM_OPTIONS" <<'OPTS'
@ai_usage_bar_width 0
OPTS
  seed_window 5h 66 $((NOW + 7200))
  AI_USAGE_NOW=$NOW run render codex
  [ "$output" = '#[fg=#bac2de]cx #[fg=#6c7086]5h #[fg=#f9e2af]66% #[fg=#6c7086]2h#[fg=default]' ]
}

@test "custom bar glyphs labels and colours" {
  cat >>"$TMUX_SHIM_OPTIONS" <<'OPTS'
@ai_usage_bar_width 3
@ai_usage_bar_filled =
@ai_usage_bar_empty -
@ai_usage_codex_label CX
@ai_usage_warn_at 50
@ai_usage_crit_at 80
@ai_usage_ok_color "#111111"
@ai_usage_warn_color "#222222"
@ai_usage_crit_color "#333333"
@ai_usage_text_color "#444444"
@ai_usage_dim_color "#555555"
OPTS
  seed_window 5h 55 $((NOW + 3600))
  AI_USAGE_NOW=$NOW run render codex
  [ "$output" = '#[fg=#444444]CX #[fg=#555555]5h #[fg=#222222]==- 55% #[fg=#555555]1h#[fg=default]' ]
}

@test "@ai_usage_cache_dir redirects the snapshot path" {
  local alt="$BATS_TEST_TMPDIR/alt-cache"
  cat >>"$TMUX_SHIM_OPTIONS" <<OPTS
@ai_usage_cache_dir $alt
OPTS
  mkdir -p "$alt"
  jq -n --argjson now "$NOW" \
    '{provider:"codex",status:"ok",fetched_at:$now,ok_at:$now,retry_at:$now,error:null,
      windows:[{label:"wk",used_pct:10,resets_at:($now+3600),window_seconds:3600}]}' \
    >"$alt/codex.json"
  AI_USAGE_NOW=$NOW run render codex
  [[ "$output" == *'10%'* ]]
}

@test "render uses one jq invocation" {
  export AI_USAGE_NO_REFRESH=1
  seed_snapshot primary-only $NOW
  export JQ_SHIM_LOG="$BATS_TEST_TMPDIR/jq.log"
  : >"$JQ_SHIM_LOG"
  AI_USAGE_NOW=$NOW run render codex
  [ "$(wc -l <"$JQ_SHIM_LOG" | tr -d ' ')" -eq 1 ]
}