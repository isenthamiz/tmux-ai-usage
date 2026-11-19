# Window label from a quota window's length in seconds (see GLOSSARY.md: Window label).
def window_label:
  if . == 18000 then "5h"
  elif . == 604800 then "wk"
  elif . % 86400 == 0 then "\(. / 86400)d"
  elif . % 3600 == 0 then "\(. / 3600)h"
  else "\(. / 60 | floor)m"
  end;
