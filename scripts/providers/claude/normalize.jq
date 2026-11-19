# Claude get_usage (or cache) payload -> usage snapshot. Pure; `$now` is epoch seconds.
include "labels";

def iso_epoch:
  if type == "number" then .
  elif type == "string" then (fromdateiso8601 | floor)
  else null end;

def window_from($label; $seconds; $obj):
  if $obj == null or ($obj | type) != "object" then empty
  elif ($obj.utilization | type) != "number" then empty
  else {
    label: $label,
    used_pct: ($obj.utilization | round),
    resets_at: ($obj.resets_at | iso_epoch),
    window_seconds: $seconds
  } end;

def scoped_label:
  "wk-" + (.display_name | ascii_downcase | gsub("[^a-z0-9]+"; "-") | gsub("^-+|-+$"; ""));

def windows_from($rl):
  [
    window_from("5h"; 18000; $rl.five_hour),
    window_from("wk"; 604800; $rl.seven_day),
    window_from("wk-opus"; 604800; $rl.seven_day_opus),
    window_from("wk-sonnet"; 604800; $rl.seven_day_sonnet),
    ($rl.model_scoped // [] | .[]
     | select((.utilization | type) == "number")
     | {
         label: scoped_label,
         used_pct: (.utilization | round),
         resets_at: (.resets_at | iso_epoch),
         window_seconds: 604800
       })
  ]
  | map(select(.resets_at != null));

. as $in
| ($in | if .source == "cache" then .rate_limits else .rate_limits end) as $rl
| {
    provider: "claude",
    fetched_at: $now,
    retry_at: $now
  }
+ if ($rl | type) == "object" and (windows_from($rl) | length) > 0 then
    {
      status: "ok",
      ok_at: (if $in.source == "cache" and ($in.fetchedAtMs | type) == "number"
              then ($in.fetchedAtMs / 1000 | floor) else $now end),
      error: null,
      windows: windows_from($rl)
    }
  else
    {
      status: "bad_shape",
      ok_at: null,
      error: "unrecognised Claude usage response",
      windows: []
    }
  end