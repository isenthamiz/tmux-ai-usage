#!/usr/bin/env bats
# Focus: #{ai_usage} shows only the provider whose agent runs in the active
# pane. render.sh gets the pane's command and tty as arguments.
# shellcheck disable=SC2030,SC2031,SC2016
load test_helper

setup() {
  setup_env
  export PS_SHIM_LOG="$BATS_TEST_TMPDIR/ps.log"
  export PS_SHIM_OUTPUT="$BATS_TEST_TMPDIR/ps.out"
  : >"$PS_SHIM_LOG"
  : >"$PS_SHIM_OUTPUT"
  seed_snapshot_claude five-hour-weekly "$NOW"
  seed_snapshot primary-secondary "$NOW"
  seed_snapshot_cursor unified-weekly "$NOW"
  opt @ai_usage_step 4
}

NOW=1795074750
TTY=/dev/ttys008

CL='#[fg=#f9e2af]cl#[fg=default]'
CX='#[fg=#f9e2af]cx#[fg=default]'
CU='#[fg=#a6e3a1]cu#[fg=default]'
ALL='#[fg=#f9e2af]cl #[fg=#f9e2af]cx #[fg=#a6e3a1]cu#[fg=default]'

# Each process row: its args, in the foreground process group unless it
# starts with "bg ". Written as `ps -o pgid=,tpgid=,args=` would print them.
pane() { # pane_current_command [process...]
  local cmd=$1 row
  shift
  : >"$PS_SHIM_OUTPUT"
  for row in "$@"; do
    case $row in
      'bg '*) printf '  200   300 %s\n' "${row#bg }" ;;
      *) printf '  300   300 %s\n' "$row" ;;
    esac >>"$PS_SHIM_OUTPUT"
  done
  AI_USAGE_NOW=$NOW AI_USAGE_NO_REFRESH=1 render all "$cmd" "$TTY"
}

ps_calls() { wc -l <"$PS_SHIM_LOG" | tr -d ' '; }

@test "Claude's native installer shows a version string and focuses Claude" {
  [ "$(pane 2.1.328)" = "$CL" ]
  [ "$(ps_calls)" = 0 ]
}

@test "codex, claude and claude.exe focus by name alone" {
  [ "$(pane codex)" = "$CX" ]
  [ "$(pane claude)" = "$CL" ]
  [ "$(pane claude.exe)" = "$CL" ]
  [ "$(ps_calls)" = 0 ]
}

@test "Cursor runs as node: one ps finds the cursor-agent path" {
  [ "$(pane node \
    'bg -zsh' \
    '/Users/me/.local/bin/agent --use-system-ca /Users/me/.local/share/cursor-agent/versions/2026.11.19-f005e9d/index.js')" = "$CU" ]
  [ "$(cat "$PS_SHIM_LOG")" = "-t $TTY -o pgid=,tpgid=,args=" ]
}

@test "Codex on older Node runs as node: ps finds the codex path" {
  [ "$(pane node 'node /opt/homebrew/lib/node_modules/@openai/codex/bin/codex.js' \
    '/opt/homebrew/lib/node_modules/@openai/codex/vendor/aarch64-apple-darwin/codex/codex')" = "$CX" ]
}

@test "an agent behind a shell wrapper is found by ps" {
  [ "$(pane bash 'bg -zsh' '/bin/bash wrap.sh' '/Users/me/.local/bin/claude --resume')" = "$CL" ]
  [ "$(pane bash 'bg -zsh' '/bin/bash wrap.sh' '/opt/homebrew/bin/codex')" = "$CX" ]
}

@test "a plain shell or other node program means no focus" {
  [ "$(pane zsh '-zsh')" = "$ALL" ]
  [ "$(pane node 'node server.js')" = "$ALL" ]
}

@test "any other command means no focus and no ps" {
  [ "$(pane vim)" = "$ALL" ]
  [ "$(pane python3.12)" = "$ALL" ]
  [ "$(pane 1.2)" = "$ALL" ]
  [ "$(pane 1.2.3.4)" = "$ALL" ]
  [ "$(pane '')" = "$ALL" ]
  [ "$(ps_calls)" = 0 ]
}

@test "focus on a provider not in @ai_usage_providers is ignored" {
  opt @ai_usage_providers '"claude cursor"'
  [ "$(pane codex)" = '#[fg=#f9e2af]cl #[fg=#a6e3a1]cu#[fg=default]' ]
}

@test "focus overrides rotation" {
  opt @ai_usage_rotate on
  # Rotation alone would show claude at NOW.
  [ "$(pane codex)" = "$CX" ]
  [ "$(AI_USAGE_NOW=$((NOW + 10)) AI_USAGE_NO_REFRESH=1 render all codex "$TTY")" = "$CX" ]
  [ "$(pane vim)" = "$CL" ]
}

@test "a per-provider token ignores focus" {
  [ "$(AI_USAGE_NOW=$NOW AI_USAGE_NO_REFRESH=1 render cursor codex "$TTY")" = "$CU" ]
}

@test "steps apply to the focused provider" {
  : >"$TMUX_SHIM_OPTIONS"
  [ "$(pane codex)" = "$(nested \
    '#[fg=#bac2de]cx #[fg=#6c7086]5h #[fg=#f9e2af]▰▰▰▰▱ #[fg=#6c7086]47m' \
    '#[fg=#bac2de]cx #[fg=#f9e2af]▰▰▰▰▱ #[fg=#6c7086]47m' \
    '#[fg=#bac2de]cx #[fg=#f9e2af]▰▰▰▰▱' \
    '#[fg=#bac2de]cx #[fg=#f9e2af]81%' \
    '#[fg=#f9e2af]cx')" ]
}

@test "only the foreground process group counts, not background jobs" {
  [ "$(pane zsh '-zsh' 'bg /Users/me/.local/bin/claude')" = "$ALL" ]
  [ "$(pane zsh '-zsh' 'bg vim /Users/me/notes/claude')" = "$ALL" ]
}

@test "arguments that merely mention an agent do not focus" {
  [ "$(pane node 'node /Users/me/app.js --log /tmp/claude')" = "$ALL" ]
  [ "$(pane bash '/bin/bash -c grep -r cursor-agent .')" = "$ALL" ]
  [ "$(pane bash 'cat /Users/me/notes/codex')" = "$ALL" ]
}

@test "process arguments are not glob-expanded" {
  cd "$BATS_TEST_TMPDIR" && touch claude
  [ "$(pane bash '/bin/bash -c ls *')" = "$ALL" ]
}

@test "an empty pane command, dropped by #{q:}, means no focus" {
  [ "$(AI_USAGE_NOW=$NOW AI_USAGE_NO_REFRESH=1 render all "$TTY")" = "$ALL" ]
  [ "$(ps_calls)" = 0 ]
}
