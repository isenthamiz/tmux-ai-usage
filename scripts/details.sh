#!/bin/bash
# The details popup body: every enabled provider's quota windows in full,
# with problems explained. Reads cached usage snapshots only.
#
#   details.sh --open CLIENT WIDTH HEIGHT
#       (the key binding, via run-shell) pick the layout for the client's
#       width, measure the body and open a popup of exactly that size
#   details.sh --layout table|line --width N
#       (inside the popup) draw, redraw every 10 s, close on q or Esc
#   details.sh --once   draw once at $COLUMNS (default 80) and exit
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/options.sh
. "$DIR/lib/options.sh"
# shellcheck source=scripts/lib/snapshot.sh
. "$DIR/lib/snapshot.sh"
# shellcheck source=scripts/lib/format.sh
. "$DIR/lib/format.sh"

SELF="$DIR/details.sh"
BAR_CELLS=10
TABLE_WIDTH=56   # the widest table line: header and window rows
PADDING=1        # cells of space inside the popup border, on every side
CHROME=$((2 * PADDING + 2))   # padding on both sides plus the border
TITLE=' AI usage · q close '
TITLE_SLACK=5    # tmux 3.5a cuts a popup title shorter than its width - 5
RESET=$'\033[0m'

# A tmux colour as a terminal escape: #rrggbb, colourN, or a basic name.
ansi() { # tmux-colour
  local c=$1 n name
  case $c in
    '#'[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F])
      printf '\033[38;2;%d;%d;%dm' "0x${c:1:2}" "0x${c:3:2}" "0x${c:5:2}" ;;
    colour[0-9]*|color[0-9]*)
      printf '\033[38;5;%dm' "${c##*r}" ;;
    *)
      n=0
      for name in black red green yellow blue magenta cyan white; do
        [ "$c" = "$name" ] && { printf '\033[%dm' $((30 + n)); return; }
        n=$((n + 1))
      done ;;
  esac
}

provider_name() {
  case $1 in claude) echo Claude ;; codex) echo Codex ;; cursor) echo Cursor ;; esac
}

# The fix for a snapshot status, in words.
fix_text() { # provider status
  case $1/$2 in
    claude/signed_out) echo "Run \`claude\` in a terminal and log in." ;;
    codex/signed_out) echo "Run \`codex login\`." ;;
    cursor/signed_out) echo "Open the Cursor app and sign in." ;;
    */missing_dep) echo "Something it needs is missing. Run doctor.sh to see what." ;;
    */bad_shape) echo "The provider answered in a format the plugin doesn't know. The plugin may need an update." ;;
    */error) echo "Temporary error; retrying automatically." ;;
  esac
}

# The status-line marker followed by its fix.
problem_text() { # provider status
  printf '%s %s' "$(status_marker "$2")" "$(fix_text "$1" "$2")"
}

# The table when it fits the client with padding and border, else one line
# per provider. Sets LAYOUT and NOTE_WIDTH (the body width notes wrap to:
# the table's, or whatever room a narrow client leaves).
choose_layout() { # client_width
  local room=$(($1 - CHROME))
  if [ "$room" -ge "$TABLE_WIDTH" ]; then
    LAYOUT=table NOTE_WIDTH=$TABLE_WIDTH
  else
    LAYOUT=line NOTE_WIDTH=$room
    # Wrapping still needs room for a word after the indent.
    [ "$NOTE_WIDTH" -lt 16 ] && NOTE_WIDTH=16
  fi
}

