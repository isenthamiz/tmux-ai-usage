# shellcheck shell=bash
# Validate @ai_usage_* options once at plugin load; reset invalid values and notify.
# shellcheck source=scripts/lib/options.sh
. "$(dirname "${BASH_SOURCE[0]}")/options.sh"

_is_uint() {
  case $1 in ''|*[!0-9]*) return 1 ;;
  esac
  return 0
}

_default_cache_dir() {
  printf '%s' "${XDG_CACHE_HOME:-$HOME/.cache}/tmux-ai-usage"
}

_crit_colour_at_load() {
  local v
  v=$(tmux show-options -gqv @ai_usage_crit_color 2>/dev/null) && [ -n "$v" ] && { printf '%s' "$v"; return 0; }
  v=$(tmux show-options -gqv @thm_red 2>/dev/null) && [ -n "$v" ] && { printf '%s' "$v"; return 0; }
  printf '%s' '#f38ba8'
}

_option_report_invalid() {
  local name=$1 bad=$2 default=$3
  tmux display-message "tmux-ai-usage: $name invalid ($bad), using default"
  tmux set-option -gq "$name" "$default"
}

_valid_providers_strict() {
  local want=$1 have="" p
  for p in $want; do
    case $p in
      claude|codex|cursor) have="$have $p" ;;
    esac
  done
  have=${have# }
  printf '%s' "$have"
}

validate_ai_usage_options() {
  local value fixed unknown p default_ri ri def_cache warn_set=0 crit_set=0
  def_cache=$(_default_cache_dir)

  value=$(tmux show-options -gqv @ai_usage_providers 2>/dev/null) || value=""
  if [ -n "$value" ]; then
    unknown=""
    for p in $value; do
      case $p in
        claude|codex|cursor) ;;
        *) unknown=${unknown:+$unknown, }"$p" ;;
      esac
    done
    fixed=$(_valid_providers_strict "$value")
    if [ -n "$unknown" ]; then
      [ -z "$fixed" ] && fixed='claude codex cursor'
      _option_report_invalid '@ai_usage_providers' "$unknown" "$fixed"
    elif [ -z "$fixed" ]; then
      _option_report_invalid '@ai_usage_providers' "$value" 'claude codex cursor'
    fi
  fi

  value=$(tmux show-options -gqv @ai_usage_bar_width 2>/dev/null) || value=""
  if [ -n "$value" ] && ! _is_uint "$value"; then
    _option_report_invalid '@ai_usage_bar_width' "$value" '5'
  fi

  value=$(tmux show-options -gqv @ai_usage_warn_at 2>/dev/null) || value=""
  local crit
  crit=$(tmux show-options -gqv @ai_usage_crit_at 2>/dev/null) || crit=""
  [ -n "$value" ] && warn_set=1
  [ -n "$crit" ] && crit_set=1
  if [ "$warn_set" -eq 1 ] && { ! _is_uint "$value" || [ "$value" -gt 100 ]; }; then
    _option_report_invalid '@ai_usage_warn_at' "$value" '60'
    value=60
    warn_set=1
  fi
  if [ "$crit_set" -eq 1 ] && { ! _is_uint "$crit" || [ "$crit" -gt 100 ]; }; then
    _option_report_invalid '@ai_usage_crit_at' "$crit" '85'
    crit=85
    crit_set=1
  fi
  value=${value:-60}
  crit=${crit:-85}
  if [ "$warn_set" -eq 1 ] && [ "$crit_set" -eq 1 ] && [ "$value" -ge "$crit" ]; then
    _option_report_invalid '@ai_usage_warn_at' ">= crit_at ($crit)" '60'
    _option_report_invalid '@ai_usage_crit_at' "<= warn_at ($value)" '85'
    tmux set-option -gq @ai_usage_warn_at 60
    tmux set-option -gq @ai_usage_crit_at 85
  fi

  value=$(tmux show-options -gqv @ai_usage_refresh_interval 2>/dev/null) || value=""
  if [ -n "$value" ]; then
    if ! _is_uint "$value"; then
      _option_report_invalid '@ai_usage_refresh_interval' "$value" '60'
    else
      default_ri=$value
      [ "$default_ri" -lt 60 ] && default_ri=60
      if [ "$default_ri" != "$value" ]; then
        tmux set-option -gq @ai_usage_refresh_interval "$default_ri"
      fi
    fi
  fi

  value=$(tmux show-options -gqv @ai_usage_stale_after 2>/dev/null) || value=""
  if [ -n "$value" ]; then
    ri=$(tmux show-options -gqv @ai_usage_refresh_interval 2>/dev/null) || ri=60
    _is_uint "$ri" || ri=60
    [ "$ri" -lt 60 ] && ri=60
    if ! _is_uint "$value"; then
      _option_report_invalid '@ai_usage_stale_after' "$value" '900'
    elif [ "$value" -lt "$ri" ]; then
      _option_report_invalid '@ai_usage_stale_after' "$value (< refresh $ri)" '900'
    fi
  fi

  value=$(tmux show-options -gqv @ai_usage_step_widths 2>/dev/null) || value=""
  if [ -n "$value" ] && ! valid_step_widths "$value"; then
    _option_report_invalid '@ai_usage_step_widths' "$value" '180 140 110 80'
  fi

  value=$(tmux show-options -gqv @ai_usage_step 2>/dev/null) || value=""
  if [ -n "$value" ] && ! valid_step "$value"; then
    _option_report_invalid '@ai_usage_step' "$value" 'auto'
  fi

  value=$(tmux show-options -gqv @ai_usage_rotate 2>/dev/null) || value=""
  if [ -n "$value" ] && ! valid_on_off "$value"; then
    _option_report_invalid '@ai_usage_rotate' "$value" 'off'
  fi

  value=$(tmux show-options -gqv @ai_usage_rotate_interval 2>/dev/null) || value=""
  if [ -n "$value" ] && ! valid_rotate_interval "$value"; then
    _option_report_invalid '@ai_usage_rotate_interval' "$value" '10'
  fi

  # The renderer reads this instead of running tmux -V on every redraw.
  value=$(tmux -V 2>/dev/null) || value=""
  tmux set-option -gq @ai_usage_tmux_version "${value#tmux }"

  value=$(tmux show-options -gqv @ai_usage_cache_dir 2>/dev/null) || value=""
  if [ -n "$value" ]; then
    mkdir -p "$value" && chmod 700 "$value" 2>/dev/null || true
  else
    mkdir -p "$def_cache" && chmod 700 "$def_cache" 2>/dev/null || true
  fi
}