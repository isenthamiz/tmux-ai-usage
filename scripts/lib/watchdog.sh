# shellcheck shell=bash
# Hard time limit for a command (macOS has no timeout). Prints child stdout.

run_with_timeout() { # seconds command...
  local limit=$1 pid start=$SECONDS
  shift
  local out
  out=$(mktemp) || return 1
  trap 'rm -f "$out"' RETURN
  ( "$@" >"$out" ) &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if [ $((SECONDS - start)) -ge "$limit" ]; then
      kill "$pid" 2>/dev/null
      wait "$pid" 2>/dev/null
      rm -f "$out"
      return 124
    fi
    sleep 1
  done
  wait "$pid"
  local rc=$?
  cat "$out"
  return "$rc"
}