#!/bin/bash
# Write ebay-capture/*.json from aIQ My Usage or CLI /usage (phase 1: manual numbers).
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/ebay_acquire.sh
. "$DIR/lib/ebay_acquire.sh"

usage() {
  cat <<'EOF'
Usage: capture-usage.sh <claude|codex|cursor> <mtd_usd> <cap_usd>

Creates or updates the ebay profile capture file used by acquire.ebay.sh.
Cross-check MTD and cap against aIQ My Usage before saving.

Example:
  capture-usage.sh claude 42.50 150

Files live under:
  ${EBAY_USAGE_CAPTURE_DIR:-$CACHE/ebay-capture}/<provider>.json
EOF
}

prov=${1:-}
mtd=${2:-}
cap=${3:-}
if [ -z "$prov" ] || [ -z "$mtd" ] || [ -z "$cap" ]; then
  usage >&2
  exit 2
fi

case $prov in
  claude|codex|cursor) ;;
  *) echo "unknown provider: $prov" >&2; exit 2 ;;
esac

case $mtd in *[!0-9.]*|'') echo "mtd_usd must be a number" >&2; exit 2 ;; esac
case $cap in *[!0-9.]*|'') echo "cap_usd must be a number" >&2; exit 2 ;; esac

dest=$(ebay_capture_dir)
mkdir -p "$dest"
tmp=$(mktemp)
jq -n --arg p "$prov" --argjson mtd "$mtd" --argjson cap "$cap" \
  '{provider: $p, mtd_usd: $mtd, cap_usd: $cap}' >"$tmp"
mv -f "$tmp" "$dest/$prov.json"
chmod 600 "$dest/$prov.json"
echo "wrote $dest/$prov.json"