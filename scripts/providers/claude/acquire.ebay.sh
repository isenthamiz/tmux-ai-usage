#!/bin/bash
# eBay Claude Code: MTD/cap from ~/.cache/.../ebay-capture/claude.json (phase 1).
DIR_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib"
# shellcheck source=scripts/lib/ebay_acquire.sh
. "$DIR_LIB/ebay_acquire.sh"
ebay_acquire_emit claude