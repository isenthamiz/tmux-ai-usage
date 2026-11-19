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