# shellcheck shell=bash
# Focus: which provider's AI agent runs in the active pane. tmux passes the
# pane's command and tty to render.sh; see research/agent-detection.md.

# The provider a script belongs to, from its install path, or nothing.
_provider_for_script() { # path
  case $1 in
    */cursor-agent/*) echo cursor ;;
    */claude-code/*) echo claude ;;
    */@openai/codex/*|codex.js|*/codex.js) echo codex ;;
    *) return 1 ;;
  esac
}

# The provider a program is, from its name or install path, or nothing.
_provider_for_program() { # name-or-path
  case ${1##*/} in
    claude|claude.exe) echo claude ;;
    codex) echo codex ;;
    cursor-agent) echo cursor ;;
    *) _provider_for_script "$1" ;;
  esac
}

# Claude's native installer runs as its version, e.g. 2.1.328.
_is_version_string() { # name
  local rest=$1 part n=0
  while :; do
    part=${rest%%.*}
    case $part in ''|*[!0-9]*) return 1 ;; esac
    n=$((n + 1))
    [ "$rest" = "$part" ] && break
    rest=${rest#*.}
  done
  [ "$n" -eq 3 ]
}

# The provider of one process: its program, or the script a runtime such as
# node runs (the first argument that isn't an option). `read -a` splits
# without glob expansion.
_provider_for_process() { # args
  local -a words
  local word
  read -r -a words <<<"$1"
  [ "${#words[@]}" -gt 0 ] || return 1
  _provider_for_program "${words[0]}" && return 0
  for word in "${words[@]:1}"; do
    case $word in -*) continue ;; esac
    _provider_for_script "$word"
    return
  done
  return 1
}

# Prints claude, codex or cursor, or nothing when the pane runs no agent.
# Only `node` or a shell costs a fork: one `ps -t <tty>`, of which only the
# foreground process group counts, the group tmux itself reads.
focus_provider() { # pane_current_command pane_tty
  local cmd=$1 tty=$2 pgid tpgid args
  case $cmd in
    node|sh|bash|zsh|fish|dash|ksh|tcsh|csh) ;;
    *)
      _provider_for_program "$cmd" ||
        { _is_version_string "$cmd" && echo claude; }
      return 0 ;;
  esac
  [ -n "$tty" ] || return 0
  while read -r pgid tpgid args; do
    [ "$pgid" = "$tpgid" ] || continue
    _provider_for_process "$args" && return 0
  done < <(ps -t "$tty" -o pgid=,tpgid=,args= 2>/dev/null)
  return 0
}