# Characters on screen, not bytes: colours stripped, counted under UTF-8
# (tmux may run us under the C locale).
visible_width() { # text
  local LC_ALL=en_US.UTF-8 plain=$1
  while [[ $plain == *$'\033['*m* ]]; do
    local head=${plain%%$'\033['*} rest=${plain#*$'\033['}
    plain=$head${rest#*m}
  done
  echo "${#plain}"
}

# Word-wrap text to width columns, one line per output line.
wrap() { # width text
  local LC_ALL=en_US.UTF-8 width=$1 word line=""
  local -a words
  read -r -a words <<<"$2"
  for word in "${words[@]}"; do
    if [ -n "$line" ] && [ $((${#line} + 1 + ${#word})) -gt "$width" ]; then
      printf '%s\n' "$line"; line=$word
    else
      line=${line:+$line }$word
    fi
  done
  [ -n "$line" ] && printf '%s\n' "$line"
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

# Prints the popup body in LAYOUT (table, or one line per provider). Each
# provider's window rows come first, then its notes (problem, stale), which
# wrap to NOTE_WIDTH.
draw() {
  local text dim crit
  text=$(ansi "$COLOR_TEXT"); dim=$(ansi "$COLOR_DIM"); crit=$(ansi "$COLOR_CRIT")

  local narrow=0
  [ "$LAYOUT" = line ] && narrow=1

  local name_w=8 indent='         '
  if [ "$narrow" -eq 1 ]; then
    name_w=7; indent='        '
  else
    printf '%s%s%s\n' "$dim" \
      "$(rstrip "$(printf '%-8s %-10s %-16s %-9s %s' Provider Window Usage 'Resets in' 'Resets at')")" "$RESET"
  fi

  # P rows: provider status ok_at.  W rows: provider label pct resets_at.
  local kind p f1 f2 f3 cur="" status ok_at stale draws_windows rows=() notes=() line
  flush() {
    [ -n "$cur" ] || return 0
    local name first=1 r note color wrapped all=()
    name=$(provider_name "$cur")
    if [ "$narrow" -eq 1 ] && [ "${#rows[@]}" -gt 0 ]; then
      local joined=""
      for r in "${rows[@]}"; do joined="${joined:+$joined  }$r"; done
      all=("$joined")
    else
      all=("${rows[@]}")
    fi
    for note in "${notes[@]}"; do
      color=${note%%$'\x1f'*}
      while IFS= read -r wrapped; do
        all+=("$color$wrapped")
      done < <(wrap $((NOTE_WIDTH - ${#indent})) "${note#*$'\x1f'}")
    done
    for r in "${all[@]}"; do
      if [ "$first" -eq 1 ]; then
        printf '%s%s%s %s%s\n' "$text" "$(printf "%-${name_w}s" "$name")" "$RESET" "$r" "$RESET"
        first=0
      else
        printf '%s%s%s\n' "$indent" "$r" "$RESET"
      fi
    done
  }

  while IFS=$'\t' read -r kind p f1 f2 f3; do
    if [ "$kind" = P ]; then
      flush
      cur=$p status=$f1 ok_at=$f2 rows=() notes=() stale=0 draws_windows=1
      case $status in
        pending) notes=("$dim"$'\x1f'"… no reading yet") draws_windows=0 ;;
        signed_out|missing_dep|bad_shape)
          notes=("$crit"$'\x1f'"$(problem_text "$p" "$status")") draws_windows=0 ;;
        error) notes=("$crit"$'\x1f'"$(problem_text "$p" "$status")") ;;
      esac
      if [ "$draws_windows" -eq 1 ] && [ "${ok_at:-0}" != 0 ] && is_stale "$ok_at" "$now"; then
        stale=1
        notes+=("$dim"$'\x1f'"~ last good reading $(countdown $((now - ok_at))) ago; numbers may be out of date")
      fi
      continue
    fi
    [ "$draws_windows" -eq 1 ] || continue
    local label=$f1 pct=$f2 resets_at=$f3 color left="" at=""
    color=$(usage_color "$pct")
    [ "$stale" -eq 1 ] && color=$dim || color=$(ansi "$color")
    if [ "$resets_at" -gt "$now" ]; then
      left=$(countdown $((resets_at - now))); at=$(clock "$resets_at")
    fi
    if [ "$narrow" -eq 1 ]; then
      line="$dim$label $color$pct%$RESET${left:+ $dim$left}$RESET"
    else
      line=$(printf '%s%-10s %s%s %4s%%' "$dim" "$label" "$color" \
        "$(bar "$pct" "$BAR_CELLS" "$BAR_FILLED" "$BAR_EMPTY")" "$pct")
      [ -n "$left" ] && line=$(printf '%s %s%-9s %s' "$line" "$dim" "$left" "$at")
    fi
    rows+=("$line")
  done < <(read_snapshots)
  flush
}

# Open a popup sized to the body: widest line and line count, plus padding
# and border, at least as wide as the title, at most the client's size.
open_popup() { # client client_width client_height
  local client=$1 cw=$2 ch=$3 body line widest=0 lines=0 w h min_w
  choose_layout "$cw"
  body=$(draw)
  while IFS= read -r line; do
    w=$(visible_width "$line")
    [ "$w" -gt "$widest" ] && widest=$w
    lines=$((lines + 1))
  done <<<"$body"
  min_w=$(($(visible_width "$TITLE") + TITLE_SLACK))
  w=$((widest + CHROME))
  [ "$w" -lt "$min_w" ] && w=$min_w
  [ "$w" -gt "$cw" ] && w=$cw
  h=$((lines + CHROME))
  [ "$h" -gt "$ch" ] && h=$ch
  tmux display-popup -c "$client" -E -w "$w" -h "$h" -T "$TITLE" \
    "'$SELF' --layout $LAYOUT --width $NOTE_WIDTH"
}

load_options
now=${AI_USAGE_NOW:-$(date +%s)}

if [ "${1:-}" = --open ]; then
  open_popup "$2" "$3" "$4"
  exit 0
fi

choose_layout "${COLUMNS:-80}"
once=0
while [ $# -gt 0 ]; do
  case $1 in
    --layout) LAYOUT=$2; shift ;;
    --width) NOTE_WIDTH=$2; shift ;;
    --once) once=1 ;;
  esac
  shift
done

# Piped or under test: one frame, unpadded.
if [ "$once" -eq 1 ] || [ ! -t 0 ]; then
  draw
  exit 0
fi

# In the popup: padded, redrawn every 10 s, closed by q or Esc. Keys are
# polled once a second because bash 3.2's read -t can't be woken sooner.
drawn_at=0
while :; do
  now=$(date +%s)
  if [ $((now - drawn_at)) -ge 10 ]; then
    printf '\033[2J\033[H\n'
    draw | sed 's/^/ /'
    drawn_at=$now
  fi
  key=""
  IFS= read -rsn1 -t 1 key
  case $key in q|$'\033') exit 0 ;; esac
done
