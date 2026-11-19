# shellcheck shell=bash disable=SC2034  # sets globals read by the scripts that source it
# Plugin options, read with a single `tmux show-options -g` call per run.
# Sets COLOR_OK, COLOR_WARN, COLOR_CRIT, COLOR_TEXT, COLOR_DIM, WARN_AT, CRIT_AT,
# BAR_WIDTH, BAR_FILLED, BAR_EMPTY, REFRESH_INTERVAL, STALE_AFTER, CLAUDE_LABEL and CODEX_LABEL.

load_options() {
  local line name value thm_green="" thm_yellow="" thm_red="" thm_text="" thm_dim=""
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
    esac
  done <<<"$(tmux show-options -g 2>/dev/null)"

  COLOR_OK=${thm_green:-#a6e3a1}
  COLOR_WARN=${thm_yellow:-#f9e2af}
  COLOR_CRIT=${thm_red:-#f38ba8}
  COLOR_TEXT=${thm_text:-#bac2de}
  COLOR_DIM=${thm_dim:-#6c7086}
  WARN_AT=60
  CRIT_AT=85
  BAR_WIDTH=5
  BAR_FILLED="▰"
  BAR_EMPTY="▱"
  REFRESH_INTERVAL=60
  STALE_AFTER=900
  CLAUDE_LABEL="cl"
  CODEX_LABEL="cx"
}
