#!/bin/bash
# PROTOTYPE — throwaway. Answers "What should the usage bars look like?" (issue #6).
# Four structurally different status-line renderings of FAKE usage snapshots, shown
# inside your real status-right so they're judged next to cpu/mem/battery.
#
#   prototype/usage-bars.sh apply            # prepend to status-right, bind prefix+F9 / prefix+F10
#   prototype/usage-bars.sh next|prev        # cycle variant (same as prefix+F10 / prefix+F9)
#   prototype/usage-bars.sh scenario NAME    # typical | hot | legacy-cursor
#   prototype/usage-bars.sh restore          # put status-right back exactly as it was
#   prototype/usage-bars.sh preview          # print every variant x scenario in this terminal
#
# bash 3.2 compatible (macOS /bin/bash).

SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
VARIANTS="A B C D"

variant_name() {
  case $1 in
    A) echo "tightest window per provider (▰▱)" ;;
    B) echo "every window, full detail (█ eighths)" ;;
    C) echo "glyph strip: one vertical cell per window" ;;
    D) echo "quiet until it matters (≥75%)" ;;
  esac
}

# --- fake usage snapshots: provider|window label|used_pct|seconds until reset ---------
scenario_data() {
  case $1 in
    hot) cat <<'EOF'
claude|5h|93|1500
claude|wk|88|190000
claude|wk-opus|40|190000
codex|5h|100|1200
codex|wk|62|300000
cursor|wk|97|86400
EOF
    ;;
    legacy-cursor) cat <<'EOF'
claude|5h|42|7980
claude|wk|67|274000
claude|wk-opus|12|274000
codex|5h|81|2820
codex|wk|35|440000
cursor|auto-mo|44|1209600
cursor|api-mo|71|1209600
EOF
    ;;
    *) cat <<'EOF'
claude|5h|42|7980
claude|wk|67|274000
claude|wk-opus|12|274000
codex|5h|81|2820
codex|wk|35|440000
cursor|wk|58|352800
EOF
    ;;
  esac
}

# --- helpers ---------------------------------------------------------------------------
opt() { local v; v=$(tmux show -gqv "$1" 2>/dev/null); echo "${v:-$2}"; }
GREEN=$(opt @thm_green '#a6e3a1'); YELLOW=$(opt @thm_yellow '#f9e2af'); RED=$(opt @thm_red '#f38ba8')
DIM=$(opt @thm_overlay_0 '#6c7086'); TEXT=$(opt @thm_subtext_0 '#bac2de')

colour() { if [ "$1" -ge 85 ]; then echo "$RED"; elif [ "$1" -ge 60 ]; then echo "$YELLOW"; else echo "$GREEN"; fi; }
fg() { printf '#[fg=%s]' "$1"; }

countdown() { # 7980 -> 2h13m, 274000 -> 3d4h, 2820 -> 47m
  local s=$1 d h m
  d=$((s / 86400)); h=$((s % 86400 / 3600)); m=$((s % 3600 / 60))
  if [ $d -gt 0 ]; then echo "${d}d${h}h"; elif [ $h -gt 0 ]; then echo "${h}h${m}m"; else echo "${m}m"; fi
}

short() { case $1 in claude) echo cl ;; codex) echo cx ;; cursor) echo cu ;; esac; }
long()  { case $1 in claude) echo Claude ;; codex) echo Codex ;; cursor) echo Cursor ;; esac; }

bar_segments() { # pct width -> ▰▰▱▱▱
  local pct=$1 w=$2 n i out=""
  n=$(( (pct * w + 50) / 100 ))
  for ((i = 0; i < w; i++)); do if [ $i -lt $n ]; then out="$out▰"; else out="$out▱"; fi; done
  echo "$out"
}

bar_eighths() { # pct width -> ███▍░░░░
  local pct=$1 w=$2 eighths full rem i out=""
  local parts=(" " "▏" "▎" "▍" "▌" "▋" "▊" "▉")
  eighths=$(( pct * w * 8 / 100 )); full=$((eighths / 8)); rem=$((eighths % 8))
  for ((i = 0; i < full; i++)); do out="$out█"; done
  if [ $full -lt $w ]; then
    if [ $rem -gt 0 ]; then out="$out${parts[$rem]}"; else out="$out░"; fi
    for ((i = full + 1; i < w; i++)); do out="$out░"; done
  fi
  echo "$out"
}

vcell() { # pct -> ▁▂▃▄▅▆▇█
  local cells=("▁" "▂" "▃" "▄" "▅" "▆" "▇" "█") i
  if [ "$1" -ge 100 ]; then i=7; else i=$(( $1 * 8 / 100 )); fi
  echo "${cells[$i]}"
}

providers() { cut -d'|' -f1 | awk '!seen[$0]++'; }

# --- variants --------------------------------------------------------------------------
# A: one bar per provider, showing only its most-used window (label tells which).
render_A() {
  local data=$1 p line w pct secs out="" sep=""
  for p in $(echo "$data" | providers); do
    line=$(echo "$data" | awk -F'|' -v p="$p" '$1==p' | sort -t'|' -k3 -nr | head -1)
    IFS='|' read -r _ w pct secs <<<"$line"
    out="$out$sep$(fg "$TEXT")$(short "$p") $(fg "$DIM")$w $(fg "$(colour "$pct")")$(bar_segments "$pct" 5) $pct% $(fg "$DIM")$(countdown "$secs")"
    sep=" $(fg "$DIM")│ "
  done
  echo "$out"
}

