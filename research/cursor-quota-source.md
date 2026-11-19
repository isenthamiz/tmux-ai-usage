# Where can Cursor plan-quota usage be read from?

Research for issue #4. Researched 2026-11-19 against Cursor 3.30.14 on macOS.

## Answer

**There is no documented, per-user API for Cursor plan-quota usage.** The viable source is the same
undocumented dashboard API that the cursor.com web dashboard and third-party menu-bar tools use,
authenticated with the Cursor desktop app's own session token read from its local SQLite state DB.
Since Cursor 3.27 that token is encrypted at rest with a Keychain-held key, so a Bash reader needs
`sqlite3` + `security` + OpenSSL 3 (Homebrew) + `jq`.

Recommended source: `GET https://cursor.com/api/usage-summary` (cookie auth built from the app token).
For accounts on The X Subscription (weekly pool), also read
`POST https://cursor.com/api/dashboard/get-sand-usage-status`.

**Not verified live.** Calling either endpoint with the stored token was blocked by the local
permission policy during this research, so response shapes below come from Cursor's own client bundle
and from an open-source client (CodexBar), not from an observed response. The implementation ticket
should start with a one-off live check.

## Cursor's usage model today (it has changed twice)

Cursor now has three plan generations, and the quota window differs by generation:

| Generation | Plans | Quota windows | Unit |
|---|---|---|---|
| Request-based (oldest legacy) | early Pro etc. | monthly, with billing cycle | request counts |
| Legacy usage-based | Hobby, Start, Pro, Pro+, Ultra, Teams Standard/Premium seats | **two monthly pools**: "Cursor Models" and "Other Models", reset with billing cycle | dollars (cents) of API-priced usage |
| The X Subscription (current, sold since the Cursor/Grok/X bundle) | Free, Plus, Premium, Super, Ultra, Teams seats | **one weekly pool** for Cursor models, shared with Grok; third-party models paid from prepaid credit (not a quota) | percent of pool |

