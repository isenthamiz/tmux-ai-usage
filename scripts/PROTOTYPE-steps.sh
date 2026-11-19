#!/bin/bash
# PROTOTYPE — throwaway. Answers "How should each step look, and at which widths?" (issue #38).
# Not production code: no tests, no validation. Lives only on the prototype/steps branch.
#
#   PROTOTYPE-steps.sh preview   print every step, and the step picked at a range of widths
#   PROTOTYPE-steps.sh live      this session only: swap the plugin piece in status-right for a
#                                width-aware one, then resize the terminal and watch
#   PROTOTYPE-steps.sh off       restore this session's status-right
#   PROTOTYPE-steps.sh emit      (used by live) print the tmux format
#
# Knobs (env):
#   T="180 140 110 80"   minimum client width for full, step 1, step 2, step 3 (below the last: step 4)
#   SEP=" │ "            separator at full and step 1
#   SEP_NARROW=" "       separator at steps 2-4
#   WIDTH=5              progress bar cells
#   CRIT=85 WARN=60
export LC_ALL=en_US.UTF-8
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
CACHE=${CACHE:-$HOME/.cache/tmux-ai-usage}
T=${T:-180 140 110 80}
SEP=${SEP:- │ }
SEP_NARROW=${SEP_NARROW:- }
WIDTH=${WIDTH:-5}
CRIT=${CRIT:-85}
WARN=${WARN:-60}
NOW=$(date +%s)

opt() { local v; v=$(tmux show -gqv "$1" 2>/dev/null); printf '%s' "${v:-$2}"; }
C_OK=$(opt @thm_green '#a6e3a1'); C_WARN=$(opt @thm_yellow '#f9e2af'); C_CRIT=$(opt @thm_red '#f38ba8')
C_TEXT=$(opt @thm_subtext_0 '#bac2de'); C_DIM=$(opt @thm_overlay_0 '#6c7086')

countdown() { # seconds
  local s=$1 d h m
  [ "$s" -lt 0 ] && s=0
  d=$((s / 86400)); h=$((s % 86400 / 3600)); m=$((s % 3600 / 60))
  if [ $d -gt 0 ]; then printf '%sd' $d; [ $h -gt 0 ] && printf '%sh' $h
  elif [ $h -gt 0 ]; then printf '%sh' $h; [ $m -gt 0 ] && printf '%sm' $m
  else printf '%sm' $m; fi
}

# rows: label wl pct countdown  (most-used window per provider)
rows() {
  local p lbl
  for p in claude codex cursor; do
    case $p in claude) lbl=cl ;; codex) lbl=cx ;; cursor) lbl=cu ;; esac
    [ -r "$CACHE/$p.json" ] || continue
    jq -r --arg l "$lbl" --argjson now "$NOW" \
      '.windows | max_by(.used_pct) | "\($l) \(.label) \(.used_pct) \(.resets_at - $now)"' "$CACHE/$p.json"
  done
}

# piece STEP MODE(tmux|ansi) label wl pct secs
piece() {
  local step=$1 mode=$2 l=$3 wl=$4 pct=$5 secs=$6 lvl n i bar="" cd red=0
  if [ "$pct" -ge "$CRIT" ]; then lvl=$C_CRIT; red=1; elif [ "$pct" -ge "$WARN" ]; then lvl=$C_WARN; else lvl=$C_OK; fi
  n=$(( (pct * WIDTH + 50) / 100 ))
  for ((i = 0; i < WIDTH; i++)); do if [ $i -lt $n ]; then bar="${bar}▰"; else bar="${bar}▱"; fi; done
  cd=$(countdown "$secs")
  c() { if [ "$mode" = tmux ]; then printf '#[fg=%s]' "$1"; else printf '\033[38;2;%d;%d;%dm' "0x${1:1:2}" "0x${1:3:2}" "0x${1:5:2}"; fi; }
  case $step in
    0) printf '%s%s %s%s %s%s %s%s' "$(c "$C_TEXT")" "$l" "$(c "$C_DIM")" "$wl" "$(c "$lvl")" "$bar" "$(c "$C_DIM")" "$cd" ;;
    1) printf '%s%s %s%s %s%s' "$(c "$C_TEXT")" "$l" "$(c "$lvl")" "$bar" "$(c "$C_DIM")" "$cd" ;;
    2) printf '%s%s %s%s' "$(c "$C_TEXT")" "$l" "$(c "$lvl")" "$bar"; [ $red = 1 ] && printf ' %s%s' "$(c "$C_DIM")" "$cd" ;;
    3) printf '%s%s %s%s%%' "$(c "$C_TEXT")" "$l" "$(c "$lvl")" "$pct"; [ $red = 1 ] && printf ' %s%s' "$(c "$C_DIM")" "$cd" ;;
    4) printf '%s%s' "$(c "$lvl")" "$l" ;;
  esac
}

