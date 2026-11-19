# Where can Claude plan-quota usage be read from?

Resolves [#2](https://github.com/isenthamiz/tmux-ai-usage/issues/2). Researched 2026-11-19 against Claude Code 2.1.328 on macOS (Pro plan). Terms follow [GLOSSARY.md](../GLOSSARY.md).

## Answer

Claude reports usage for two **quota windows** to a personal Pro/Max account: a rolling 5-hour window (`five_hour`, also called "session") and a weekly window (`seven_day`, "weekly_all"). Some accounts or plans also get model-scoped weekly windows (`seven_day_opus`, `seven_day_sonnet`, and per-model rows in `limits[]`/`model_scoped`). All of them come from one server-side source, which Claude Code exposes in four ways:

| # | Source | Documented? | Needs a running Claude Code session? | Touches credentials? | Network cost per read |
|---|---|---|---|---|---|
| A | Status line JSON `rate_limits` | Yes | Yes. It only updates after API responses | No | None (comes from inference response headers) |
| B | `claude -p` `get_usage` control request (stream-json) | No. The schema in the binary marks it "Experimental" | No. It spawns its own short-lived process | No (Claude Code handles them) | One `GET /api/oauth/usage` plus process startup (about 2 to 4 s) |
| C | `~/.claude.json` → `.cachedUsageUtilization` | No (internal cache) | Something must have fetched recently | No | None (file read) |
| D | `GET https://api.anthropic.com/api/oauth/usage` with the keychain OAuth token | No, and the legal terms rule it out for third-party tools | No | **Yes**: reads the OAuth bearer from the keychain | One HTTPS request |

**Recommendation:** use **B** (`get_usage` via `claude -p`) as the polling source. Add **A** as an optional zero-cost fast path: a status-line tee that writes the latest `rate_limits` to a cache file while a session is active. Do **not** use D. Use C only as an opportunistic fallback, if at all. Details and caveats follow.

---

## A. Status line payload: `rate_limits` (documented)

Source: [Customize your status line](https://code.claude.com/docs/en/statusline).

- **Fields:**
  - `rate_limits.five_hour.used_percentage` and `rate_limits.seven_day.used_percentage`: 0 to 100.
  - `rate_limits.five_hour.resets_at` and `rate_limits.seven_day.resets_at`: Unix epoch **seconds**.
  - `rate_limits.spend_limit.*` exists only behind a Claude apps gateway, so it does not apply here.
  - Model-specific windows are **not** in this payload.
- **Presence:** "appears only for claude.ai Pro, Max, and Ultra subscribers … only after the first API response in the session. Each window … may be independently absent, and Claude Code drops a window once its `resets_at` time passes." The docs recommend `jq -r '.rate_limits.five_hour.used_percentage // empty'`.
- **Freshness:** the values are carried on inference response headers. The binary reads `anthropic-ratelimit-unified-5h-utilization`, `-5h-reset`, `-7d-utilization`, `-7d-reset`, `-status`, and related headers. So the numbers are current as of the last model response in *that* session. The status-line command runs on events (debounced 300 ms), on an optional `refreshInterval` timer, and when a window's `resets_at` passes. In an idle session, or when usage happens elsewhere (claude.ai, another machine), the values go stale. anthropics/claude-code#99231 calls this "push-only".
- **Precision:** the headers are floored to a whole percent. `/api/oauth/usage` rounds to nearest, so the two can differ by 1 point (anthropics/claude-code#105890).
- **Auth/cost:** none. It is just stdin to a script Claude Code already runs.
- **How tmux would use it:** configure (or wrap) `statusLine.command` to `tee` the stdin JSON's `.rate_limits` plus a timestamp into a cache file such as `~/.cache/tmux-ai-usage/claude.json`. tmux reads that file. Downsides:
  - It edits the user's Claude Code settings and has to chain to any existing status line.
  - Nothing updates while no CLI session is active.
  - The VS Code extension does not run `statusLine` (anthropics/claude-code#107376).

## B. `get_usage` control request via `claude -p` (undocumented, experimental, no credential handling)

Source: the Zod schema inside the Claude Code 2.1.328 binary, verified locally. It is not in the public Agent SDK reference pages (checked [TypeScript](https://code.claude.com/docs/en/agent-sdk/typescript) and [Python](https://code.claude.com/docs/en/agent-sdk/python)).

The schema's own description says: *"Requests the structured /usage data: session cost/usage totals plus claude.ai plan rate-limit utilization when available. Experimental — the response shape may change."* Its `skip_behaviors` option is described as being *"For callers that need only the plan rate limits, such as a usage meter"*.

Working invocation (bash + jq, about 3.9 s wall time here, 0 model tokens, `total_cost_usd: 0`):

```sh
{ echo '{"type":"control_request","request_id":"u","request":{"subtype":"get_usage","skip_behaviors":true}}'; sleep 3; } \
  | claude -p --no-session-persistence --input-format stream-json --output-format stream-json --verbose 2>/dev/null \
  | jq -c 'select(.type=="control_response" and .response.request_id=="u") | .response.response'
```

(The `sleep` keeps stdin open until the response arrives. A real implementation should read until the matching `control_response` arrives and then close stdin, rather than sleeping a fixed time.)

- **Fields** (observed response, Pro plan):
  - `subscription_type` (`"pro"`, `"max"`, …).
  - `rate_limits_available` (bool).
  - `rate_limits.five_hour` and `rate_limits.seven_day`: `{utilization: 0-100, resets_at: ISO-8601 string}`.
  - `rate_limits.seven_day_opus`, `seven_day_sonnet`, `seven_day_oauth_apps`: same shape, or `null`.
  - `rate_limits.limits[]`: `{kind: "session"|"weekly_all"|…, group, percent, resets_at, severity, is_active, scope}`. This is the server's generic list and the best place to discover model-scoped windows.
  - `rate_limits.model_scoped[]`: per-model weekly windows, `{display_name, utilization, resets_at}`.
  - `extra_usage` / `spend`: usage-credit info, which is not plan quota.
  - `seven_day_breakdown`: split between Claude Code, Chats, and Cowork.
  - Many opaque codename keys that are `null`.
- **Auth:** Claude Code reads its own keychain item and refreshes the token itself. The plugin never sees a token. Not available under `--bare`, which skips keychain reads.
- **Freshness:** live server value at call time. It covers usage from every surface (claude.ai, other machines), unlike A.
- **Polling cost and rate limits:**
  - Each call is one `GET /api/oauth/usage` plus a Claude Code process start. The process start also performs normal startup work and runs the user's `SessionStart` hooks.
  - The endpoint is rate limited. The [costs docs](https://code.claude.com/docs/en/costs#when-the-usage-request-fails) say: "most often because the usage endpoint is rate limited". No numeric limit is published.
  - In the binary, a 429 or 403 is remembered per bearer token for `Retry-After`, or 5 min when that header is absent, capped at 1 h.
  - Claude Code itself throttles its on-disk cache of this data to one write per 60 s.
  - Polling every 60 s or slower is reasonable. Anything faster is unjustified. On a rate-limit error, back off and show stale data with its age.
- **Gotchas:**
  - Use `--no-session-persistence`. Without it, each run leaves a transcript under `~/.claude/projects/`.
  - `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` (often pushed by org managed settings) makes it return `rate_limits: null` without a request (anthropics/claude-code#108146).
  - The response shape is explicitly unstable, so parse defensively with `// empty`.
- **Human-readable alternative:** `claude -p "/usage"` (about 2 s) prints `Current session: 28% used · resets Nov 19 at 11:59am (Europe/Dublin)` and `Current week (all models): …`. The [SDK docs](https://code.claude.com/docs/en/agent-sdk/typescript) confirm that slash-command output comes back as assistant text. That output is localised prose, so it is too fragile to parse. Prefer `get_usage`.

## C. `~/.claude.json` → `.cachedUsageUtilization` (undocumented cache)

- **Shape:** `{accountUuid, fetchedAtMs, utilization}`. `utilization` is the same object as B's `rate_limits` (`five_hour.utilization`, `five_hour.resets_at` as ISO, …).
- **Writes:** Claude Code writes it whenever it fetches `/api/oauth/usage`. That happens through `/usage`, B, and some other in-app fetches. Writes are throttled to once per 60 s (`zt = 60000` in the binary). Claude Code treats entries older than 1 h as unusable (`hi = 3600000`). This is the "Showing last-known usage" snapshot described in the costs docs.
- **Freshness:** opportunistic. During this research the value stayed at the session-start fetch for 12+ minutes of active work. It only moved when `/usage`/`get_usage` ran. Not a reliable sole source.
- **Auth/cost:** a file read. `~/.claude.json` also holds `oauthAccount` with personal data (email and name), so the plugin should read only `.cachedUsageUtilization` with jq. It must never write to the file, because Claude Code rewrites it frequently and keeps backups.
- **Use:** a zero-cost fallback when B is rate-limited, and a cheap way to show *something* at tmux start. Check `fetchedAtMs` and `accountUuid`.

## D. Direct `GET /api/oauth/usage` with the stored OAuth token (not recommended)

- **What the binary does:**
  - Endpoint: `https://api.anthropic.com/api/oauth/usage`. Variants such as `?skip_spend=1` also exist.
  - Headers: `Authorization: Bearer <accessToken>` and `anthropic-beta: oauth-2025-04-20` (the constant `Fu` used for OAuth calls).
  - Timeout: 5 s.
- **Credential storage on macOS:** a keychain generic-password item with service `Claude Code-credentials` and the macOS username as account. Claude Code reads it with `security find-generic-password -a <user> -w -s "Claude Code-credentials"`. The value is JSON with a `claudeAiOauth` object holding `accessToken`, `refreshToken`, expiry, `subscriptionType`, and `rateLimitTier`. On Linux the fallback is `~/.claude/.credentials.json`, which is not present on this Mac. No secret values were read for this research.
- **Why not:**
  1. The [legal and compliance page](https://code.claude.com/docs/en/legal-and-compliance) says: "developers may not collect, store, or intermediate Claude.ai credentials or session tokens".
  2. The access token expires. Refreshing it from bash would rotate the refresh token underneath Claude Code and could sign the user out. Not refreshing means the bar breaks whenever the token is stale.
  3. It is undocumented and has no compatibility promise. It has the same rate limit as B.
  4. B returns the same data while Claude Code owns the token lifecycle. anthropics/claude-code#99231 (open) asks for an official read-only endpoint precisely because community tools do D today.

## Other candidates ruled out

- **`~/.claude/stats-cache.json`:** local token and message counts per day and model. It is not quota and has no windows or resets.
- **`rate_limit_event` / `SDKRateLimitEvent` in headless stream-json** ([docs](https://code.claude.com/docs/en/agent-sdk/typescript)): only emitted around model requests. Polling it would spend quota.
- **`claude` subcommands:** none exposes usage (`claude --help` in 2.1.328).
- **Admin, Analytics, and Enterprise Analytics APIs:** org-only and token/cost-based, with no 5h/7d windows ([costs docs](https://code.claude.com/docs/en/costs#manage-costs-for-your-organization)).
- **OpenTelemetry:** tokens and cost, not plan quota.

## Implications for the plugin

- Model each window as `{name, used_pct, resets_at_epoch}`. Normalise B/C's ISO `resets_at` and A's epoch seconds to epoch.
- Windows to show: always `five_hour` and `seven_day` when present. Optionally show any `limits[]` entry whose `kind` is model-scoped. Hide a window that is `null` or absent, and treat a passed `resets_at` as 0%.
- Poll B from a background job every 60 s or more, never from tmux's `status-interval` directly, because each call costs about 2 to 4 s. Write the result to a cache file that the tmux segment reads.
- On a 429 or any failure, keep the last good value, mark it stale, and back off for at least 5 minutes.
- Optional: an A-based status-line tee can refresh the cache file for free while a CLI session is active.

## Sources

- Claude Code docs: [statusline](https://code.claude.com/docs/en/statusline), [costs](https://code.claude.com/docs/en/costs), [Agent SDK TypeScript reference](https://code.claude.com/docs/en/agent-sdk/typescript), [legal and compliance](https://code.claude.com/docs/en/legal-and-compliance).
- Claude Code 2.1.328 binary: `~/.local/share/claude/versions/2.1.328`, read with `strings`. Relevant pieces: `get_usage` request/response schema, `fetchUtilization`, `cachedUsageUtilization` read/write, backoff constants, and `anthropic-ratelimit-unified-*` header names.
- Local verification, read-only: `claude -p "/usage"`, the `get_usage` run above, `~/.claude.json` key names, and keychain item metadata (no values).
- anthropics/claude-code issues [#99231](https://github.com/anthropics/claude-code/issues/99231), [#105890](https://github.com/anthropics/claude-code/issues/105890), [#108146](https://github.com/anthropics/claude-code/issues/108146), [#107376](https://github.com/anthropics/claude-code/issues/107376).
