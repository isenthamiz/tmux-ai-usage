# shellcheck shell=bash disable=SC2034  # sets globals read by the scripts that source it
# Plugin options, read with a single `tmux show-options -g` call per run.

_valid_providers() {
  local want=$1 have="" p
  for p in $want; do
    case " $have " in *" $p "*) continue ;; esac  # each provider once
    case $p in
      claude|codex|cursor) have="$have $p" ;;
    esac
  done
  have=${have# }
  if [ -n "$have" ]; then echo "$have"; else echo "claude codex cursor"; fi
}

# Four descending integers: minimum client width for full, step 1, 2 and 3.
valid_step_widths() { # value
  local n=0 prev="" w
  for w in $1; do
    case $w in ''|*[!0-9]*) return 1 ;; esac
    [ -n "$prev" ] && [ "$w" -ge "$prev" ] && return 1
    prev=$w; n=$((n + 1))
  done
  [ "$n" -eq 4 ]
}

valid_on_off() { # value
  case $1 in on|off) return 0 ;; esac
  return 1
}

valid_rotate_interval() { # value: whole seconds, at least 1
  case $1 in ''|*[!0-9]*) return 1 ;; esac
  [ "$1" -ge 1 ]
}

valid_step() { # value
  case $1 in auto|full|1|2|3|4) return 0 ;; esac
  return 1
}

# tmux gained the e|>=: comparison the step conditional needs in 3.2.
version_has_expr() { # tmux version, e.g. 3.5a, 3.1c, next-3.6
  local v=${1#next-} major minor
  v=${v%%[!0-9.]*}
  major=${v%%.*}
  minor=${v#*.}; minor=${minor%%.*}
  case $major in ''|*[!0-9]*) return 0 ;; esac
  case $minor in ''|*[!0-9]*) minor=0 ;; esac
  [ "$major" -gt 3 ] || { [ "$major" -eq 3 ] && [ "$minor" -ge 2 ]; }
}

_finalize_loaded_options() {
  local def_cache="${XDG_CACHE_HOME:-$HOME/.cache}/tmux-ai-usage"

  if [ "${WARN_AT:-60}" -ge "${CRIT_AT:-85}" ]; then
    WARN_AT=60
    CRIT_AT=85
  fi
  if [ "${STALE_AFTER:-900}" -lt "${REFRESH_INTERVAL:-60}" ]; then
    STALE_AFTER=900
  fi
  CACHE_DIR=${CACHE_DIR:-$def_cache}
}

