#!/bin/bash
# Reads cached usage snapshots only; never fetches. Works from a shell or tmux run-shell.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/options.sh
. "$DIR/lib/options.sh"
# shellcheck source=scripts/lib/snapshot.sh
. "$DIR/lib/snapshot.sh"
# shellcheck source=scripts/lib/deps.sh
. "$DIR/lib/deps.sh"
# shellcheck source=scripts/lib/format.sh
. "$DIR/lib/format.sh"
# shellcheck source=scripts/lib/providers.sh
. "$DIR/lib/providers.sh"

now=${AI_USAGE_NOW:-$(date +%s)}
load_options

_print_ok_age() { # ok_at epoch
  local ok_at=$1
  if [ "$ok_at" -gt 0 ]; then
    countdown $((now - ok_at))
  else
    echo "-"
  fi
}

_print_provider_snapshot() {
  local p=$1 path st ok_at ra err ok_age
  path=$(snapshot_path "$p")
  if [ ! -f "$path" ]; then
    printf 'provider=%s\tstatus=pending\tok_age=-\tretry_at=-\terror=-\n' "$p"
    return
  fi
  st=$(jq -r '.status // "error"' "$path")
  ok_at=$(jq -r '.ok_at // 0' "$path")
  ra=$(jq -r 'if (.retry_at // 0) > 0 then (.retry_at | tostring) else "-" end' "$path")
  err=$(jq -r 'if .error == null or .error == "" then "-" else .error end' "$path")
  ok_age=$(_print_ok_age "$ok_at")
  printf 'provider=%s\tstatus=%s\tok_age=%s\tretry_at=%s\terror=%s\n' \
    "$p" "$st" "$ok_age" "$ra" "$err"
}

if command -v jq >/dev/null 2>&1; then
  jq_path=$(command -v jq)
  printf 'deps jq=ok path=%s\n' "$jq_path"
else
  printf 'deps jq=missing\n'
  exit 1
fi

for p in $(list_providers "$DIR"); do
  _print_provider_snapshot "$p"
  printf 'provider=%s\tdeps %s\n' "$p" "$(provider_deps_line "$p")"
done

printf 'options providers=%s\n' "$PROVIDERS"
printf 'options cache_dir=%s\n' "$(cache_dir)"
printf 'options refresh_interval=%s\n' "$REFRESH_INTERVAL"
printf 'options stale_after=%s\n' "$STALE_AFTER"
printf 'options bar_width=%s warn_at=%s crit_at=%s\n' "$BAR_WIDTH" "$WARN_AT" "$CRIT_AT"
printf 'options claude_label=%s codex_label=%s cursor_label=%s\n' \
  "$CLAUDE_LABEL" "$CODEX_LABEL" "$CURSOR_LABEL"
printf 'options claude_window=%s codex_window=%s cursor_window=%s\n' \
  "$CLAUDE_WINDOW" "$CODEX_WINDOW" "$CURSOR_WINDOW"
printf "options separator='%s'\n" "$SEPARATOR"
printf "options step=%s step_widths='%s'\n" "$STEP" "$STEP_WIDTHS"
focus=$(tmux show-options -gqv @ai_usage_focus 2>/dev/null) || focus=""
printf 'options rotate=%s rotate_interval=%s focus=%s\n' "$ROTATE" "$ROTATE_INTERVAL" "${focus:-off}"
