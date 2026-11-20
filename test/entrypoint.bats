#!/usr/bin/env bats
# Plugin load: option validation and jq-missing behaviour (tmux shim).
# shellcheck disable=SC2030,SC2031
load test_helper

setup() {
  setup_env
  export TMUX_SHIM_SET_LOG="$BATS_TEST_TMPDIR/tmux-set.log"
  export TMUX_SHIM_MSG_LOG="$BATS_TEST_TMPDIR/tmux-msg.log"
  : >"$TMUX_SHIM_SET_LOG"
  : >"$TMUX_SHIM_MSG_LOG"
}

load_plugin() {
  TMUX_SHIM_OPTIONS="$TMUX_SHIM_OPTIONS" \
    /bin/bash "$ROOT/ai_usage.tmux"
}

@test "invalid bar width is reset at load with one display-message" {
  cat >"$TMUX_SHIM_OPTIONS" <<'OPTS'
status-right #{ai_usage_codex}
@ai_usage_bar_width xy
OPTS
  load_plugin
  grep -q '@ai_usage_bar_width invalid' "$TMUX_SHIM_MSG_LOG"
  grep -q 'set-option -gq @ai_usage_bar_width 5' "$TMUX_SHIM_SET_LOG"
}

@test "unknown provider is reported and stripped at load" {
  cat >"$TMUX_SHIM_OPTIONS" <<'OPTS'
status-right #{ai_usage}
@ai_usage_providers codex bogus
OPTS
  load_plugin
  grep -q '@ai_usage_providers invalid' "$TMUX_SHIM_MSG_LOG"
  grep -q 'set-option -gq @ai_usage_providers codex' "$TMUX_SHIM_SET_LOG"
}

@test "missing jq rewrites tokens to !jq in crit colour" {
  cat >"$TMUX_SHIM_OPTIONS" <<'OPTS'
status-right #{ai_usage_claude} #{ai_usage}
OPTS
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat >"$BATS_TEST_TMPDIR/bin/jq" <<'EOF'
#!/bin/sh
exit 127
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/jq"
  export PATH="$BATS_TEST_TMPDIR/bin:$ROOT/test/shims:$PATH"
  load_plugin
  grep -q 'jq not found' "$TMUX_SHIM_MSG_LOG"
  grep -Fq '#[fg=#f38ba8]!jq' "$TMUX_SHIM_SET_LOG"
}
@test "step widths that are not four descending integers are reset at load" {
  cat >"$TMUX_SHIM_OPTIONS" <<'OPTS'
status-right #{ai_usage}
@ai_usage_step_widths 80 110 140 180
OPTS
  load_plugin
  grep -q '@ai_usage_step_widths invalid' "$TMUX_SHIM_MSG_LOG"
  grep -q 'set-option -gq @ai_usage_step_widths 180 140 110 80' "$TMUX_SHIM_SET_LOG"
}

@test "an unknown step is reset to auto at load" {
  cat >"$TMUX_SHIM_OPTIONS" <<'OPTS'
status-right #{ai_usage}
@ai_usage_step 5
OPTS
  load_plugin
  grep -q '@ai_usage_step invalid' "$TMUX_SHIM_MSG_LOG"
  grep -q 'set-option -gq @ai_usage_step auto' "$TMUX_SHIM_SET_LOG"
}

@test "valid step options load without a message" {
  cat >"$TMUX_SHIM_OPTIONS" <<'OPTS'
status-right #{ai_usage}
@ai_usage_step_widths 200 150 100 50
@ai_usage_step 2
OPTS
  load_plugin
  [ ! -s "$TMUX_SHIM_MSG_LOG" ]
}

@test "the tmux version is recorded at load for the renderer" {
  cat >"$TMUX_SHIM_OPTIONS" <<'OPTS'
status-right #{ai_usage}
OPTS
  TMUX_SHIM_VERSION=3.1c load_plugin
  grep -q 'set-option -gq @ai_usage_tmux_version 3.1c' "$TMUX_SHIM_SET_LOG"
}

@test "an unknown rotate value is reset to off at load" {
  cat >"$TMUX_SHIM_OPTIONS" <<'OPTS'
status-right #{ai_usage}
@ai_usage_rotate yes
OPTS
  load_plugin
  grep -q '@ai_usage_rotate invalid' "$TMUX_SHIM_MSG_LOG"
  grep -q 'set-option -gq @ai_usage_rotate off' "$TMUX_SHIM_SET_LOG"
}

@test "a rotate interval that is not a positive integer is reset to 10 at load" {
  cat >"$TMUX_SHIM_OPTIONS" <<'OPTS'
status-right #{ai_usage}
@ai_usage_rotate_interval 0
OPTS
  load_plugin
  grep -q '@ai_usage_rotate_interval invalid' "$TMUX_SHIM_MSG_LOG"
  grep -q 'set-option -gq @ai_usage_rotate_interval 10' "$TMUX_SHIM_SET_LOG"
}

@test "with focus on, #{ai_usage} passes the pane's command and tty" {
  cat >"$TMUX_SHIM_OPTIONS" <<'OPTS'
status-right #{ai_usage} #{ai_usage_claude}
@ai_usage_focus on
OPTS
  load_plugin
  grep -Fq "set-option -gq status-right #('$ROOT/scripts/render.sh' all #{q:pane_current_command} #{q:pane_tty}) #('$ROOT/scripts/render.sh' claude)" "$TMUX_SHIM_SET_LOG"
}

@test "with focus off, #{ai_usage} passes no pane arguments" {
  cat >"$TMUX_SHIM_OPTIONS" <<'OPTS'
status-right #{ai_usage}
OPTS
  load_plugin
  grep -Fxq "set-option -gq status-right #('$ROOT/scripts/render.sh' all)" "$TMUX_SHIM_SET_LOG"
}

@test "an unknown focus value is reset to off at load" {
  cat >"$TMUX_SHIM_OPTIONS" <<'OPTS'
status-right #{ai_usage}
@ai_usage_focus yes
OPTS
  load_plugin
  grep -q '@ai_usage_focus invalid' "$TMUX_SHIM_MSG_LOG"
  grep -q 'set-option -gq @ai_usage_focus off' "$TMUX_SHIM_SET_LOG"
  grep -Fxq "set-option -gq status-right #('$ROOT/scripts/render.sh' all)" "$TMUX_SHIM_SET_LOG"
}