load_options() {
  local line name value thm_green="" thm_yellow="" thm_red="" thm_text="" thm_dim=""
  local raw_providers="claude codex cursor"
  local ri=60
  SEPARATOR=' │ '
  CLAUDE_WINDOW=auto
  CODEX_WINDOW=auto
  CURSOR_WINDOW=auto
  STEP_WIDTHS='180 140 110 80'
  STEP=auto
  ROTATE=off
  ROTATE_INTERVAL=10
  STATUS_INTERVAL=15
  TMUX_HAS_EXPR=1

  while IFS= read -r line; do
    name=${line%% *}
    value=${line#* }
    value=${value#\"}
    value=${value%\"}
    case $name in
      @thm_green) thm_green=$value ;;
      @thm_yellow) thm_yellow=$value ;;
      @thm_red) thm_red=$value ;;
      @thm_subtext_0) thm_text=$value ;;
      @thm_overlay_0) thm_dim=$value ;;
      @ai_usage_providers) raw_providers=$value ;;
      @ai_usage_separator) SEPARATOR=$value ;;
      @ai_usage_claude_window) CLAUDE_WINDOW=${value:-auto} ;;
      @ai_usage_codex_window) CODEX_WINDOW=${value:-auto} ;;
      @ai_usage_cursor_window) CURSOR_WINDOW=${value:-auto} ;;
      @ai_usage_bar_width)
        case $value in ''|*[!0-9]*) ;;
        *) BAR_WIDTH=$value ;;
        esac ;;
      @ai_usage_bar_filled) BAR_FILLED=$value ;;
      @ai_usage_bar_empty) BAR_EMPTY=$value ;;
      @ai_usage_warn_at)
        case $value in ''|*[!0-9]*) ;;
        *) [ "$value" -le 100 ] && WARN_AT=$value ;;
        esac ;;
      @ai_usage_crit_at)
        case $value in ''|*[!0-9]*) ;;
        *) [ "$value" -le 100 ] && CRIT_AT=$value ;;
        esac ;;
      @ai_usage_ok_color) COLOR_OK=$value ;;
      @ai_usage_warn_color) COLOR_WARN=$value ;;
      @ai_usage_crit_color) COLOR_CRIT=$value ;;
      @ai_usage_text_color) COLOR_TEXT=$value ;;
      @ai_usage_dim_color) COLOR_DIM=$value ;;
      @ai_usage_claude_label) CLAUDE_LABEL=$value ;;
      @ai_usage_codex_label) CODEX_LABEL=$value ;;
      @ai_usage_cursor_label) CURSOR_LABEL=$value ;;
      @ai_usage_refresh_interval)
        case $value in ''|*[!0-9]*) ;;
        *) ri=$value; [ "$ri" -lt 60 ] && ri=60; REFRESH_INTERVAL=$ri ;;
        esac ;;
      @ai_usage_stale_after)
        case $value in ''|*[!0-9]*) ;;
        *) STALE_AFTER=$value ;;
        esac ;;
      @ai_usage_step_widths)
        valid_step_widths "$value" && STEP_WIDTHS=$value ;;
      status-interval)
        case $value in ''|*[!0-9]*) ;; *) STATUS_INTERVAL=$value ;; esac ;;
      @ai_usage_rotate)
        valid_on_off "$value" && ROTATE=$value ;;
      @ai_usage_rotate_interval)
        valid_rotate_interval "$value" && ROTATE_INTERVAL=$value ;;
      @ai_usage_step)
        valid_step "$value" && STEP=$value ;;
      @ai_usage_tmux_version)
        version_has_expr "$value" || TMUX_HAS_EXPR=0 ;;
      @ai_usage_cache_dir)
        [ -n "$value" ] && CACHE_DIR=$value ;;
    esac
  done <<<"$(tmux show-options -g 2>/dev/null)"

  PROVIDERS=$(_valid_providers "$raw_providers")

  COLOR_OK=${COLOR_OK:-${thm_green:-#a6e3a1}}
  COLOR_WARN=${COLOR_WARN:-${thm_yellow:-#f9e2af}}
  COLOR_CRIT=${COLOR_CRIT:-${thm_red:-#f38ba8}}
  COLOR_TEXT=${COLOR_TEXT:-${thm_text:-#bac2de}}
  COLOR_DIM=${COLOR_DIM:-${thm_dim:-#6c7086}}
  WARN_AT=${WARN_AT:-60}
  CRIT_AT=${CRIT_AT:-85}
  BAR_WIDTH=${BAR_WIDTH:-5}
  BAR_FILLED=${BAR_FILLED:-▰}
  BAR_EMPTY=${BAR_EMPTY:-▱}
  REFRESH_INTERVAL=${REFRESH_INTERVAL:-60}
  STALE_AFTER=${STALE_AFTER:-900}
  CLAUDE_LABEL=${CLAUDE_LABEL:-cl}
  CODEX_LABEL=${CODEX_LABEL:-cx}
  CURSOR_LABEL=${CURSOR_LABEL:-cu}

  _finalize_loaded_options
}

window_pin_for() {
  case $1 in
    claude) echo "$CLAUDE_WINDOW" ;;
    codex) echo "$CODEX_WINDOW" ;;
    cursor) echo "$CURSOR_WINDOW" ;;
    *) echo auto ;;
  esac
}

provider_label_for() {
  case $1 in
    claude) echo "$CLAUDE_LABEL" ;;
    codex) echo "$CODEX_LABEL" ;;
    cursor) echo "$CURSOR_LABEL" ;;
    *) echo "$1" ;;
  esac
}

snapshot_json_for() {
  local p=$1 path
  path=$(snapshot_path "$p")
  if [ -f "$path" ]; then cat "$path"; else printf 'null'; fi
}