#!/bin/bash
# Prints the raw Codex `wham/usage` response. All I/O for the Codex provider.
# The sign-in is read only; the token is never refreshed or written anywhere,
# and is passed to curl on stdin so it never appears in `ps`.
auth="${CODEX_HOME:-$HOME/.codex}/auth.json"
[ -r "$auth" ] || { echo "no Codex sign-in at $auth" >&2; exit 1; }

IFS=$'\t' read -r token account < <(jq -r '[.tokens.access_token // "", .tokens.account_id // ""] | @tsv' "$auth")
[ -n "$token" ] || { echo "no access token in $auth" >&2; exit 1; }

printf 'header = "Authorization: Bearer %s"\nheader = "chatgpt-account-id: %s"\n' "$token" "$account" |
  curl -fsS --max-time 15 -H 'User-Agent: codex-cli' --config - \
    https://chatgpt.com/backend-api/wham/usage
