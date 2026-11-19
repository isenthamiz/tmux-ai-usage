# Raw `wham/usage` response -> usage snapshot. Pure: no I/O. `$now` is epoch seconds.
include "labels";

def known_window:
  type == "object"
  and (.used_percent | type) == "number"
  and (.limit_window_seconds | type) == "number"
  and (.reset_at | type) == "number";

def known_shape:
  (.rate_limit | type) == "object"
  and ([.rate_limit.primary_window, .rate_limit.secondary_window]
       | all(. == null or known_window));

{ provider: "codex", fetched_at: $now, retry_at: $now }
+ if known_shape then
    {
      status: "ok",
      ok_at: $now,
      error: null,
      windows: [
        .rate_limit.primary_window, .rate_limit.secondary_window
        | select(. != null)
        | {
            label: (.limit_window_seconds | window_label),
            used_pct: (.used_percent | round),
            resets_at: .reset_at,
            window_seconds: .limit_window_seconds
          }
      ]
    }
  else
    { status: "bad_shape", ok_at: null, error: "unrecognised wham/usage response", windows: [] }
  end
