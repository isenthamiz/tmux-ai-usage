# Raw eBay monthly capture -> usage snapshot. Pure; $now is epoch seconds.
# Input: provider, mtd_usd, cap_usd, resets_at, window_seconds

def used_pct:
  if (.cap_usd | type) != "number" or .cap_usd <= 0 then 0
  elif (.mtd_usd | type) != "number" then 0
  else ((.mtd_usd / .cap_usd) * 100 | round | if . > 100 then 100 elif . < 0 then 0 else . end)
  end;

def known_shape:
  (.provider | type) == "string"
  and (.mtd_usd | type) == "number"
  and (.cap_usd | type) == "number"
  and .cap_usd > 0
  and (.resets_at | type) == "number"
  and (.window_seconds | type) == "number";

{ fetched_at: $now, retry_at: $now }
+ if known_shape then
    {
      provider: .provider,
      status: "ok",
      ok_at: $now,
      error: null,
      windows: [
        {
          label: "mo",
          used_pct: used_pct,
          resets_at: .resets_at,
          window_seconds: .window_seconds
        }
      ]
    }
  else
    {
      provider: (.provider // "unknown"),
      status: "bad_shape",
      ok_at: null,
      error: "unrecognised eBay monthly usage capture",
      windows: []
    }
  end