# B: every window, labelled, with eighth-block bars and ↻ reset.
render_B() {
  local data=$1 p w pct secs out="" sep="" first
  for p in $(echo "$data" | providers); do
    out="$out$sep$(fg "$TEXT")$(long "$p")"
    while IFS='|' read -r _ w pct secs; do
      out="$out $(fg "$DIM")$w$(fg "$(colour "$pct")")$(bar_eighths "$pct" 6)$pct% $(fg "$DIM")↻$(countdown "$secs")"
    done <<<"$(echo "$data" | awk -F'|' -v p="$p" '$1==p')"
    sep=" $(fg "$DIM")│ "
  done
  echo "$out"
}

# C: ultra-dense — one coloured vertical cell per window, then the soonest reset of the
#    single most-used window anywhere.
render_C() {
  local data=$1 p w pct secs out top
  out="$(fg "$DIM")AI"
  for p in $(echo "$data" | providers); do
    out="$out $(fg "$TEXT")$(short "$p")"
    while IFS='|' read -r _ w pct secs; do
      out="$out$(fg "$(colour "$pct")")$(vcell "$pct")"
    done <<<"$(echo "$data" | awk -F'|' -v p="$p" '$1==p')"
  done
  top=$(echo "$data" | sort -t'|' -k3 -nr | head -1)
  IFS='|' read -r p w pct secs <<<"$top"
  echo "$out $(fg "$DIM")max $(fg "$(colour "$pct")")$(short "$p")·$w $pct% $(fg "$DIM")↻$(countdown "$secs")"
}

# D: nothing but a dim tick until any window reaches 75%; then only those windows.
render_D() {
  local data=$1 hot p w pct secs out="" sep=""
  hot=$(echo "$data" | awk -F'|' '$3>=75' | sort -t'|' -k3 -nr)
  if [ -z "$hot" ]; then echo "$(fg "$DIM")AI ✓"; return; fi
  while IFS='|' read -r p w pct secs; do
    out="$out$sep$(fg "$(colour "$pct")")$(long "$p") $w $pct% $(fg "$DIM")↻$(countdown "$secs")"
    sep="  "
  done <<<"$hot"
  echo "$(fg "$RED")▲ $out"
}

render() { # variant scenario
  local v=${1:-A} s=${2:-typical}
  printf '%s[%s] ' "$(fg "$DIM")" "$v"
  "render_$v" "$(scenario_data "$s")"
}

# --- tmux wiring -----------------------------------------------------------------------
cycle() { # +1 / -1
  local cur i=0 n idx arr
  cur=$(opt @proto_usage_variant A); arr=($VARIANTS); n=${#arr[@]}
  for ((i = 0; i < n; i++)); do [ "${arr[$i]}" = "$cur" ] && idx=$i; done
  idx=$(( (idx + $1 + n) % n ))
  set_variant "${arr[$idx]}"
}

set_variant() {
  tmux set -g @proto_usage_variant "$1"
  tmux refresh-client -S
  tmux display-message "usage-bars prototype: $1 — $(variant_name "$1")  (scenario: $(opt @proto_usage_scenario typical))"
}

case $1 in
  render) render "$2" "$3" ;;
  apply)
    if [ -z "$(tmux show -gqv @proto_saved_status_right)" ]; then
      tmux set -g @proto_saved_status_right "$(tmux show -gv status-right)"
      tmux set -g @proto_saved_status_right_length "$(tmux show -gv status-right-length)"
    fi
    tmux set -g @proto_usage_variant "$(opt @proto_usage_variant A)"
    tmux set -g @proto_usage_scenario "$(opt @proto_usage_scenario typical)"
    tmux set -g status-right-length 300
    tmux set -g status-right "#($SELF render #{@proto_usage_variant} #{@proto_usage_scenario}) #[fg=$DIM]│$(tmux show -gv @proto_saved_status_right)"
    tmux bind-key F9 run-shell "$SELF prev"
    tmux bind-key F10 run-shell "$SELF next"
    set_variant "$(opt @proto_usage_variant A)"
    ;;
  next) cycle 1 ;;
  prev) cycle -1 ;;
  variant) set_variant "$2" ;;
  scenario) tmux set -g @proto_usage_scenario "$2"; set_variant "$(opt @proto_usage_variant A)" ;;
  restore)
    saved=$(tmux show -gqv @proto_saved_status_right)
    [ -n "$saved" ] && tmux set -g status-right "$saved"
    len=$(tmux show -gqv @proto_saved_status_right_length)
    [ -n "$len" ] && tmux set -g status-right-length "$len"
    tmux unbind-key F9 2>/dev/null; tmux unbind-key F10 2>/dev/null
    for o in @proto_saved_status_right @proto_saved_status_right_length @proto_usage_variant @proto_usage_scenario; do tmux set -gu "$o"; done
    tmux refresh-client -S
    echo "status-right restored"
    ;;
  preview)
    for s in typical hot legacy-cursor; do
      echo "── scenario: $s"
      for v in $VARIANTS; do
        render "$v" "$s" | perl -pe 's/#\[fg=#(..)(..)(..)\]/sprintf("\e[38;2;%d;%d;%dm",hex $1,hex $2,hex $3)/ge'
        printf '\e[0m\n'
      done
    done
    ;;
  *) sed -n '2,12p' "$SELF" ;;
esac
