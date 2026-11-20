#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031
load test_helper

setup() { setup_env; force_step full; }

NOW=1795074751

seed_all_providers() {
  seed_snapshot_claude five-hour-weekly "$NOW"
  seed_snapshot primary-secondary "$NOW"
  seed_snapshot_cursor unified-weekly "$NOW"
}

# shellcheck disable=SC2001
combined_output() { sed 's/#\[fg=default\]$//' <<<"$output"; }

@test "#{ai_usage} joins default providers in order with the default separator in dim" {
  seed_all_providers
  AI_USAGE_NOW=$NOW run render all
  [ "$status" -eq 0 ]
  [ "$(combined_output)" = \
'#[fg=#bac2de]cl #[fg=#6c7086]wk #[fg=#f9e2af]▰▰▰▱▱ #[fg=#6c7086]7d2h#[fg=#6c7086] │ #[fg=#bac2de]cx #[fg=#6c7086]5h #[fg=#f9e2af]▰▰▰▰▱ #[fg=#6c7086]47m#[fg=#6c7086] │ #[fg=#bac2de]cu #[fg=#6c7086]wk #[fg=#a6e3a1]▰▰▰▱▱ #[fg=#6c7086]2d1h' ]
}

@test "@ai_usage_providers sets order and membership for #{ai_usage}" {
  seed_all_providers
  cat >> "$TMUX_SHIM_OPTIONS" <<'OPTS'
@ai_usage_providers codex claude
OPTS
  AI_USAGE_NOW=$NOW run render all
  [ "$(combined_output)" = \
'#[fg=#bac2de]cx #[fg=#6c7086]5h #[fg=#f9e2af]▰▰▰▰▱ #[fg=#6c7086]47m#[fg=#6c7086] │ #[fg=#bac2de]cl #[fg=#6c7086]wk #[fg=#f9e2af]▰▰▰▱▱ #[fg=#6c7086]7d2h' ]
}

@test "@ai_usage_separator replaces the joiner between pieces" {
  seed_all_providers
  cat >> "$TMUX_SHIM_OPTIONS" <<'OPTS'
@ai_usage_providers codex claude
@ai_usage_separator ::
OPTS
  AI_USAGE_NOW=$NOW run render all
  [ "$(combined_output)" = \
'#[fg=#bac2de]cx #[fg=#6c7086]5h #[fg=#f9e2af]▰▰▰▰▱ #[fg=#6c7086]47m#[fg=#6c7086]::#[fg=#bac2de]cl #[fg=#6c7086]wk #[fg=#f9e2af]▰▰▰▱▱ #[fg=#6c7086]7d2h' ]
}

@test "a per-provider token still renders when that provider is omitted from @ai_usage_providers" {
  seed_snapshot_claude five-hour-weekly "$NOW"
  cat >> "$TMUX_SHIM_OPTIONS" <<'OPTS'
@ai_usage_providers codex
OPTS
  AI_USAGE_NOW=$NOW run render claude
  [ "$output" = '#[fg=#bac2de]cl #[fg=#6c7086]wk #[fg=#f9e2af]▰▰▰▱▱ #[fg=#6c7086]7d2h#[fg=default]' ]
}

@test "auto picks the highest utilized window including model-scoped" {
  seed_snapshot_claude with-model-scoped "$NOW"
  AI_USAGE_NOW=$NOW run render claude
  [ "$output" = '#[fg=#bac2de]cl #[fg=#6c7086]wk-opus #[fg=#a6e3a1]▰▰▰▱▱ #[fg=#6c7086]7d4h#[fg=default]' ]
}

@test "@ai_usage_<provider>_window pins a window by label" {
  seed_snapshot primary-secondary "$NOW"
  cat >> "$TMUX_SHIM_OPTIONS" <<'OPTS'
@ai_usage_codex_window wk
OPTS
  AI_USAGE_NOW=$NOW run render codex
  [ "$output" = '#[fg=#bac2de]cx #[fg=#6c7086]wk #[fg=#a6e3a1]▰▰▱▱▱ #[fg=#6c7086]5d2h#[fg=default]' ]
}

@test "a pinned label missing from the snapshot falls back to auto" {
  seed_snapshot primary-secondary "$NOW"
  cat >> "$TMUX_SHIM_OPTIONS" <<'OPTS'
@ai_usage_codex_window daily
OPTS
  AI_USAGE_NOW=$NOW run render codex
  [ "$output" = '#[fg=#bac2de]cx #[fg=#6c7086]5h #[fg=#f9e2af]▰▰▰▰▱ #[fg=#6c7086]47m#[fg=default]' ]
}

@test "a reset window counts as 0% when auto-selecting among windows" {
  jq -n --argjson now "$NOW" \
    '{provider:"codex",status:"ok",fetched_at:$now,ok_at:$now,retry_at:$now,error:null,
      windows:[
        {label:"5h",used_pct:81,resets_at:($now - 120),window_seconds:18000},
        {label:"wk",used_pct:35,resets_at:($now + 440000),window_seconds:604800}
      ]}' > "$CACHE/codex.json"
  AI_USAGE_NOW=$NOW run render codex
  [ "$output" = '#[fg=#bac2de]cx #[fg=#6c7086]wk #[fg=#a6e3a1]▰▰▱▱▱ #[fg=#6c7086]5d2h#[fg=default]' ]
}