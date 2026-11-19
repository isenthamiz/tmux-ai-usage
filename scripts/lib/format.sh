# shellcheck shell=bash
# Pieces of a usage bar. Pure functions: no tmux, no I/O.

# Compact countdown: the two largest units, dropping a zero remainder.
# 2820 -> 47m, 7980 -> 2h13m, 274000 -> 3d4h, 86400 -> 1d.
countdown() {
  local s=$1 d h m
  [ "$s" -lt 0 ] && s=0
  d=$((s / 86400)); h=$((s % 86400 / 3600)); m=$((s % 3600 / 60))
  if [ "$d" -gt 0 ]; then
    if [ "$h" -gt 0 ]; then echo "${d}d${h}h"; else echo "${d}d"; fi
  elif [ "$h" -gt 0 ]; then
    if [ "$m" -gt 0 ]; then echo "${h}h${m}m"; else echo "${h}h"; fi
  else
    echo "${m}m"
  fi
}

# Bar of $3 cells, filled = round(pct * width / 100). Glyphs are passed whole, so
# multibyte characters are never sliced (safe under the C locale).
bar() { # pct width filled empty
  local pct=$1 width=$2 filled i out=""
  filled=$(( (pct * width + 50) / 100 ))
  [ "$filled" -gt "$width" ] && filled=$width
  for ((i = 0; i < width; i++)); do
    if [ "$i" -lt "$filled" ]; then out="$out$3"; else out="$out$4"; fi
  done
  echo "$out"
}

usage_color() { # pct
  if [ "$1" -ge "$CRIT_AT" ]; then echo "$COLOR_CRIT"
  elif [ "$1" -ge "$WARN_AT" ]; then echo "$COLOR_WARN"
  else echo "$COLOR_OK"
  fi
}
