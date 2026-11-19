# One jq call: pick the displayed window per provider snapshot (see render.sh).
def effective_pct($w; $now):
  if ($w.resets_at // 0) <= $now then 0 else $w.used_pct end;

def auto_pick($ws; $now):
  $ws | max_by(effective_pct(.; $now));

def pick($ws; $pin; $now):
  if ($ws | length) == 0 then null
  elif $pin != "auto" then
    (([$ws[] | select(.label == $pin)][0]) // null) as $fixed
    | if $fixed == null then auto_pick($ws; $now) else $fixed end
  else auto_pick($ws; $now) end;

def row($snap; $pin):
  if $snap == null then {
    provider: null, status: "pending", fetched_at: 0, ok_at: 0, retry_at: 0,
    window_label: "", used_pct: 0, resets_at: 0, has_windows: 0
  }
  else
    ($snap.status // "error") as $st
    | ($snap.fetched_at // 0) as $fa
    | ($snap.ok_at // 0) as $oa
    | ($snap.retry_at // 0) as $ra
    | ($snap.windows // []) as $ws
    | (pick($ws; $pin; $now)) as $w
    | {
        provider: ($snap.provider // null),
        status: $st,
        fetched_at: $fa,
        ok_at: $oa,
        retry_at: $ra,
        window_label: ($w.label // ""),
        used_pct: ($w.used_pct // 0),
        resets_at: ($w.resets_at // 0),
        has_windows: (if ($ws | length) > 0 then 1 else 0 end)
      }
  end;

def tsv($p; $r):
  [$p, $r.status, $r.fetched_at, $r.ok_at, $r.retry_at,
   $r.window_label, $r.used_pct, $r.resets_at, $r.has_windows] | @tsv;

tsv("claude"; row($claude; $claude_pin)),
tsv("codex"; row($codex; $codex_pin)),
tsv("cursor"; row($cursor; $cursor_pin))