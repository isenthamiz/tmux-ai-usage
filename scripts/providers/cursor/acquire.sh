#!/bin/bash
# Cursor plan quota from cursor.com dashboard APIs. Read-only token from the app DB.
# Exits 2 = signed_out, 3 = missing_dep (Keychain), 1 = transient error.
DIR_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib"
# shellcheck source=scripts/lib/deps.sh
. "$DIR_LIB/deps.sh"

now=${AI_USAGE_NOW:-$(date +%s)}
state_db="${CURSOR_STATE_DB:-$HOME/Library/Application Support/Cursor/User/globalStorage/state.vscdb}"

_jwt_payload_b64() {
  local jwt=$1 part
  part=$(printf '%s' "$jwt" | cut -d. -f2)
  case $((${#part} % 4)) in
    2) part="${part}==" ;;
    3) part="${part}=" ;;
  esac
  printf '%s' "$part" | tr '_-' '/+'
}

_jwt_claims() { # jwt
  _jwt_payload_b64 "$1" | base64 -D 2>/dev/null || _jwt_payload_b64 "$1" | base64 -d
}

_read_stored_token() {
  local db=$1
  [ -r "$db" ] || return 1
  sqlite3 -readonly "$db" "SELECT value FROM ItemTable WHERE key='cursorAuth/accessToken';" 2>/dev/null
}

_decrypt_token() { # stored openssl_bin
  local stored=$1 openssl_bin=$2
  if [[ "$stored" != cursor-safe-storage:v1:* ]]; then
    printf '%s' "$stored"
    return 0
  fi

  local pass blob key_hex ct_file dec_file
  sec_err=$(mktemp)
  if ! pass=$(security find-generic-password -s 'Cursor Safe Storage' -a 'Cursor Key' -w 2>"$sec_err"); then
  if grep -qiE 'user cancel|was denied|canceled' "$sec_err" 2>/dev/null; then
      rm -f "$sec_err"
      echo "Keychain access refused" >&2
      return 3
    fi
    rm -f "$sec_err"
    if ! pass=$(security find-generic-password -s 'Cursor Safe Storage' -a 'Cursor' -w 2>/dev/null); then
      echo "Cursor Safe Storage key not in Keychain" >&2
      return 3
    fi
  else
    rm -f "$sec_err"
  fi

  blob=$(printf '%s' "${stored#cursor-safe-storage:v1:}" | base64 -D 2>/dev/null) || {
    echo "could not decode stored token" >&2
    return 1
  }
  if [ "${blob:0:3}" != $'v10' ]; then
    echo "unrecognised encrypted token" >&2
    return 1
  fi

  key_hex=$("$openssl_bin" kdf -keylen 16 -kdfopt digest:SHA1 -kdfopt "pass:$pass" \
    -kdfopt salt:saltysalt -kdfopt iter:1003 PBKDF2 2>/dev/null | xxd -p -c 32) || {
    echo "token decryption failed" >&2
    return 1
  }

  ct_file=$(mktemp)
  dec_file=$(mktemp)
  trap 'rm -f "$ct_file" "$dec_file"' RETURN
  printf '%s' "${blob:3}" | base64 >"$ct_file"
  if ! "$openssl_bin" enc -d -aes-128-cbc -K "$key_hex" \
      -iv 20202020202020202020202020202020 -base64 -in "$ct_file" -out "$dec_file" 2>/dev/null; then
    echo "token decryption failed" >&2
    return 1
  fi
  tr -d '\0' <"$dec_file"
  return 0
}

_cookie_for() { # jwt
  local jwt=$1 claims user_id
  claims=$(_jwt_claims "$jwt") || return 1
  user_id=$(printf '%s' "$claims" | jq -r '.sub // "" | split("|") | last')
  [ -n "$user_id" ] || return 1
  printf 'WorkosCursorSessionToken=%s%%3A%%3A%s' "$user_id" "$jwt"
}

_check_expiry() { # jwt
  local jwt=$1 exp claims
  claims=$(_jwt_claims "$jwt") || return 1
  exp=$(printf '%s' "$claims" | jq -r '.exp // empty')
  if [ -n "$exp" ] && [ "$exp" -le "$now" ]; then
    echo "Cursor session token expired" >&2
    exit 2
  fi
}

if ! openssl_bin=$(find_openssl); then
  echo "openssl with kdf not found" >&2
  exit 3
fi

stored=$(_read_stored_token "$state_db")
if [ -z "$stored" ]; then
  echo "no Cursor sign-in" >&2
  exit 2
fi

decrypt_rc=0
jwt=$(_decrypt_token "$stored" "$openssl_bin") || decrypt_rc=$?
if [ "$decrypt_rc" -eq 3 ]; then
  exit 3
fi
if [ -z "$jwt" ] || [ "${jwt:0:3}" != "eyJ" ]; then
  echo "no Cursor sign-in" >&2
  exit 2
fi

_check_expiry "$jwt"
cookie=$(_cookie_for "$jwt") || {
  echo "no Cursor sign-in" >&2
  exit 2
}

body=$(mktemp) hdr=$(mktemp)
trap 'rm -f "$body" "$hdr"' EXIT

sand_http=$(curl -sS --max-time 15 -X POST \
  -H 'User-Agent: tmux-ai-usage' \
  -H 'Accept: application/json' \
  -H "Cookie: $cookie" \
  -H 'Origin: https://cursor.com' \
  -H 'Content-Type: application/json' \
  -D "$hdr" -o "$body" -w '%{http_code}' \
  -d '{}' \
  'https://cursor.com/api/dashboard/get-sand-usage-status')

case $sand_http in
  2*) ;;
  401|403)
    echo "HTTP $sand_http from get-sand-usage-status" >&2
    exit 2 ;;
  429)
    retry_after=$(awk -F': ' 'tolower($1)=="retry-after" {gsub(/\r/,""); print $2; exit}' "$hdr")
    echo "HTTP 429 from get-sand-usage-status" >&2
    [ -n "$retry_after" ] && echo "retry_after=$retry_after" >&2
    exit 1 ;;
  *)
    echo "HTTP $sand_http from get-sand-usage-status" >&2
    exit 1 ;;
esac

sand=$(cat "$body")
if ! jq -e . >/dev/null 2>&1 <<<"$sand"; then
  echo "invalid JSON from get-sand-usage-status" >&2
  exit 1
fi

summary_json=null
if [ "$(jq -r '.isUnified // false' <<<"$sand")" != true ]; then
  : >"$body"
  : >"$hdr"
  sum_http=$(curl -sS --max-time 15 \
    -H 'User-Agent: tmux-ai-usage' \
    -H 'Accept: application/json' \
    -H "Cookie: $cookie" \
    -D "$hdr" -o "$body" -w '%{http_code}' \
  'https://cursor.com/api/usage-summary')
  case $sum_http in
    2*) summary_json=$(cat "$body") ;;
    401|403)
      echo "HTTP $sum_http from usage-summary" >&2
      exit 2 ;;
    429)
      retry_after=$(awk -F': ' 'tolower($1)=="retry-after" {gsub(/\r/,""); print $2; exit}' "$hdr")
      echo "HTTP 429 from usage-summary" >&2
      [ -n "$retry_after" ] && echo "retry_after=$retry_after" >&2
      exit 1 ;;
    *)
      echo "HTTP $sum_http from usage-summary" >&2
      exit 1
    ;;
  esac
fi

jq -n --argjson sand "$sand" --argjson summary "$summary_json" '{sand: $sand, summary: $summary}'