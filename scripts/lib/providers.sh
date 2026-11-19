# shellcheck shell=bash
# Provider discovery from scripts/providers/<name>/ (acquire + normalize).

list_providers() { # plugin-scripts-dir
  local root=$1 d base
  for d in "$root/providers"/*/; do
    [ -d "$d" ] || continue
    [ -f "${d}acquire.sh" ] && [ -f "${d}normalize.jq" ] || continue
    base=$(basename "$d")
    echo "$base"
  done | LC_ALL=C sort
}

provider_deps_line() { # provider
  local p=$1 miss path
  case $p in
    claude)
      if path=$(find_claude_binary); then
        echo "claude=$(basename "$path") path=$path"
      else
        echo "claude=missing"
      fi
      ;;
    codex)
      if path=$(find_binary curl); then
        echo "curl=$(basename "$path") path=$path"
      else
        echo "curl=missing"
      fi
      ;;
    cursor)
      if miss=$(cursor_missing_dep); then
        echo "$miss=missing"
      else
        echo "curl sqlite3 security openssl=ok"
      fi
      ;;
    *)
      echo "(no dependency checks)"
      ;;
  esac
}