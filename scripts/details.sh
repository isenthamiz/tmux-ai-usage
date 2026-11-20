#!/bin/bash
# The details popup body: every enabled provider's quota windows in full,
# with problems explained. Reads cached usage snapshots only.
#
#   details.sh          draw, redraw every 10 s, close on q or Esc
#   details.sh --once   draw once and exit (tests, piping)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/options.sh
. "$DIR/lib/options.sh"
# shellcheck source=scripts/lib/snapshot.sh
. "$DIR/lib/snapshot.sh"
# shellcheck source=scripts/lib/format.sh
. "$DIR/lib/format.sh"

BAR_CELLS=10
NARROW_BELOW=60
RESET=$'\033[0m'

# A tmux colour as a terminal escape: #rrggbb, colourN, or a basic name.
ansi() { # tmux-colour
  local c=$1 n
  case $c in
    '#'[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F])
      printf '\033[38;2;%d;%d;%dm' "0x${c:1:2}" "0x${c:3:2}" "0x${c:5:2}" ;;
    colour[0-9]*|color[0-9]*)
      printf '\033[38;5;%dm' "${c##*r}" ;;
    *)
      n=0
      for c2 in black red green yellow blue magenta cyan white; do
        [ "$c" = "$c2" ] && { printf '\033[%dm' $((30 + n)); return; }
        n=$((n + 1))
      done ;;
  esac
}

provider_name() {
  case $1 in claude) echo Claude ;; codex) echo Codex ;; cursor) echo Cursor ;; esac
}

# The status-line marker and its fix, in words.
problem_text() { # provider status
  case $1/$2 in
    claude/signed_out) echo "!login Run \`claude\` in a terminal and log in." ;;
    codex/signed_out) echo "!login Run \`codex login\`." ;;
    cursor/signed_out) echo "!login Open the Cursor app and sign in." ;;
    */missing_dep) echo "!deps Something it needs is missing. Run doctor.sh to see what." ;;
    */bad_shape) echo "!format The provider answered in a format the plugin doesn't know. The plugin may need an update." ;;
    */error) echo "!error Temporary error; retrying automatically." ;;
  esac
}

clock() { date -r "$1" '+%a %H:%M'; }

rstrip() { local s=$1; printf '%s' "${s%"${s##*[! ]}"}"; }

# One jq call: per enabled provider a P row, then its windows most-used first
# (a passed reset counts as 0%).
read_snapshots() {
  local p args=()
  for p in $PROVIDERS; do
    args+=(--argjson "$p" "$(snapshot_json_for "$p")")
  done
  # shellcheck disable=SC2086  # PROVIDERS is a space-separated list
  jq -r -n --argjson now "$now" "${args[@]}" --arg order "$PROVIDERS" '
    $order | split(" ")[] as $p | ($ARGS.named[$p]) as $s
    | if $s == null then ["P", $p, "pending", 0] | @tsv
      else
        (["P", $p, ($s.status // "error"), ($s.ok_at // 0)] | @tsv),
        ($s.windows // []
         | map(. + {pct: (if (.resets_at // 0) <= $now then 0 else .used_pct end)})
         | sort_by(-.pct)[]
         | ["W", $p, .label, .pct, (.resets_at // 0)] | @tsv)
      end'
}

# Prints the popup body: a table, or one line per provider when narrow.
# Each provider's window rows come first, then its notes (problem, stale).
draw() {
  local text dim crit
  text=$(ansi "$COLOR_TEXT"); dim=$(ansi "$COLOR_DIM"); crit=$(ansi "$COLOR_CRIT")

  local narrow=0 cols=${COLUMNS:-}
  [ -n "$cols" ] || cols=$(tput cols 2>/dev/null || echo 80)
  [ "$cols" -lt "$NARROW_BELOW" ] && narrow=1

  local name_w=8 indent='         '
  if [ "$narrow" -eq 1 ]; then
    name_w=7; indent='        '
  else
    printf '%s%s%s\n' "$dim" \
      "$(rstrip "$(printf '%-8s %-10s %-16s %-9s %s' Provider Window Usage 'Resets in' 'Resets at')")" "$RESET"
  fi

  local kind p a b c cur="" status ok_at stale shows rows=() notes=() line
  flush() {
    [ -n "$cur" ] || return 0
    local name first=1 r all=("${rows[@]}" "${notes[@]}")
    name=$(provider_name "$cur")
    if [ "$narrow" -eq 1 ] && [ "${#rows[@]}" -gt 0 ]; then
      local joined=""
      for r in "${rows[@]}"; do joined="${joined:+$joined  }$r"; done
      all=("$joined" "${notes[@]}")
    fi
    for r in "${all[@]}"; do
      if [ "$first" -eq 1 ]; then
        printf '%s%s%s %s%s\n' "$text" "$(printf "%-${name_w}s" "$name")" "$RESET" "$r" "$RESET"
        first=0
      else
        printf '%s%s%s\n' "$indent" "$r" "$RESET"
      fi
    done
  }

  while IFS=$'\t' read -r kind p a b c; do
    if [ "$kind" = P ]; then
      flush
      cur=$p status=$a ok_at=$b rows=() notes=() stale=0 shows=1
      case $status in
        pending) notes=("${dim}… no reading yet") shows=0 ;;
        signed_out|missing_dep|bad_shape)
          notes=("$crit$(problem_text "$p" "$status")") shows=0 ;;
        error) notes=("$crit$(problem_text "$p" "$status")") ;;
      esac
      if [ "$shows" -eq 1 ] && [ "${ok_at:-0}" != 0 ] &&
         [ $((now - ok_at)) -gt "$STALE_AFTER" ]; then
        stale=1
        notes+=("$dim~ last good reading $(countdown $((now - ok_at))) ago; numbers may be out of date")
      fi
      continue
    fi
    [ "$shows" -eq 1 ] || continue
    local color left="" at=""
    color=$(usage_color "$b")
    [ "$stale" -eq 1 ] && color=$dim || color=$(ansi "$color")
    if [ "$c" -gt "$now" ]; then
      left=$(countdown $((c - now))); at=$(clock "$c")
    fi
    if [ "$narrow" -eq 1 ]; then
      line="$dim$a $color$b%$RESET${left:+ $dim$left}$RESET"
    else
      line=$(printf '%s%-10s %s%s %4s%%' "$dim" "$a" "$color" \
        "$(bar "$b" "$BAR_CELLS" "$BAR_FILLED" "$BAR_EMPTY")" "$b")
      [ -n "$left" ] && line=$(printf '%s %s%-9s %s' "$line" "$dim" "$left" "$at")
    fi
    rows+=("$line")
  done < <(read_snapshots)
  flush
}

load_options

if [ "${1:-}" = --once ]; then
  now=${AI_USAGE_NOW:-$(date +%s)}
  draw
  exit 0
fi

while :; do
  now=$(date +%s)
  printf '\033[2J\033[H'
  draw
  printf '\n%sq close%s' "$(ansi "$COLOR_DIM")" "$RESET"
  IFS= read -rsn1 -t 10 key
  case $key in q|$'\033') exit 0 ;; esac
done
