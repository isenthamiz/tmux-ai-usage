# shellcheck shell=bash
# Focus: which provider's AI agent runs in the active pane. tmux passes the
# pane's command and tty to render.sh; see research/agent-detection.md.

# Provider named by one process's args, or nothing.
_provider_in_args() { # args line
  local word base
  for word in $1; do
    base=${word##*/}
    case $word in
      *cursor-agent*) echo cursor; return 0 ;;
    esac
    case $base in
      claude|claude.exe) echo claude; return 0 ;;
      codex|codex.js) echo codex; return 0 ;;
    esac
    case $word in
      */claude-code/*) echo claude; return 0 ;;
      */@openai/codex/*) echo codex; return 0 ;;
    esac
  done
  return 1
}

# Prints claude, codex or cursor, or nothing when the pane runs no agent.
# Only `node` or a shell costs a fork: one `ps -t <tty> -o args=`.
focus_provider() { # pane_current_command pane_tty
  local cmd=$1 tty=$2 line found
  case $cmd in
    codex) echo codex; return 0 ;;
    claude|claude.exe) echo claude; return 0 ;;
    node|sh|bash|zsh|fish|dash|ksh|tcsh|csh) ;;
    *)
      # Claude's native installer runs as its version, e.g. 2.1.328.
      case $cmd in
        *[!0-9.]*|.*|*.|*..*) return 0 ;;
      esac
      case $cmd in
        *.*.*) echo claude ;;
      esac
      return 0 ;;
  esac
  [ -n "$tty" ] || return 0
  while IFS= read -r line; do
    found=$(_provider_in_args "$line") && { echo "$found"; return 0; }
  done < <(ps -t "$tty" -o args= 2>/dev/null)
  return 0
}
