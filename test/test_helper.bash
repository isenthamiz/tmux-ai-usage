# Shared setup for bats tests.
ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
FIXTURES="$ROOT/test/fixtures"

# Canonical, compact JSON so expected snapshots can be compared as strings.
canon() { jq -S -c . "$@"; }

# Isolated environment per test: shimmed tmux on PATH, private cache dir.
setup_env() {
  export PATH="$ROOT/test/shims:$PATH"
  export JQ_SHIM_LOG=""
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"
  export TMUX_SHIM_OPTIONS="$BATS_TEST_TMPDIR/tmux-options"
  export TMUX_SHIM_LOG="$BATS_TEST_TMPDIR/tmux.log"
  CACHE="$XDG_CACHE_HOME/tmux-ai-usage"
  mkdir -p "$CACHE"
  : > "$TMUX_SHIM_OPTIONS"
}

# Write a codex usage snapshot from a fixture, as if read at $2.
seed_snapshot() { # fixture fetched_at
  jq --argjson now "$2" -L "$ROOT/scripts/lib" -f "$ROOT/scripts/providers/codex/normalize.jq" \
    "$FIXTURES/codex/$1.json" > "$CACHE/codex.json"
}

seed_snapshot_claude() { # fixture fetched_at
  jq --argjson now "$2" -L "$ROOT/scripts/lib" -f "$ROOT/scripts/providers/claude/normalize.jq" \
    "$FIXTURES/claude/$1.json" > "$CACHE/claude.json"
}

setup_claude() { # get_usage-body-fixture
  export CLAUDE_SHIM_LOG="$BATS_TEST_TMPDIR/claude.log"
  export CLAUDE_SHIM_RESPONSE="$FIXTURES/claude/$1.json"
}

claude_calls() { [ -f "$CLAUDE_SHIM_LOG" ] && wc -l < "$CLAUDE_SHIM_LOG" | tr -d ' ' || echo 0; }

seed_snapshot_cursor() { # fixture fetched_at
  jq --argjson now "$2" -L "$ROOT/scripts/lib" -f "$ROOT/scripts/providers/cursor/normalize.jq" \
    "$FIXTURES/cursor/$1.json" > "$CACHE/cursor.json"
}

setup_cursor() { # unified|legacy
  export CURSOR_STATE_DB="$BATS_TEST_TMPDIR/cursor-state.vscdb"
  touch "$CURSOR_STATE_DB"
  export CURSOR_SHIM_TOKEN="${CURSOR_TEST_JWT:-eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJhdXRoMHx0ZXN0dXNlciIsImV4cCI6MTg5MzQ1NjAwMH0.sig}"
  export CURL_SHIM_LOG="$BATS_TEST_TMPDIR/curl.log"
  : >"$CURL_SHIM_LOG"
  export CURL_SHIM_SAND_RESPONSE="$FIXTURES/cursor/sand-unified.json"
  unset CURL_SHIM_SUMMARY_RESPONSE
}

render() { "$ROOT/scripts/render.sh" "$@"; }
refresh() { "$ROOT/scripts/refresh.sh" "$@"; }

# Write a codex snapshot holding a single window. fetched_at defaults to $NOW.
seed_window() { # label used_pct resets_at [fetched_at]
  local at=${4:-$NOW}
  jq -n --arg l "$1" --argjson p "$2" --argjson r "$3" --argjson at "$at" \
    '{provider:"codex",status:"ok",fetched_at:$at,ok_at:$at,retry_at:$at,error:null,
      windows:[{label:$l,used_pct:$p,resets_at:$r,window_seconds:18000}]}' > "$CACHE/codex.json"
}

# Fake Codex sign-in and a fake wham/usage endpoint serving a fixture.
setup_codex() { # response-fixture
  export CODEX_HOME="$BATS_TEST_TMPDIR/codex"
  mkdir -p "$CODEX_HOME"
  echo '{"auth_mode":"chatgpt","tokens":{"access_token":"test-token","account_id":"test-account"}}' > "$CODEX_HOME/auth.json"
  export CURL_SHIM_LOG="$BATS_TEST_TMPDIR/curl.log"
  export CURL_SHIM_RESPONSE="$FIXTURES/codex/$1.json"
}

curl_calls() { [ -f "$CURL_SHIM_LOG" ] && wc -l < "$CURL_SHIM_LOG" | tr -d ' ' || echo 0; }

# Poll until a command succeeds, up to $2 seconds (default 5).
wait_for() { # command [seconds]
  local tries=$(( ${2:-5} * 10 ))
  while [ "$tries" -gt 0 ]; do
    eval "$1" && return 0
    sleep 0.1; tries=$((tries - 1))
  done
  return 1
}

# True once no refresh holds the codex lock.
refresh_idle() { [ ! -d "$CACHE/codex.lock" ]; }

# Merge fields into the codex snapshot on disk.
patch_snapshot() { jq "$@" "$CACHE/codex.json" >"$CACHE/codex.json.tmp" && mv "$CACHE/codex.json.tmp" "$CACHE/codex.json"; }

# Usage snapshot with a non-ok status and optional windows from a prior good reading.
seed_status() { # status [ok_at]
  local st=$1 oat=${2:-null}
  jq -n --arg p codex --arg st "$st" --argjson now "${NOW:-0}" --argjson oat "$oat" \
    '{provider:$p,status:$st,fetched_at:$now,ok_at:$oat,retry_at:$now,error:"test",
      windows:(if $oat == null then [] else [{label:"wk",used_pct:66,resets_at:($now+7200),window_seconds:604800}] end)}' \
    > "$CACHE/codex.json"
}

# Pin render.sh to one step instead of the client_width conditional.
force_step() { echo "@ai_usage_step $1" >> "$TMUX_SHIM_OPTIONS"; }

# The nested client_width conditional render.sh prints for `auto`.
nested() { # full s1 s2 s3 s4 [widths for full, step 1, 2, 3]
  local w1=${6:-180} w2=${7:-140} w3=${8:-110} w4=${9:-80}
  printf '#{?#{e|>=:#{client_width},%s},%s,#{?#{e|>=:#{client_width},%s},%s,#{?#{e|>=:#{client_width},%s},%s,#{?#{e|>=:#{client_width},%s},%s,%s}}}}#[fg=default]' \
    "$w1" "$1" "$w2" "$2" "$w3" "$3" "$w4" "$4" "$5"
}

# Set one tmux option for render.sh.
opt() { echo "$1 $2" >> "$TMUX_SHIM_OPTIONS"; }
