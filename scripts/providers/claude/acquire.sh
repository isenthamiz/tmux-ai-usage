#!/bin/bash
# Claude plan quota via get_usage; falls back to .cachedUsageUtilization only.
# Never reads credentials. Exits 2 = signed_out, 1 = transient error.
DIR_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib"
# shellcheck source=scripts/lib/deps.sh
. "$DIR_LIB/deps.sh"

config="${CLAUDE_CONFIG:-$HOME/.claude.json}"
request_id="tmux-ai-usage-$$"

if ! claude_bin=$(find_claude_binary); then
  echo "claude CLI not found" >&2
  exit 1
fi

_usage_request='{"type":"control_request","request_id":"'"$request_id"'","request":{"subtype":"get_usage","skip_behaviors":true}}'

stderr=$(mktemp)
stream=$(mktemp)
stdin_hold=$(mktemp)
trap 'rm -f "$stderr" "$stream" "$stdin_hold"' EXIT

{ printf '%s\n' "$_usage_request"
  while [ -e "$stdin_hold" ]; do sleep 0.2; done
} | "$claude_bin" -p --no-session-persistence \
  --input-format stream-json --output-format stream-json 2>"$stderr" >"$stream" &
runner=$!

response=""
for _ in $(seq 1 90); do
  if response=$(jq -c --arg id "$request_id" '
        select(.type == "control_response" and .response.request_id == $id)
        | .response.response
      ' "$stream" 2>/dev/null) && [ -n "$response" ] && [ "$response" != "null" ]; then
    rm -f "$stdin_hold"
    break
  fi
  kill -0 "$runner" 2>/dev/null || break
  sleep 0.2
done

rm -f "$stdin_hold"
kill "$runner" 2>/dev/null
wait "$runner" 2>/dev/null || true

if [ -n "$response" ] && [ "$response" != "null" ]; then
  printf '%s' "$response"
  exit 0
fi

if grep -Eiq 'not logged in|sign in|authentication|unauthorized|401' "$stderr"; then
  head -1 "$stderr" >&2
  exit 2
fi
if grep -Eiq '429|rate limit' "$stderr"; then
  echo "HTTP 429 from usage API" >&2
  ra=$(awk -F': ' 'tolower($1) ~ /retry/ {print $2; exit}' "$stderr" | tr -d '\r')
  [ -n "$ra" ] && echo "retry_after=$ra" >&2
  exit 1
fi

if [ -r "$config" ]; then
  cached=$(jq -c '.cachedUsageUtilization // empty' "$config" 2>/dev/null)
  if [ -n "$cached" ] && [ "$cached" != "null" ]; then
    jq -n --argjson c "$cached" \
      '{source: "cache", fetchedAtMs: $c.fetchedAtMs, rate_limits: $c.utilization}'
    exit 0
  fi
fi

head -1 "$stderr" >&2
echo "get_usage failed" >&2
exit 1