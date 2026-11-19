# Merge a new usage snapshot attempt into the cached snapshot (back-off + keep good windows).
def backoff_error($old; $interval):
  if $old == null or $old.status != "error" or ($old.retry_at | type) != "number"
     or ($old.fetched_at | type) != "number"
  then $interval
  else (($old.retry_at - $old.fetched_at) * 2 | if . > 900 then 900 else . end)
  end;

def backoff_429($retry_after):
  (($retry_after // 300) | if . > 3600 then 3600 else . end);

def retry_delay($old; $new; $interval; $retry_after):
  if $new.status == "ok" then 0
  elif $new.status == "error" and (($new.error // "") | test("429"))
  then backoff_429($retry_after)
  elif $new.status == "error" then backoff_error($old; $interval)
  else $interval
  end;

. as $old |
if $new.status == "ok" then $new
else
  ($old // {provider: $new.provider, ok_at: null, windows: []})
  | {
      provider: .provider,
      status: $new.status,
      fetched_at: $new.fetched_at,
      ok_at: .ok_at,
      retry_at: ($now + retry_delay($old; $new; $interval; $retry_after)),
      error: $new.error,
      windows: .windows
    }
end