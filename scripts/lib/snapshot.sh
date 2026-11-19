# shellcheck shell=bash
# Where usage snapshots live.

cache_dir() { echo "${XDG_CACHE_HOME:-$HOME/.cache}/tmux-ai-usage"; }
snapshot_path() { echo "$(cache_dir)/$1.json"; }
