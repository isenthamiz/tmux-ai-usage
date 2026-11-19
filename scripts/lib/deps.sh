# shellcheck shell=bash
# Required commands for each provider. PATH first, then known install locations.

_find_on_path() { command -v "$1" 2>/dev/null; }

find_binary() { # name [extra-dir...]
  local name=$1 dir
  shift
  [ -n "${AI_USAGE_TEST_NO_CURL:-}" ] && [ "$name" = curl ] && return 1
  [ -n "${AI_USAGE_TEST_NO_CLAUDE:-}" ] && [ "$name" = claude ] && return 1
  [ -n "${AI_USAGE_TEST_NO_SQLITE3:-}" ] && [ "$name" = sqlite3 ] && return 1
  [ -n "${AI_USAGE_TEST_NO_SECURITY:-}" ] && [ "$name" = security ] && return 1
  path=$(_find_on_path "$name") && { echo "$path"; return 0; }
  for dir in "$@"; do
  [ -x "$dir/$name" ] && { echo "$dir/$name"; return 0; }
  done
  return 1
}

find_claude_binary() {
  find_binary claude "$HOME/.local/bin" "$HOME/.claude/local"
}

openssl_has_kdf() { # path-to-openssl
  "$1" kdf -help >/dev/null 2>&1
}

find_openssl() {
  [ -n "${AI_USAGE_TEST_NO_OPENSSL:-}" ] && return 1
  local p
  p=$(find_binary openssl \
    /opt/homebrew/opt/openssl@3/bin \
    /usr/local/opt/openssl@3/bin) || return 1
  openssl_has_kdf "$p" || return 1
  echo "$p"
}

cursor_missing_dep() { # prints first missing dependency name
  find_binary curl >/dev/null || { echo curl; return 0; }
  find_binary sqlite3 >/dev/null || { echo sqlite3; return 0; }
  find_binary security >/dev/null || { echo security; return 0; }
  find_openssl >/dev/null || { echo openssl; return 0; }
  return 1
}