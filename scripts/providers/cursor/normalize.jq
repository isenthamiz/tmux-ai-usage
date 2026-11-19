# Cursor acquire payload (sand + optional summary) -> usage snapshot. Pure; $now is epoch seconds.
include "labels";
include "time";


def sand_ok:
  (.sand | type) == "object"
  and (.sand.isUnified | type) == "boolean";

def unified_windows:
  .sand as $s
  | if ($s.usagePercent | type) == "number"
      and ($s.currentPeriodStart | type) == "string"
      and ($s.nextResetTimestampUtc | type) == "string"
    then
      ($s.currentPeriodStart | iso_epoch) as $start
      | ($s.nextResetTimestampUtc | iso_epoch) as $end
      | [
          {
            label: "wk",
            used_pct: ($s.usagePercent | round),
            resets_at: $end,
            window_seconds: ($end - $start)
          }
        ]
    else []
    end;

def legacy_windows:
  .summary as $u
  | if ($u | type) == "object"
       and ($u.billingCycleEnd | type) == "string"
       and ($u.individualUsage.plan | type) == "object"
    then
      ($u.billingCycleEnd | iso_epoch) as $end
      | ($u.billingCycleStart | iso_epoch) as $start
      | (if ($end - $start) > 0 then ($end - $start) else 2592000 end) as $win
      | ($u.individualUsage.plan) as $plan
      | [
          (if ($plan.autoPercentUsed | type) == "number" then
            {
              label: "mo-auto",
              used_pct: ($plan.autoPercentUsed | round),
              resets_at: $end,
              window_seconds: $win
            }
           else empty end),
          (if ($plan.apiPercentUsed | type) == "number" then
            {
              label: "mo-api",
              used_pct: ($plan.apiPercentUsed | round),
              resets_at: $end,
              window_seconds: $win
            }
           else empty end)
        ]
    else []
    end;

def windows_from:
  if .sand.isUnified == true then unified_windows
  elif .sand.isUnified == false then legacy_windows
  else []
  end;

. | {
    provider: "cursor",
    fetched_at: $now,
    retry_at: $now
  }
+ if sand_ok and (windows_from | length) > 0 then
    {
      status: "ok",
      ok_at: $now,
      error: null,
      windows: windows_from
    }
  else
    {
      status: "bad_shape",
      ok_at: null,
      error: "unrecognised Cursor usage response",
      windows: []
    }
  end