line() { # step mode
  local step=$1 mode=$2 sep out="" first=1 l wl pct secs
  if [ "$step" -ge 2 ]; then sep=$SEP_NARROW; else sep=$SEP; fi
  while read -r l wl pct secs; do
    if [ $first = 1 ]; then first=0; else
      if [ "$mode" = tmux ]; then out="$out#[fg=$C_DIM]$sep"; else out="$out$(printf '\033[38;2;%d;%d;%dm' "0x${C_DIM:1:2}" "0x${C_DIM:3:2}" "0x${C_DIM:5:2}")$sep"; fi
    fi
    out="$out$(piece "$step" "$mode" "$l" "$wl" "$pct" "$secs")"
  done <<<"$(rows)"
  if [ "$mode" = tmux ]; then printf '%s#[fg=default]' "$out"; else printf '%s\033[0m' "$out"; fi
}

plain_len() { # strip ANSI, count chars
  printf '%s' "$1" | perl -CS -ne 's/\e\[[0-9;]*m//g; print length($_)'
}

step_for() { # width
  local w=$1 i=0 t
  for t in $T; do [ "$w" -ge "$t" ] && { echo $i; return; }; i=$((i + 1)); done
  echo 4
}

case ${1:-preview} in
  preview)
    names=(full "step 1" "step 2" "step 3" "step 4")
    echo "Every step (real cached usage; thresholds T=\"$T\"):"
    for s in 0 1 2 3 4; do
      l=$(line $s ansi)
      printf '  %-7s %3s cols  %s\n' "${names[$s]}" "$(plain_len "$l")" "$l"
    done
    echo
    echo "Step picked at each terminal width:"
    for w in 232 200 180 160 140 120 110 100 90 80 70; do
      s=$(step_for $w); printf '  %3s cols → %-7s %s\n' $w "${names[$s]}" "$(line "$s" ansi)"
    done
    ;;
  emit)
    set -- $T
    printf '#{?#{e|>=:#{client_width},%s},%s,#{?#{e|>=:#{client_width},%s},%s,#{?#{e|>=:#{client_width},%s},%s,#{?#{e|>=:#{client_width},%s},%s,%s}}}}' \
      "$1" "$(line 0 tmux)" "$2" "$(line 1 tmux)" "$3" "$(line 2 tmux)" "$4" "$(line 3 tmux)" "$(line 4 tmux)"
    ;;
  live)
    s=$(tmux display -p '#{session_name}')
    cur=$(tmux show -gv status-right)
    env_prefix="T='$T' SEP='$SEP' SEP_NARROW='$SEP_NARROW' WIDTH=$WIDTH"
    new=$(printf '%s' "$cur" | sed -E "s|#\\('[^']*/render\\.sh' all\\)|#($env_prefix '$SELF' emit)|")
    if [ "$new" = "$cur" ]; then echo "no #(…render.sh' all) in status-right; nothing changed" >&2; exit 1; fi
    tmux set -t "$s" status-right "$new"
    echo "Live in session '$s' (T=\"$T\"). Resize the terminal to see steps change. Undo: $0 off"
    ;;
  off)
    s=$(tmux display -p '#{session_name}')
    tmux set -u -t "$s" status-right && echo "Restored session '$s' status-right."
    ;;
esac
