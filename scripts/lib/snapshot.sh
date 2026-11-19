# shellcheck shell=bash
# Where usage snapshots live.

cache_dir() {
  if [ -n "${CACHE_DIR:-}" ]; then
    printf '%s' "$CACHE_DIR"
  else
    printf '%s' "${XDG_CACHE_HOME:-$HOME/.cache}/tmux-ai-usage"
  fi
}
snapshot_path() { echo "$(cache_dir)/$1.json"; }
