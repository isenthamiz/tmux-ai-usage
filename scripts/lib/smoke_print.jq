# Usage numbers only for smoke.sh (never tokens or raw responses).
{
  provider,
  status,
  fetched_at,
  ok_at,
  retry_at,
  error,
  windows: [
    .windows[]? | {label, used_pct, resets_at, window_seconds}
  ]
}