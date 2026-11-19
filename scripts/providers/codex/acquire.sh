#!/bin/bash
# Prints the raw Codex `wham/usage` response on stdout. Exits 2 = signed_out, 1 = error.
# STDERR carries a short error line only; never tokens or response bodies.
auth="${CODEX_HOME:-$HOME/.codex}/auth.json"
if [ ! -r "$auth" ]; then
  echo "no Codex sign-in" >&2
  exit 2
fi

IFS=$'\t' read -r token account < <(jq -r '[.tokens.access_token // "", .tokens.account_id // ""] | @tsv' "$auth")
if [ -z "$token" ]; then
  echo "no access token in auth file" >&2
  exit 2
fi

body=$(mktemp) hdr=$(mktemp)
trap 'rm -f "$body" "$hdr"' EXIT

# No -f: we classify HTTP status ourselves. Token goes through a config file, not argv.
http=$(printf 'header = "Authorization: Bearer %s"\nheader = "chatgpt-account-id: %s"\n' "$token" "$account" |
  curl -sS --max-time 15 -H 'User-Agent: codex-cli' --config - \
    -D "$hdr" -o "$body" -w '%{http_code}' \
    https://chatgpt.com/backend-api/wham/usage)
if [ -z "$http" ]; then
  echo "network error from wham/usage" >&2
  exit 1
fi

case $http in
  2*) cat "$body"; exit 0 ;;
  401|403)
    echo "HTTP $http from wham/usage" >&2
    exit 2 ;;
  429)
    retry_after=$(awk -F': ' 'tolower($1)=="retry-after" {gsub(/\r/,""); print $2; exit}' "$hdr")
    echo "HTTP 429 from wham/usage" >&2
    [ -n "$retry_after" ] && echo "retry_after=$retry_after" >&2
    exit 1 ;;
  5*)
    echo "HTTP $http from wham/usage" >&2
    exit 1 ;;
  *)
    echo "HTTP $http from wham/usage" >&2
    exit 1 ;;
  esac