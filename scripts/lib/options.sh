# shellcheck shell=bash disable=SC2034  # sets globals read by the scripts that source it
# Plugin options, read with a single `tmux show-options -g` call per run.

_valid_providers() {
  local want=$1 have="" p
  for p in $want; do
    case $p in
      claude|codex|cursor) have="$have $p" ;;
    esac
  done
  have=${have# }
  if [ -n "$have" ]; then echo "$have"; else echo "claude codex cursor"; fi
}

load_options() {
  local line name value thm_green="" thm_yellow="" thm_red="" thm_text="" thm_dim=""
  local raw_providers="claude codex cursor"
  SEPARATOR=' │ '
  CLAUDE_WINDOW=auto
  CODEX_WINDOW=auto
  CURSOR_WINDOW=auto
  CURSOR_LABEL=cu

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
      @ai_usage_claude_window) CLAUDE_WINDOW=$value ;;
      @ai_usage_codex_window) CODEX_WINDOW=$value ;;
      @ai_usage_cursor_window) CURSOR_WINDOW=$value ;;
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