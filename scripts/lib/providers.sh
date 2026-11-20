# shellcheck shell=bash
# Provider discovery from scripts/providers/<name>/ (acquire + normalize).
# shellcheck source=scripts/lib/profile.sh
. "$(dirname "${BASH_SOURCE[0]}")/profile.sh"

list_providers() { # plugin-scripts-dir
  local root=$1 d base
  for d in "$root/providers"/*/; do
    [ -d "$d" ] || continue
    [ -f "${d}acquire.sh" ] && [ -f "${d}normalize.jq" ] || continue
    base=$(basename "$d")
    echo "$base"
  done | LC_ALL=C sort
}

provider_deps_line() { # provider [profile]
  local p=$1 prof=${2:-${PROFILE:-personal}} miss path
  case $prof in
    ebay)
      case $p in
        claude)
          if path=$(find_claude_binary); then
            echo "claude=$(basename "$path") path=$path"
          else
            echo "claude=missing"
          fi
          echo "ebay_capture=$(ebay_capture_dir 2>/dev/null || echo '?')"
          ;;
        codex)
          if path=$(find_codex_binary); then
            echo "codex=$(basename "$path") path=$path"
          else
            echo "codex=missing (optional until CLI capture)"
          fi
          echo "ebay_capture=$(ebay_capture_dir 2>/dev/null || echo '?')"
          ;;
        cursor)
          if path=$(find_cursor_cli_binary); then
            echo "cursor_cli=$(basename "$path") path=$path"
          else
            echo "cursor_cli=missing (optional until CLI capture)"
          fi
          echo "ebay_capture=$(ebay_capture_dir 2>/dev/null || echo '?')"
          ;;
        *) echo "(no dependency checks)" ;;
      esac
      ;;
    *)
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
      ;;
  esac
}

ebay_capture_dir() {
  local base="${XDG_CACHE_HOME:-$HOME/.cache}/tmux-ai-usage"
  printf '%s' "${EBAY_USAGE_CAPTURE_DIR:-${AI_USAGE_EBAY_CAPTURE_DIR:-$base/ebay-capture}}"
}

provider_refresh_deps_ok() { # provider profile -> 0 ok; else prints missing_dep message
  local p=$1 prof=$2 miss path cap
  cap=$(ebay_capture_dir)
  case $prof in
    ebay)
      if [ ! -f "$cap/$p.json" ]; then
        echo "eBay capture $cap/$p.json missing"
        return 1
      fi
      return 0
      ;;
  esac
  case $p in
    codex)
      find_binary curl >/dev/null || { echo "curl not found"; return 1; }
      ;;
    claude)
      find_claude_binary >/dev/null || { echo "claude CLI not found"; return 1; }
      ;;
    cursor)
      miss=$(cursor_missing_dep) && { echo "$miss not found"; return 1; }
      ;;
  esac
  return 0
}