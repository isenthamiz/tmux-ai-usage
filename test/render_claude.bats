#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031
load test_helper

setup() { setup_env; force_step full; }

NOW=1795074751

@test "claude piece shows its highest-utilization window" {
  seed_snapshot_claude five-hour-weekly $NOW
  AI_USAGE_NOW=$NOW run render claude
  [ "$output" = '#[fg=#bac2de]cl #[fg=#6c7086]wk #[fg=#f9e2af]▰▰▰▱▱ #[fg=#6c7086]7d2h#[fg=default]' ]
}