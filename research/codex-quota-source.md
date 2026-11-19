# Where can Codex plan-quota usage be read from?

Resolves #3. Researched 2026-11-19.

## Answer

Poll the ChatGPT backend endpoint that Codex itself uses,
`GET https://chatgpt.com/backend-api/wham/usage`. Authenticate with the
ChatGPT access token and account ID that Codex keeps in `~/.codex/auth.json`.
It returns usage and reset time for every quota window, it is current even
when no Codex session is running, and the Codex TUI polls the same endpoint
every 60 s. The endpoint is undocumented, so the plugin has to tolerate
changes to its shape. The session rollout files under `~/.codex/sessions`
are the fallback: they need no network but are only as fresh as the last
CLI turn.

## Sources examined

- `openai/codex` source at commit `b9559ff` (2026-11-19), mainly `codex-rs/`.
- Public docs: <https://learn.chatgpt.com/docs/pricing>, which is where
  `developers.openai.com/codex/pricing` redirects.
- This machine, read-only: `~/.codex/` (Codex desktop app installed, no
  `codex` CLI on PATH, signed in with a Plus plan). No secret values were
  recorded here.

## Source 1: `GET /backend-api/wham/usage` (recommended)

**What it is.** The backend "rate-limit status" call. The URL is built in
`codex-rs/backend-client/src/client/rate_limit_resets.rs`
(`rate_limit_status_url`). It is `{base}/wham/usage` when the base URL
contains `/backend-api`, and `{base}/api/codex/usage` otherwise (`PathStyle`
in `codex-rs/backend-client/src/client.rs`). The default base is
`https://chatgpt.com/backend-api/`
(`codex-rs/model-provider/src/chatgpt_base_url.rs`), and users can override
it with `chatgpt_base_url` in `config.toml`.

**Auth.** The request needs these headers (`Client::headers` in `client.rs`):
- `Authorization: Bearer <tokens.access_token>`
- `chatgpt-account-id: <tokens.account_id>` (`CHATGPT_ACCOUNT_ID_HEADER` in
  `codex-rs/http-client/src/openai_headers.rs`)
- `User-Agent` (Codex sends `codex-cli` when it has no other value).

Both values are in `~/.codex/auth.json` under `.tokens`, with
`auth_mode: "chatgpt"`. They live there only while
`cli_auth_credentials_store` resolves to file storage; with the keyring
backend they are in the macOS Keychain instead (`core/src/config/auth_keyring.rs`).
`CODEX_HOME` moves the whole directory. The access token on this machine is a
JWT that expires 10 days after it was issued (the `exp` minus `iat` claims).
Codex refreshes it and rotates the refresh token
(`codex-rs/login/src/oauth_session*.rs`). The plugin should therefore
**only read** `auth.json` and never refresh the token itself, because a
second refresher could invalidate Codex's rotated refresh token. If the
token has expired (HTTP 401), show a "stale / open Codex" state.

**Fields.** These come from the generated OpenAPI models in
`codex-rs/codex-backend-openapi-models/src/models/` and from a live call on
this machine (HTTP 200, about 1 s):

```json
{
  "plan_type": "plus",
  "rate_limit": {
    "allowed": true, "limit_reached": false,
    "primary_window":   { "used_percent": 66, "limit_window_seconds": 604800,
                          "reset_after_seconds": 177914, "reset_at": 1795252665 },
    "secondary_window": null
  },
  "additional_rate_limits": null,
  "credits": { "has_credits": true, "unlimited": false, "balance": "…" },
  "spend_control": { "reached": false, "individual_limit": null },
  "rate_limit_reached_type": null
}
```

- Each window has `used_percent` (an integer here), `limit_window_seconds`,
  `reset_after_seconds` and `reset_at` (Unix seconds). That is everything a
  usage bar needs.
- `primary_window` and `secondary_window` are both nullable. On this Plus
  account in November 2026, only one weekly window (604800 s) is returned.
  The docs say Plus has a five-hour limit and that "Pro plans currently have
  no five-hour limit". **Do not hard-code which window is 5 h and which is
  weekly.** Label each window from `limit_window_seconds`.
- `additional_rate_limits[]` holds per-model or per-feature buckets
  (`metered_feature`, `limit_name`, `rate_limit.{primary,secondary}_window`).
  Codex maps these to extra snapshots
  (`make_additional_rate_limit_snapshot`, `client.rs`).

**Documented?** No. The public docs point users only to the dashboard at
chatgpt.com/codex/settings/usage and to `/status` in the CLI. The schema is
an internal "codex-backend" OpenAPI document (v0.0.1) that has been
code-generated into the open-source repo. It can change without notice.

**Freshness.** This is the server's live value, independent of whether any
Codex client is running. On this machine it read 66 %, while the newest
rollout file (2026-11-14) said 56 % for the same window, because later usage
came from a client that did not write rollouts.

