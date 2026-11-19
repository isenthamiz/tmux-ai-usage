# shellcheck shell=bash
# Refresh lock: an atomic mkdir holding the owner's pid (flock is not on macOS,
# lockf/shlock are not on Linux). A lock whose owner is dead, or that is older
# than LOCK_MAX_AGE seconds, is broken.
LOCK_MAX_AGE=120

lock_acquire() { # lock-dir
  local lock=$1 pid mtime age
  if mkdir "$lock" 2>/dev/null; then
    echo $$ > "$lock/pid"
    return 0
  fi
  pid=$(cat "$lock/pid" 2>/dev/null)
  mtime=$(stat -f %m "$lock" 2>/dev/null || stat -c %Y "$lock" 2>/dev/null || echo 0)
  age=$(( $(date +%s) - mtime ))
  if [ "$age" -lt "$LOCK_MAX_AGE" ]; then
    # No pid yet means the owner is between mkdir and writing it: still held.
    [ -z "$pid" ] && return 1
    kill -0 "$pid" 2>/dev/null && return 1
  fi
  rm -rf "$lock"
  mkdir "$lock" 2>/dev/null || return 1
  echo $$ > "$lock/pid"
}

lock_release() { rm -rf "$1"; }
