# Raw `wham/usage` response -> usage snapshot. Pure: no I/O. `$now` is epoch seconds.
include "labels";

{
  provider: "codex",
  status: "ok",
  fetched_at: $now,
  ok_at: $now,
  retry_at: $now,
  error: null,
  windows: [
    .rate_limit.primary_window, .rate_limit.secondary_window
    | select(. != null)
    | {
        label: (.limit_window_seconds | window_label),
        used_pct: .used_percent,
        resets_at: .reset_at,
        window_seconds: .limit_window_seconds
      }
  ]
}
