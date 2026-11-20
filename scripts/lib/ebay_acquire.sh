# shellcheck shell=bash
# eBay profile: read MTD/cap from a capture file until CLI parsers land.

ebay_capture_dir() {
  local base="${CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/tmux-ai-usage}"
  printf '%s' "${EBAY_USAGE_CAPTURE_DIR:-${AI_USAGE_EBAY_CAPTURE_DIR:-$base/ebay-capture}}"
}

_ebay_month_bounds() { # epoch-now -> resets_at window_seconds (stdout, two lines)
  local now=$1 som som_epoch next win
  som=$(date -r "$now" +%Y-%m-01)
  som_epoch=$(date -j -f "%Y-%m-%d" "$som" +%s)
  next=$(date -r "$som_epoch" -v+1m +%s)
  win=$((next - som_epoch))
  printf '%s\n%s\n' "$next" "$win"
}

# Prints one JSON object for normalize.ebay.jq. Exits 2 when capture missing.
ebay_acquire_emit() { # provider
  local prov=$1 dir file now resets window
  now=${AI_USAGE_NOW:-$(date +%s)}
  dir=$(ebay_capture_dir)
  mkdir -p "$dir" || exit 1
  file="$dir/$prov.json"
  if [ ! -f "$file" ]; then
    echo "eBay capture missing: $file (run scripts/ebay/capture-usage.sh)" >&2
    exit 2
  fi
  if ! jq -e . >/dev/null 2>&1 <"$file"; then
    echo "invalid JSON in $file" >&2
    exit 1
  fi
  {
    IFS= read -r resets || exit 1
    IFS= read -r window || exit 1
  } < <(_ebay_month_bounds "$now")
  jq -n --arg p "$prov" --argjson now "$now" --argjson resets "$resets" \
    --argjson window "$window" --slurpfile cap "$file" \
    '($cap[0]) as $in
     | {
         provider: ($in.provider // $p),
         mtd_usd: ($in.mtd_usd // $in.mtd // $in.month_to_date_usd),
         cap_usd: ($in.cap_usd // $in.cap // $in.monthly_cap_usd),
         resets_at: ($in.resets_at // $resets),
         window_seconds: ($in.window_seconds // $window)
       }'
}