# shellcheck shell=bash
# Refresh lock: an atomic mkdir holding the owner's pid (flock is not on macOS,
# lockf/shlock are not on Linux). A lock whose owner is dead, or that is older
# than LOCK_MAX_AGE seconds, is broken.
#
# Ages use the real clock, not AI_USAGE_NOW: they are compared with directory
# mtimes, which the filesystem stamps in real time.
LOCK_MAX_AGE=120

_age() { # path -> seconds since its mtime
  local mtime
  mtime=$(stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0)
  echo $(( $(date +%s) - mtime ))
}

_lock_is_stale() { # lock-dir
  local pid
  [ "$(_age "$1")" -ge "$LOCK_MAX_AGE" ] && return 0
  pid=$(cat "$1/pid" 2>/dev/null)
  # No pid yet means the owner is between mkdir and writing it: still held.
  [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null
}

_lock_take() { mkdir "$1" 2>/dev/null && echo $$ > "$1/pid"; }

lock_acquire() { # lock-dir
  local lock=$1 breaker="$1.break"
  _lock_take "$lock" && return 0
  _lock_is_stale "$lock" || return 1

  # Several renders can find the same stale lock. Only the one holding the
  # breaker may remove it, and it checks again first: another breaker may
  # already have replaced it with a live lock.
  if ! mkdir "$breaker" 2>/dev/null; then
    # A breaker that died mid-break would block everyone; clear it once old.
    [ "$(_age "$breaker")" -ge "$LOCK_MAX_AGE" ] && rmdir "$breaker" 2>/dev/null
    return 1
  fi
  local taken=1
  if _lock_is_stale "$lock"; then
    rm -rf "$lock"
    _lock_take "$lock" && taken=0
  fi
  rmdir "$breaker"
  return $taken
}

lock_release() { rm -rf "$1"; }
