# tmux-ai-usage v1 spec

A TPM-installable tmux plugin that draws **usage bars** in the status line. Each bar shows how much of a quota window's plan quota has been used, plus the time until it resets, for Claude, Codex and Cursor. It is macOS-only in v1.

This file gathers the decisions recorded on the wayfinder map, [Wayfinder: tmux plan-quota usage bars for Claude, Codex, Cursor](https://github.com/isenthamiz/tmux-ai-usage/issues/1). Each section links the ticket that holds the full reasoning. Terms (provider, plan quota, quota window, usage snapshot, snapshot status, window label, stale, pending) are defined in [`GLOSSARY.md`](GLOSSARY.md).

## Scope

**In scope:** plan quota for one account per provider (Claude, Codex, Cursor), configured only through `set -g @…` tmux options, on macOS. Readings may be up to about 60 s old.

**Out of scope:**
- spend or budget tracking
- how full a session's context window is
- multiple accounts per provider
- a separate config file
- Linux

## Architecture

From [Bash + jq, or a compiled helper?](https://github.com/isenthamiz/tmux-ai-usage/issues/5) and [How is the plugin laid out and loaded?](https://github.com/isenthamiz/tmux-ai-usage/issues/14).

- **bash + `jq`**, with no build step. The bash must be compatible with macOS's `/bin/bash` 3.2.
- **Stale-while-revalidate, no daemon.** The status line only reads cached usage snapshots. When a snapshot's TTL has passed and its `retry_at` has passed, the renderer starts a detached, lock-guarded refresh and returns the cached value at once. Refreshing stops whenever tmux isn't running.
- **One fetcher per provider**, split into two parts:
  - **acquire** does all the I/O and prints the raw response.
  - **normalize** is a pure `jq` filter that turns the raw response into a usage snapshot.

### File tree

```
ai_usage.tmux                 # TPM entrypoint: validate options, check jq, rewrite tokens
scripts/
  render.sh <all|claude|codex|cursor>   # the #() target
  refresh.sh <provider>       # lock → dependency check → acquire | normalize → atomic write
  doctor.sh                   # diagnostic (reads snapshots only)
  smoke.sh                    # manual live check (fetches)
  lib/{options,snapshot,format,lock}.sh
  lib/labels.jq               # window label from window length, shared by normalizers
  providers/<provider>/acquire.sh
  providers/<provider>/normalize.jq
test/*.bats  test/fixtures/<provider>/  test/shims/
Makefile  README.md
```

### Entrypoint: `ai_usage.tmux`

- Rewrites tokens in `status-left` and `status-right` the way tmux-cpu does:
  - `#{ai_usage}` → `#($DIR/scripts/render.sh all)`
  - `#{ai_usage_claude|codex|cursor}` → `#($DIR/scripts/render.sh <provider>)`
  - No option values go into the command string.
- Validates every option once (see [Options](#options)). An invalid value falls back to its default, and one `display-message` names the option and the bad value.
- Checks only for `jq`. If `jq` is missing, it shows one `display-message` and rewrites every token to a literal `!jq` in the crit colour.

### Renderer: `render.sh`

- Each run makes one `tmux show-options -g` call and one `jq` call covering every snapshot it draws. Target: under 50 ms.
- Option changes take effect within one `status-interval`, with no reload.
- An option made invalid after load silently falls back to its default; the renderer never prints an option error.
- Starts a refresh as `( refresh.sh <p> </dev/null >/dev/null 2>&1 & )`.
- Index multibyte glyphs through bash arrays. `${s:i:1}` breaks under the C locale that tmux `#()` may run with.

### Refresh: `refresh.sh <provider>`

- **Lock:** an atomic `mkdir` of `$cache/<provider>.lock` holding a `pid` file. A lock is broken if its owner is dead or it's older than 120 s.
- **Dependency checks** run on every refresh. A missing dependency is written as a `missing_dep` snapshot, so installing it fixes the display within one refresh interval.
- **Binary lookup:** `PATH` first, then known install locations.
  - `claude`: `~/.local/bin`, `~/.claude/local`.
  - `openssl`: `/opt/homebrew/opt/openssl@3/bin`, then `/usr/local/opt/openssl@3/bin`. It must pass an `openssl kdf` probe, so LibreSSL `/usr/bin/openssl` counts as missing.
- **Timeouts:** each acquire step has a 20 s hard limit from a bash watchdog, because macOS has no `timeout`. `curl` also gets `--max-time 15`. A timeout is recorded as `error`.
- **Write:** to `$cache/<provider>.json` through a temp file in the same directory, then `mv`. The rename is atomic.

## Usage snapshot

From [Bash + jq, or a compiled helper?](https://github.com/isenthamiz/tmux-ai-usage/issues/5) and [How are stale, missing, and failed readings shown?](https://github.com/isenthamiz/tmux-ai-usage/issues/9).

```json
{
  "provider": "codex",
  "status": "ok | signed_out | missing_dep | bad_shape | error",
  "fetched_at": 0,      // epoch s: when this attempt ran
  "ok_at": 0,           // epoch s: when windows[] was last read successfully
  "retry_at": 0,        // epoch s: no refresh is started before this
  "error": "HTTP 401 from wham/usage",   // short text; never tokens or response bodies
  "windows": [
    { "label": "5h", "used_pct": 81, "resets_at": 0, "window_seconds": 18000 }
  ]
}
```

- A failed fetch keeps the previous good `windows[]` and `ok_at`.
- **Window labels** come from window length: `5h` (18000 s), `wk` (604800 s), `mo` (billing-cycle month). Any other length becomes the compact duration, e.g. `1d`.
  - Model-scoped windows add a suffix: `wk-opus`, `wk-sonnet`.
  - Cursor's legacy pools are `mo-auto` (Cursor Models) and `mo-api` (Other Models).
- **Statuses:**

  | Status | Meaning |
  |---|---|
  | `ok` | The reading succeeded. |
  | `signed_out` | No credential, a 401/403, or an expired token. |
  | `missing_dep` | A required command is missing, or Keychain access was refused. |
  | `bad_shape` | The response didn't match a known shape. |
  | `error` | Transient: network, timeout, 5xx or 429. |

  The renderer also derives two states it never stores: `pending` (no snapshot yet) and `stale` (`now - ok_at > @ai_usage_stale_after`).
- **Back-off (`retry_at`):**
  - **429:** honour `Retry-After`, or wait 5 min if it's absent, capped at 1 h.
  - **`error`:** double the wait each time, starting from the refresh interval and capped at 15 min.
  - **`signed_out` / `missing_dep` / `bad_shape`:** retry at the refresh interval.
  - **`ok`:** resets the back-off.
- **Passed reset:** a window whose `resets_at` is in the past is drawn at 0% with no countdown, and `auto` window selection is recalculated on that basis, until a fresh reading arrives.

## Providers

### Claude

From [Where can Claude plan-quota usage be read from?](https://github.com/isenthamiz/tmux-ai-usage/issues/2). Full findings are in `research/claude-quota-source.md`.

- **Acquire:**
  - Run `claude -p --no-session-persistence --input-format stream-json --output-format stream-json`.
  - Send the control request `{"subtype":"get_usage","skip_behaviors":true}`. It costs 0 model tokens and takes about 2–4 s.
  - Claude Code handles authentication. Never read the `Claude Code-credentials` Keychain token.
- **Fields:**
  - `rate_limits.five_hour` and `rate_limits.seven_day` → `{utilization 0–100, resets_at ISO}`.
  - Model-scoped windows come from `rate_limits.limits[]` / `model_scoped[]`, or from `seven_day_opus` / `seven_day_sonnet`.
  - A window that is `null` or absent is hidden.
  - The control request is experimental, so parse it defensively; a shape mismatch is `bad_shape`.
- **Fallback:**
  - Read only the `.cachedUsageUtilization` key of `~/.claude.json`: `{fetchedAtMs, utilization}`.
  - That key has the same shape as `rate_limits`, and its `ok_at` is `fetchedAtMs`.
  - Never read any other part of that file.

### Codex

From [Where can Codex plan-quota usage be read from?](https://github.com/isenthamiz/tmux-ai-usage/issues/3). Full findings are in `research/codex-quota-source.md`.

- **Acquire:**
  - `GET https://chatgpt.com/backend-api/wham/usage`.
  - Headers: `Authorization: Bearer <tokens.access_token>` and `chatgpt-account-id: <tokens.account_id>`, both from `~/.codex/auth.json`.
  - Read that file only. **Never refresh the token.** A 401 means `signed_out`.
- **Fields:**
  - `.rate_limit.{primary,secondary}_window` → `{used_percent, limit_window_seconds, reset_after_seconds, reset_at}`.
  - Either window may be `null`.
  - Label windows from `limit_window_seconds`; don't hard-code 5h or weekly.
- **Offline fallback:** the newest `token_count` event in `~/.codex/sessions/**/rollout-*.jsonl` (`.payload.rate_limits`). It only updates during CLI turns.

### Cursor

From [Where can Cursor plan-quota usage be read from?](https://github.com/isenthamiz/tmux-ai-usage/issues/4) and [Confirm Cursor's live usage response shape](https://github.com/isenthamiz/tmux-ai-usage/issues/8). Full findings are in `research/cursor-quota-source.md`.

- **Token:**
  - Run `sqlite3 -readonly` on `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb` and read `ItemTable` key `cursorAuth/accessToken`.
  - If the value starts with `cursor-safe-storage:v1:`:
    1. Base64-decode it and strip the 3-byte `v10` prefix.
    2. Get the password from the Keychain with `security find-generic-password -s 'Cursor Safe Storage' -a 'Cursor Key' -w` (legacy account `Cursor`).
    3. Derive the key with PBKDF2-HMAC-SHA1: salt `saltysalt`, 1003 iterations, 16 bytes.
    4. Decrypt with AES-128-CBC, using an IV of 16 spaces.
  - Plain JWTs from Cursor builds before 3.27 are also accepted.
  - An expired JWT `exp` means `signed_out`, and no request is made.
  - macOS asks for Keychain access once; the user chooses "Always Allow".
- **Cookie:** `WorkosCursorSessionToken=<userId>%3A%3A<JWT>`, where `userId` is the last `|` segment of the JWT's `sub`.
- **Acquire, step 1:**
  - `POST https://cursor.com/api/dashboard/get-sand-usage-status` with `Origin: https://cursor.com` and body `{}`.
  - If `isUnified` is true, there is one weekly window: `usagePercent` (an integer, 0–100) and `nextResetTimestampUtc` (ISO, `Z`). The window length comes from `currentPeriodStart`. This was verified live.
- **Acquire, step 2 (only if `isUnified` is false):**
  - `GET https://cursor.com/api/usage-summary`.
  - Legacy pools: `individualUsage.plan.autoPercentUsed` → `mo-auto` and `apiPercentUsed` → `mo-api`, both resetting at `billingCycleEnd` (ISO).
  - This path is unverified live. On unified accounts this endpoint returns all-zero percentages.
- **Ignored:** spend fields such as `onDemand`, `additionalUsageLimit` and `prepaidAvailableCents`.

## Look

From [What should the usage bars look like?](https://github.com/isenthamiz/tmux-ai-usage/issues/6). The rejected variants are on the `prototype/usage-bars` branch.

```
cl wk ▰▰▰▱▱ 67% 3d4h │ cx 5h ▰▰▰▰▱ 81% 47m │ cu wk ▰▰▰▱▱ 58% 4d2h
```

- **Pieces:** one piece per provider, made of label, window label, bar, percentage and countdown. The piece shows the provider's selected window: `auto` means the most-used one, model-scoped windows included. `#{ai_usage}` joins the pieces with the separator.
- **Bar:** filled cells = round(used_pct × width / 100).
- **Countdown:** the two largest units, with a zero remainder dropped: `47m`, `2h13m`, `3d4h`, `1d`.
- **Colours:**
  - The bar and percentage use the ok, warn or crit colour, at `< warn_at`, `≥ warn_at` and `≥ crit_at`.
  - The provider label uses the text colour.
  - The window label, countdown and separator use the dim colour.

### States

From [How are stale, missing, and failed readings shown?](https://github.com/isenthamiz/tmux-ai-usage/issues/9).

| State | Rendering |
|---|---|
| `ok`, fresh; or `error` that isn't yet stale (last good value, unmarked) | `cx 5h ▰▰▰▰▱ 81% 47m` |
| `pending` | `cl …`, all dim |
| `stale`, whatever the cause | the last good piece, all dim, with `~` before the percentage: `cx 5h ▰▰▰▰▱ ~81% 47m` |
| `signed_out` / `missing_dep` / `bad_shape` (shown immediately, no last good value) | `cl !login` / `cx !deps` / `cu !format` in the crit colour |
| `error` with no last good value ever | `cl !error` in the crit colour |

A provider never disappears from `#{ai_usage}`; it keeps its position and separator. The words, `~` and `…` are fixed in v1.

## Options

From [What tmux options configure the plugin?](https://github.com/isenthamiz/tmux-ai-usage/issues/7), plus `@ai_usage_stale_after` from [How are stale, missing, and failed readings shown?](https://github.com/isenthamiz/tmux-ai-usage/issues/9).

| Option | Type / validation | Default |
|---|---|---|
| `@ai_usage_providers` | space-separated subset of `claude codex cursor`; sets order for `#{ai_usage}` | `claude codex cursor` |
| `@ai_usage_<provider>_window` | `auto` or a window label; a missing label falls back to `auto` | `auto` |
| `@ai_usage_bar_width` | integer ≥ 0 (`0` = percentage only) | `5` |
| `@ai_usage_bar_filled` / `@ai_usage_bar_empty` | string | `▰` / `▱` |
| `@ai_usage_warn_at` / `@ai_usage_crit_at` | integer 0–100, warn < crit | `60` / `85` |
| `@ai_usage_ok_color` / `_warn_color` / `_crit_color` | tmux colour | `@thm_green` / `@thm_yellow` / `@thm_red`, else `#a6e3a1` / `#f9e2af` / `#f38ba8` |
| `@ai_usage_text_color` / `_dim_color` | tmux colour | `@thm_subtext_0` / `@thm_overlay_0`, else `#bac2de` / `#6c7086` |
| `@ai_usage_claude_label` / `_codex_label` / `_cursor_label` | string | `cl` / `cx` / `cu` |
| `@ai_usage_separator` | string | ` │ ` |
| `@ai_usage_refresh_interval` | integer seconds; values below 60 are raised to 60 | `60` |
| `@ai_usage_stale_after` | integer seconds, ≥ refresh interval | `900` |
| `@ai_usage_cache_dir` | path; created with mode 700 | `${XDG_CACHE_HOME:-$HOME/.cache}/tmux-ai-usage` |

A per-provider token renders whether or not that provider is in `@ai_usage_providers`.

## Diagnostics

- **`scripts/doctor.sh`** reads snapshots only. It prints one line per provider (status, age of the last good reading, `retry_at`, error text), checks dependencies and shows the effective option values. There is no default key binding.
- **`scripts/smoke.sh`** is manual and never runs in CI. It runs each real fetcher once and prints the resulting snapshots: usage numbers only, never tokens.

## Testing

From [How are fetchers and the renderer tested?](https://github.com/isenthamiz/tmux-ai-usage/issues/10).

- **Entry point:** `make test` runs `shellcheck` on every script, then `bats test/`. Dev dependencies: `brew install bats-core shellcheck`.
- **CI:** GitHub Actions on `macos-latest` for every push and PR.
- **Normalizers:** tested against synthetic fixtures that match the real shapes, in `test/fixtures/<provider>/<variant>.json`. Raw captures are never committed.
  - Claude: 5h + weekly; 5h + weekly + model-scoped.
  - Codex: primary only; primary + secondary.
  - Cursor: unified weekly; legacy two monthly pools.
  - One malformed fixture per provider.
- **Acquire scripts:** tested through PATH shims (fake `curl` / `claude` / `security` / `sqlite3`), for failure paths only.
- **Renderer:** a shimmed `tmux` answers `show-options`, the clock is injected with `AI_USAGE_NOW=<epoch>`, and outputs are compared as exact strings, including `#[fg=…]` markup.
- **Refresh lock:**
  - A fresh snapshot starts no refresh.
  - A stale snapshot returns the cached value and starts exactly one refresh.
  - N concurrent stale renders start one refresh.

## README must cover

- TPM install: `set -g @plugin 'isenthamiz/tmux-ai-usage'`. List it after the theme plugin, so the tokens are already in `status-right` when it loads.
- Token placement and the option table.
- Dependencies per provider:
  - `jq` always.
  - Claude: the `claude` CLI, signed in.
  - Codex: `curl`, plus a signed-in Codex CLI.
  - Cursor: `curl`, `sqlite3`, `security`, Homebrew `openssl@3`, plus the Cursor app signed in.
- Cursor's one-time Keychain "Always Allow".
- **What it reads:** every file and endpoint, all read-only. Tokens are never refreshed and never written to the cache.
- `doctor.sh`, with an optional `bind-key … run-shell` line.
