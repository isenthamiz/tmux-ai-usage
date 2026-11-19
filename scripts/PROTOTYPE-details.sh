#!/bin/bash
# PROTOTYPE — throwaway. Answers "How should the details popup look and open?" (issue #42).
# Lives only on the prototype/details-popup branch; never merged. No tests, no validation.
#
# Open it (from any tmux pane):
#   scripts/PROTOTYPE-details.sh open        # display-popup, 80% x 60%
#   W=50 H=14 scripts/PROTOTYPE-details.sh open   # try a small popup
# Inside: 1 / 2 / 3 switch variant, s toggles simulated problem states, q or Esc closes.
export LC_ALL=en_US.UTF-8
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
CACHE=${CACHE:-$HOME/.cache/tmux-ai-usage}
STALE_AFTER=900 WARN=60 CRIT=85

if [ "${1:-}" = open ]; then
  exec tmux display-popup -E -w "${W:-80%}" -h "${H:-60%}" -T " AI usage " "'$SELF' run"
fi

hex() { printf '\033[38;2;%d;%d;%dm' "0x${1:1:2}" "0x${1:3:2}" "0x${1:5:2}"; }
opt() { local v; v=$(tmux show -gqv "$1" 2>/dev/null); printf '%s' "${v:-$2}"; }
OK=$(hex "$(opt @thm_green '#a6e3a1')"); WN=$(hex "$(opt @thm_yellow '#f9e2af')"); CR=$(hex "$(opt @thm_red '#f38ba8')")
TX=$(hex "$(opt @thm_text '#cdd6f4')"); DM=$(hex "$(opt @thm_overlay_0 '#6c7086')"); B=$'\033[1m'; R=$'\033[0m'

dur() { local s=$1 d h m; [ "$s" -lt 0 ] && s=0
  d=$((s/86400)); h=$((s%86400/3600)); m=$((s%3600/60))
  if [ $d -gt 0 ]; then printf '%sd' $d; [ $h -gt 0 ] && printf '%sh' $h
  elif [ $h -gt 0 ]; then printf '%sh' $h; [ $m -gt 0 ] && printf '%sm' $m
  else printf '%sm' $m; fi; }
lvl() { if [ "$1" -ge $CRIT ]; then printf '%s' "$CR"; elif [ "$1" -ge $WARN ]; then printf '%s' "$WN"; else printf '%s' "$OK"; fi; }
bar() { local p=$1 w=$2 n i out=""; n=$(( (p*w+50)/100 ))
  for ((i=0;i<w;i++)); do if [ $i -lt $n ]; then out="${out}▰"; else out="${out}▱"; fi; done; printf '%s' "$out"; }
name() { case $1 in claude) echo Claude ;; codex) echo Codex ;; cursor) echo Cursor ;; esac; }
fix() { case $1/$2 in
  claude/signed_out) echo "Signed out. Run \`claude\` in a terminal and log in." ;;
  codex/signed_out) echo "Signed out. Run \`codex login\`." ;;
  cursor/signed_out) echo "Signed out. Open the Cursor app and sign in." ;;
  */missing_dep) echo "Something it needs is missing. Run doctor.sh to see what." ;;
  */bad_shape) echo "The provider answered in a format the plugin doesn't know. The plugin may need an update." ;;
  */error) echo "Temporary error; retrying automatically." ;;
esac; }

# state: provider status age_secs   (simulation overrides)
SIM=0 VAR=1
status_of() { local p=$1 st ok
  st=$(jq -r .status "$CACHE/$p.json" 2>/dev/null); ok=$(jq -r '.ok_at // 0' "$CACHE/$p.json" 2>/dev/null)
  if [ $SIM = 1 ]; then case $p in claude) st=signed_out ;; codex) ok=$((NOW-7200)) ;; esac; fi
  [ -z "$st" ] && st=pending
  echo "$st $((NOW-ok))"; }
windows() { jq -r --argjson now "$NOW" '.windows | sort_by(-.used_pct)[] | "\(.label) \(.used_pct) \(.resets_at - $now) \(.resets_at)"' "$CACHE/$1.json" 2>/dev/null; }
at() { date -r "$1" '+%a %H:%M'; }

problem_line() { # provider status age
  local p=$1 st=$2 age=$3
  local mk; case $st in signed_out) mk=login ;; missing_dep) mk=deps ;; bad_shape) mk=format ;; *) mk=$st ;; esac
  if [ "$st" != ok ]; then printf '%s!%s %s%s\n' "$CR" "$mk" "$(fix "$p" "$st")" "$R"
  elif [ "$age" -gt $STALE_AFTER ]; then printf '%s~ last good reading %s ago; numbers may be out of date%s\n' "$DM" "$(dur "$age")" "$R"; fi; }

v1() { # table
  printf '%s%-8s %-10s %-12s %5s  %-9s %s%s\n' "$DM" Provider Window Usage "" "Resets in" "Resets at" "$R"
  for p in claude codex cursor; do
    read -r st age <<<"$(status_of $p)"; first=1
    while read -r wl pct secs ts; do [ -z "$wl" ] && continue
      n=$([ $first = 1 ] && name $p || echo "")
      printf '%s%-8s%s %s%-10s%s %s%-12s %4s%%%s  %s%-9s %s%s\n' "$TX" "$n" "$R" "$DM" "$wl" "$R" "$(lvl "$pct")" "$(bar "$pct" 10)" "$pct" "$R" "$DM" "$(dur "$secs")" "$(at "$ts")" "$R"
      first=0
    done <<<"$(windows $p)"
    pl=$(problem_line $p "$st" "$age"); [ -n "$pl" ] && printf '         %s\n' "$pl"
  done; }

v2() { # cards
  for p in claude codex cursor; do
    read -r st age <<<"$(status_of $p)"
    printf '%s%s%s%s  %supdated %s ago%s\n' "$B" "$TX" "$(name $p)" "$R" "$DM" "$(dur "$age")" "$R"
    pl=$(problem_line $p "$st" "$age"); [ -n "$pl" ] && printf '  %s\n' "$pl"
    while read -r wl pct secs ts; do [ -z "$wl" ] && continue
      printf '  %s%-10s%s %s%s %3s%%%s  %sresets in %s (%s)%s\n' "$DM" "$wl" "$R" "$(lvl "$pct")" "$(bar "$pct" 10)" "$pct" "$R" "$DM" "$(dur "$secs")" "$(at "$ts")" "$R"
    done <<<"$(windows $p)"
    echo
  done; }

v3() { # compact, for small popups
  for p in claude codex cursor; do
    read -r st age <<<"$(status_of $p)"; line=""
    while read -r wl pct secs ts; do [ -z "$wl" ] && continue
      line="$line $DM$wl$R $(lvl "$pct")$pct%$R $DM$(dur "$secs")$R "
    done <<<"$(windows $p)"
    printf '%s%-7s%s%s\n' "$TX" "$(name $p)" "$R" "$line"
    pl=$(problem_line $p "$st" "$age"); [ -n "$pl" ] && printf '        %s\n' "$pl"
  done; }

while :; do
  NOW=$(date +%s)
  printf '\033[2J\033[H'
  case $VAR in 1) v1 ;; 2) v2 ;; 3) v3 ;; esac
  printf '\n%svariant %s (1 table · 2 cards · 3 compact)  ·  s simulate problems: %s  ·  q close%s' "$DM" "$VAR" "$([ $SIM = 1 ] && echo on || echo off)" "$R"
  IFS= read -rsn1 k
  case $k in 1|2|3) VAR=$k ;; s) SIM=$((1-SIM)) ;; q|$'\033') exit 0 ;; esac
done
