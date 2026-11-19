# shellcheck shell=bash
# Required commands for each provider. PATH first, then known install locations.

_find_on_path() { command -v "$1" 2>/dev/null; }

find_binary() { # name [extra-dir...]
  local name=$1 dir
  shift
  [ -n "${AI_USAGE_TEST_NO_CURL:-}" ] && [ "$name" = curl ] && return 1
  path=$(_find_on_path "$name") && { echo "$path"; return 0; }
  for dir in "$@"; do
  [ -x "$dir/$name" ] && { echo "$dir/$name"; return 0; }
  done
  return 1
}

codex_dependencies() {
  echo curl
}