**Polling cost.** One small GET. No rate limit is published. The official TUI
polls this same data (through `account/rateLimits/read`, which calls
`get_rate_limits_*`) every 60 s, and every 30, 15 or 5 s once usage reaches
75, 90 or 99 % (`rate_limit_refresh_interval` in
`codex-rs/tui/src/chatwidget/rate_limits.rs`). Polling every 60 s is
therefore in line with first-party behaviour.

**Bash + jq sketch.**
```sh
auth="${CODEX_HOME:-$HOME/.codex}/auth.json"
curl -fsS --max-time 10 https://chatgpt.com/backend-api/wham/usage \
  -H "Authorization: Bearer $(jq -r .tokens.access_token "$auth")" \
  -H "chatgpt-account-id: $(jq -r .tokens.account_id "$auth")" \
  -H 'User-Agent: codex-cli' |
jq -r '.rate_limit | [.primary_window, .secondary_window][] | select(.)
       | "\(.limit_window_seconds) \(.used_percent) \(.reset_at)"'
```
The token passes through a `curl` argument and is visible in `ps`. Passing
headers with `-H @file` or `--config -` from stdin avoids that.

## Source 2: session rollout files (offline fallback)

**What it is.** Every turn, Codex records the rate-limit headers from the
model response, or a `codex.rate_limits` websocket event, as an `event_msg`
of type `token_count` in
`$CODEX_HOME/sessions/YYYY/MM/DD/rollout-*.jsonl` (and `archived_sessions/`).
The parsing is in `codex-rs/codex-api/src/rate_limits.rs` (headers
`x-codex-primary-used-percent`, `-window-minutes`, `-reset-at`, the same for
`secondary`, plus `x-codex-credits-*`). The event shape is `TokenCountEvent`
/ `RateLimitSnapshot` / `RateLimitWindow` in `codex-rs/protocol/src/protocol.rs`.

**Fields.** The fields are under `.payload.rate_limits`: `limit_id`
(`"codex"`), `primary` and `secondary`, each
`{used_percent (float, may exceed 100), window_minutes, resets_at (Unix s)}`,
plus `credits`, `plan_type` and `rate_limit_reached_type`. This machine has
2,681 such events, all with `limit_id: "codex"`, `primary.window_minutes:
10080` and `secondary: null`. A few events have `rate_limits: null`, so
skip those.

**Auth.** None. These are local files.

**Documented?** No. The rollout format is internal; this repo has a
`rollout-migrations/` directory, which shows that the format changes.

**Freshness.** Values are written only while a Codex CLI or TUI session is
taking turns. They go stale between sessions, and stay stale when usage
happens in clients that do not write rollouts there (web, cloud tasks, the
desktop app on this machine). They are also unbounded in age: the reader
must compare `resets_at` with the current time and treat a past reset as 0 %.

**Polling cost.** Only filesystem cost: find the newest rollout file and
`grep '"rate_limits"' | tail -1`.

## Source 3: `codex app-server` JSON-RPC `account/rateLimits/read`

The method is `account/rateLimits/read`, with the notification
`account/rateLimits/updated` (`codex-rs/app-server-protocol/src/protocol/common.rs`
and `v2/account.rs`). It returns `rateLimits`, `rateLimitsByLimitId`,
`ordinaryUsageAllowed` and others. Internally it calls the same
`/wham/usage` endpoint and handles token refresh correctly. This is the most
"supported" surface, because its TypeScript schema is exported. However,
using it means installing the `codex` CLI (it is not on PATH here) and
spawning a long-lived stdio JSON-RPC process with an initialize handshake,
which is awkward from a tmux `#()` Bash script. It also is not described in
`codex-rs/app-server/README.md`. Keep it as an option if token expiry
becomes a problem.

## Not viable

- **`/status`** is an interactive TUI slash command with no machine-readable
  output and no non-interactive form.
- **The usage dashboard** (chatgpt.com/codex/settings/usage) is a browser
  page with no documented API.
- **Enterprise Analytics and Compliance APIs** are workspace-admin APIs and
  do not apply to a personal ChatGPT plan.

## Recommendation

1. Primary: poll `GET https://chatgpt.com/backend-api/wham/usage` at most
   every 60 s, cache the result, and render one usage bar per non-null
   window under `.rate_limit`. Label windows from `limit_window_seconds`,
   use `used_percent` for the bar, and use `reset_at` for time to reset. Read
   credentials from `$CODEX_HOME/auth.json` read-only, honour
   `chatgpt_base_url` if it is set, and never refresh tokens.
2. Fallback, on network error, 401, or keyring-only auth: use the newest
   `token_count` event in the rollout files. Mark it as stale, and treat
   windows whose `resets_at` has passed as reset.
3. Because the endpoint is undocumented, parse it defensively: missing or
   null windows mean "no bar", not an error.
