# Shared setup for bats tests.
ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
FIXTURES="$ROOT/test/fixtures"

# Canonical, compact JSON so expected snapshots can be compared as strings.
canon() { jq -S -c . "$@"; }

# Isolated environment per test: shimmed tmux on PATH, private cache dir.
setup_env() {
  export PATH="$ROOT/test/shims:$PATH"
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

render() { "$ROOT/scripts/render.sh" "$@"; }

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
