# Window label from a quota window's length in seconds (see GLOSSARY.md: Window label).
# 5h and wk are named; any other length is the compact duration used for countdowns:
# the two largest units, dropping a zero remainder (5400 -> 1h30m, 86400 -> 1d).
def compact_duration:
  (. / 86400 | floor) as $d | (. % 86400 / 3600 | floor) as $h | (. % 3600 / 60 | floor) as $m
  | if $d > 0 then "\($d)d" + (if $h > 0 then "\($h)h" else "" end)
    elif $h > 0 then "\($h)h" + (if $m > 0 then "\($m)m" else "" end)
    else "\($m)m"
    end;

def window_label:
  if . == 18000 then "5h"
  elif . == 604800 then "wk"
  else compact_duration
  end;