Sources:
- "every paid plan includes one weekly pool of usage for Cursor models ... shared across Cursor, Grok Bot, and the Grok apps"; legacy plans: "included usage is split into two monthly pools" — [Usage and limits](https://cursor.com/help/models-and-usage/usage-limits.md)
- Legacy: "usage resets monthly with your billing cycle. The reset date is shown on the Spending tab." X Subscription: "your included pool refreshes weekly. The next reset date is shown under Usage at grok.com/dashboard." — same page
- Legacy vs. new comparison table and "Request-based plans, where usage was counted in requests rather than tokens, are an older generation still" — [Legacy Cursor plans](https://cursor.com/docs/account/pricing/legacy-cursor-plans.md)
- "Your remaining usage and next reset date are shown in your editor settings and under Usage at grok.com/dashboard" — [Models and pricing](https://cursor.com/docs/models-and-pricing.md)
- Switching to The X Subscription is optional and permanent; "A new billing cycle starts on the day you switch" — [What is The X Subscription?](https://cursor.com/help/the-x-subscription/overview.md)

Consequence for the plugin: a Cursor provider has either **two monthly usage bars** (legacy) or
**one weekly usage bar** (X Subscription), and the reader must detect which at runtime.

On this machine `cursorAuth/stripeMembershipType` is `premium` and `stripeSubscriptionStatus` is
`active`. "Premium" exists in both the X Subscription tiers and legacy Teams seat types, so the plan
generation cannot be inferred from that key alone; use the API's `isUnified` flag (below).

## Sources considered

### 1. Documented Cursor APIs (`api.cursor.com`) — not viable

The [APIs overview](https://cursor.com/docs/api.md) lists Admin, Analytics, AI Code Tracking and
Bugbot APIs as **"Enterprise teams"** only, authenticated with a team admin key (`crsr_...`, scope
`admin:*`). The Cloud Agents API is available more widely but only exposes per-agent usage. None
gives an individual subscriber's quota percentage or reset. Documented rate limits: 20 req/min default.
Not usable for an individual Pro/Premium subscriber.

### 2. Cursor CLI (`agent`, formerly `cursor-agent`) — not viable

The [CLI docs](https://cursor.com/docs/cli/overview.md) and
[slash command reference](https://cursor.com/docs/cli/reference/slash-commands.md) have no usage or
quota command. `agent status` reports only authentication state
([Authentication](https://cursor.com/docs/cli/reference/authentication.md)). Not installed on this
machine. Its login token could serve as an alternative credential (CodexBar uses it on Linux at
`~/.config/cursor/auth.json`), but it is not needed when the desktop app is signed in.

### 3. Local app storage — holds the credential, not the usage

`~/Library/Application Support/Cursor/User/globalStorage/state.vscdb` (SQLite, table `ItemTable`,
~320 MB here, WAL mode). Relevant keys (names only):

| Key | Content |
|---|---|
| `cursorAuth/accessToken` | session token; **encrypted**, value starts with `cursor-safe-storage:v1:` |
| `cursorAuth/refreshToken` | refresh token; also encrypted |
| `cursorAuth/stripeMembershipType` | plan name, plaintext (e.g. `premium`) |
| `cursorAuth/stripeSubscriptionStatus` | plaintext (e.g. `active`) |
| `cursorAuth/storedServerBackendUrl` | `https://api2.cursor.sh` |
| `cursorAuth/cachedEmail`, `cachedScopedProfile`, `cachedSignUpType` | profile cache |

No key caches usage percentage, limits or reset date (searched `ItemTable` and `cursorDiskKV` for
usage/quota/limit/spend). `~/.cursor/` holds CLI config and agent state, also no usage.

Token decryption (observed on this machine: prefix present, payload is `v10` + AES blocks; scheme from
[CodexBar `CursorAppAuth.swift`](https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/Providers/Cursor/CursorAppAuth.swift)
and [`ChromiumSafeStorage.swift`](https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/ChromiumSafeStorage.swift)):

1. Strip `cursor-safe-storage:v1:`, base64-decode, strip the 3-byte `v10` prefix.
2. Password: Keychain generic password, service `Cursor Safe Storage`, account `Cursor Key`
   (legacy account `Cursor`). Present on this machine. `security find-generic-password -w` will
   trigger a one-time macOS Keychain prompt; "Always Allow" makes later polls silent.
3. Key = PBKDF2-HMAC-SHA1(password, salt `saltysalt`, 1003 iterations, 16 bytes);
   AES-128-CBC, IV = 16 spaces (standard Chromium/Electron OSCrypt `v10`).
4. Plaintext is a JWT; its `sub` claim is `<provider>|<userId>`, needed for the cookie below.

Bash note: macOS `/usr/bin/openssl` is LibreSSL 3.3.6 and lacks `openssl kdf`; Homebrew OpenSSL 3
(present here at `/opt/homebrew/bin/openssl`) has it. Older Cursor builds (<3.27) stored a plain JWT,
so the reader should accept both forms.

The token is never refreshed by a passive reader; when it expires the app refreshes it on next use.
A reader should skip polling when the JWT `exp` has passed and show a stale/unauthenticated state.

### 4. cursor.com dashboard API (undocumented, cookie auth) — **recommended**

Used by the cursor.com dashboard web app and by
[CodexBar's Cursor provider](https://github.com/steipete/CodexBar/blob/main/docs/cursor.md)
(field definitions in
[`CursorStatusProbe.swift`](https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/Providers/Cursor/CursorStatusProbe.swift)
and [`CursorSandUsage.swift`](https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/Providers/Cursor/CursorSandUsage.swift)).

Auth: header `Cookie: WorkosCursorSessionToken=<userId>%3A%3A<accessToken JWT>`, built from the
decrypted app token (CodexBar `cookieHeader()`). A browser's `WorkosCursorSessionToken` cookie works
too. API keys (`crsr_...`) do not.

**`GET https://cursor.com/api/usage-summary`** — legacy monthly pools + billing cycle:

- `billingCycleStart`, `billingCycleEnd` (ISO strings) → reset = `billingCycleEnd`
- `membershipType`, `limitType` (`user` / team), `isUnlimited`
- `individualUsage.plan`: `enabled`, `used`, `limit`, `remaining` (cents), `breakdown{included,bonus,total}`,
  `totalPercentUsed`, `autoPercentUsed` (Cursor Models pool), `apiPercentUsed` (Other Models pool)
- `individualUsage.onDemand`: `enabled`, `used`, `limit`, `remaining` (cents) — this is spend, out of scope
- `teamUsage.onDemand`, `teamUsage.pooled` — team plans only
- CodexBar notes "the legacy usage summary can report zero after account unification", so for X
  Subscription accounts it is not the quota source.

**`POST https://cursor.com/api/dashboard/get-sand-usage-status`** (requires `Origin: https://cursor.com`)
— the X Subscription weekly pool (and Grok Bot allowance):

- `usagePercent`, `currentPeriodStart`, `nextResetTimestampUtc` → reset
- `isUnified` — `true` marks The X Subscription shared weekly pool; this is the runtime plan-generation switch
- `hasAvailableUsage`, `includedLimitZero`, `hasNonZeroIncludedLimit`, `sandTrialExpiresAt`

**`GET https://cursor.com/api/usage?user=<userId>`** — oldest request-based plans only: per-model
`numRequests`, `maxRequestUsage`, plus `startOfMonth`. Only needed if a request-based plan still exists.

Freshness: the docs describe the Spending tab as showing "real-time usage"
([Usage and limits](https://cursor.com/help/models-and-usage/usage-limits.md)); 60 s staleness is well within this.
Rate limits / cost: **none published** for these endpoints. Cost per poll is one or two small HTTPS
JSON requests. A 60 s cadence is in line with what menu-bar tools do, but should back off on 429/5xx.
Stability: undocumented; field names have already shifted once (request counts → cents → weekly percent).
A forum thread reports a sibling endpoint returning "Usage summary is not enabled" for some accounts
([forum](https://forum.cursor.com/t/i-cant-get-my-usage-info/155469)), so expect breakage risk.

### 5. Editor's own RPC on `api2.cursor.sh` (undocumented, bearer auth) — viable alternative, unverified

The Cursor editor reads usage for its settings page over Connect RPC at the backend URL stored in
`cursorAuth/storedServerBackendUrl`. Message definitions extracted read-only from
`/Applications/Cursor.app/Contents/Resources/app/out/vs/workbench/workbench.desktop.main.js` (3.30.14):

- `aiserver.v1.DashboardService/GetCurrentPeriodUsage` → `billing_cycle_start`, `billing_cycle_end`
  (int64), `plan_usage{total_spend, included_spend, remaining, limit, auto_percent_used,
  api_percent_used, total_percent_used, ...}`, `spend_limit_usage`, `enabled`, `display_message`
- `aiserver.v1.DashboardService/GetXaiUserUsageSnapshot` → `current_period_start_ms`,
  `current_period_end_ms`, `usage_percent`, `product_usage[]{product, usage_percent}`,
  `prepaid_balance_cents`

These are what the editor itself uses and take `Authorization: Bearer <token>` directly (no cookie
construction), and `GetXaiUserUsageSnapshot` maps one-to-one onto a weekly usage bar. Whether the
server accepts the Connect JSON codec (`Content-Type: application/json`) for these methods was not
checked. Same stability and rate-limit caveats as source 4, plus protobuf field names in a minified
bundle are even less of a contract.

### Not viable

- **grok.com/dashboard**: shows the X Subscription weekly pool, but has no documented API and would need
  a separate xAI session.
- **Scraping the editor UI / logs**: no usage values found in local storage; nothing to scrape offline.

## Recommendation

Implement the Cursor provider as: `sqlite3 -readonly` the app's `cursorAuth/accessToken` → decrypt with
the `Cursor Safe Storage` Keychain key via Homebrew `openssl` (accept plain JWTs too) → build the
`WorkosCursorSessionToken` cookie → call `get-sand-usage-status`; if `isUnified` is true, render one
weekly bar from `usagePercent` / `nextResetTimestampUtc`; otherwise call `usage-summary` and render the
legacy monthly bars from `autoPercentUsed` (Cursor Models) and `apiPercentUsed` (Other Models), or
`totalPercentUsed` for a single bar, resetting at `billingCycleEnd`. Poll at most once per 60 s, cache
the last good reading, and treat 401/403 or an expired JWT as "signed out".

Keep the `api2.cursor.sh` RPCs (source 5) as the fallback if the cursor.com routes change. Before
building, run a one-off live check of both endpoints with the real token (printing field names only)
to confirm shapes and which generation this account is on.

Dependencies to state in the plugin README: Cursor desktop app signed in, `sqlite3`, `jq`, `curl`,
Homebrew `openssl@3`, and a one-time Keychain "Always Allow" for `Cursor Safe Storage`.
