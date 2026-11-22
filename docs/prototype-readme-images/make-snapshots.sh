#!/bin/bash
# PROTOTYPE: write hand-made usage snapshots for README captures. Usage: make-snapshots.sh <cache_dir> <now>
set -e; c=$1; n=$2; mkdir -p "$c"; chmod 700 "$c"
w(){ printf '%s\n' "$2" > "$c/$1.json"; }
w claude "{\"provider\":\"claude\",\"status\":\"ok\",\"fetched_at\":9999999999,\"ok_at\":$n,\"error\":null,\"windows\":[{\"label\":\"5h\",\"used_pct\":30,\"resets_at\":$((n+7980))},{\"label\":\"wk\",\"used_pct\":71,\"resets_at\":$((n+274000))}]}"
w codex  "{\"provider\":\"codex\",\"status\":\"ok\",\"fetched_at\":9999999999,\"ok_at\":$n,\"error\":null,\"windows\":[{\"label\":\"5h\",\"used_pct\":42,\"resets_at\":$((n+2820))},{\"label\":\"wk\",\"used_pct\":20,\"resets_at\":$((n+400000))}]}"
w cursor "{\"provider\":\"cursor\",\"status\":\"ok\",\"fetched_at\":9999999999,\"ok_at\":$n,\"error\":null,\"windows\":[{\"label\":\"wk\",\"used_pct\":23,\"resets_at\":$((n+353000))}]}"
