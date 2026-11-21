# tmux-ai-usage v1 spec

A TPM-installable tmux plugin that draws **usage bars** in the status line. Each bar shows how much of a quota window's plan quota has been used, plus the time until it resets, for Claude, Codex and Cursor. It is macOS-only in v1.

This file gathers the decisions recorded on the wayfinder map, [Wayfinder: tmux plan-quota usage bars for Claude, Codex, Cursor](https://github.com/isenthamiz/tmux-ai-usage/issues/1). Each section links the ticket that holds the full reasoning. Terms (provider, plan quota, quota window, usage snapshot, snapshot status, window label, stale, pending, progress bar, step, rotation, focus) are defined in [`GLOSSARY.md`](GLOSSARY.md).

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
  details.sh                  # details popup body (reads snapshots only)
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
  - `#{ai_usage}` → `#($DIR/scripts/render.sh all)`, or with `@ai_usage_focus on` → `#($DIR/scripts/render.sh all #{q:pane_current_command} #{q:pane_tty})`
  - `#{ai_usage_claude|codex|cursor}` → `#($DIR/scripts/render.sh <provider>)`
  - No option values go into the command string.
- Validates every option once (see [Options](#options)). An invalid value falls back to its default, and one `display-message` names the option and the bad value.
- Binds `@ai_usage_details_key` (default `u`) in the prefix table to open the [details popup](#details-popup), unless it is empty.
- Checks only for `jq`. If `jq` is missing, it shows one `display-message` and rewrites every token to a literal `!jq` in the crit colour.

### Renderer: `render.sh`

- Each run makes one `tmux show-options -g` call and one `jq` call covering every snapshot it draws, and prints every step at once inside one `client_width` conditional. Target: under 50 ms; it must stay well under 1 s, because tmux re-runs a `#()` command that takes ≥ 1 s in a loop. With focus on, a `node` or shell pane adds one `ps -t` call (~1.5 ms).
- Never calls `tmux display -p` for the width: with several clients it answers for one of them.
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

From [What should the usage bars look like?](https://github.com/isenthamiz/tmux-ai-usage/issues/6), revised by the map [Wayfinder: compact, width-aware usage bars](https://github.com/isenthamiz/tmux-ai-usage/issues/35). The rejected variants are on the `prototype/usage-bars` branch.

```
cl wk ▰▰▰▱▱ 3d4h │ cx 5h ▰▰▰▰▱ 47m │ cu wk ▰▰▰▱▱ 4d2h
```

- **Pieces:** one usage bar per provider, made of provider label, window label, progress bar, percentage and countdown; which of these show depends on the [step](#steps). The piece shows the provider's selected window: `auto` means the most-used one, model-scoped windows included. `#{ai_usage}` joins the pieces with the separator.
- **Progress bar:** filled cells = round(used_pct × width / 100). With `@ai_usage_bar_width 0` the percentage takes the progress bar's place at every step (`cl wk 67% 3d4h`).
- **Countdown:** the two largest units, with a zero remainder dropped: `47m`, `2h13m`, `3d4h`, `1d`.
- **Colours:**
  - The progress bar and percentage use the ok, warn or crit colour, at `< warn_at`, `≥ warn_at` and `≥ crit_at`.
  - The provider label uses the text colour (at step 4, the usage colour instead).
  - The window label, countdown and separator use the dim colour.

### Steps

From [How should each step look, and at which widths?](https://github.com/isenthamiz/tmux-ai-usage/issues/38). Every shown provider is drawn at the same step.

| Step | Client width (default) | Rendering (three providers) | Cols |
|---|---|---|---|
| full | ≥ 180 | `cl 5h ▰▱▱▱▱ 3h58m │ cx wk ▰▰▰▱▱ 1d14h │ cu wk ▰▰▰▰▰ 1d23h` | 57 |
| 1 | ≥ 140 | `cl ▰▱▱▱▱ 3h58m │ cx ▰▰▰▱▱ 1d14h │ cu ▰▰▰▰▰ 1d23h` (window label dropped) | 48 |
| 2 | ≥ 110 | `cl ▰▱▱▱▱ cx ▰▰▰▱▱ cu ▰▰▰▰▰ 1d23h` (countdown only when crit) | 32 |
| 3 | ≥ 80 | `cl 16% cx 66% cu 100% 1d23h` (percentage replaces the progress bar; countdown only when crit) | 27 |
| 4 | < 80 | `cl cx cu`, each label in its usage colour | 8 |

- The full step shows the progress bar and **no** percentage.
- **Separator:** `@ai_usage_separator` (default ` │ `) at full and step 1; a single space at steps 2–4.
- **Choosing the step:** `render.sh` prints one nested tmux format, `#{?#{e|>=:#{client_width},180},<full>,#{?#{e|>=:#{client_width},140},<step 1>,…}}`, holding every step's text. tmux re-expands `#()` output as a format on every redraw, per client, so each attached client gets its own step with no stale width after a resize (from [Can the renderer learn the tmux client width?](https://github.com/isenthamiz/tmux-ai-usage/issues/36)). Step text must contain no literal commas or unbalanced braces.
- `@ai_usage_step` forces one step; on tmux < 3.2 (no `e|>=:`), `auto` renders the full step.

### Rotation and focus

From [How do rotation and focus behave?](https://github.com/isenthamiz/tmux-ai-usage/issues/41). Both are opt-in and act on `#{ai_usage}` only; a per-provider token always shows its provider.

- **Rotation** (`@ai_usage_rotate on`): one provider at a time, cycling through the enabled providers in order. The provider shown is `index = floor(now / interval) mod n`, so every client agrees and nothing is stored. The interval (default 10 s) is rounded up to whole `status-interval` ticks. Every provider gets an equal turn, whatever its usage or state. One enabled provider means no rotation.
- **Focus** (`@ai_usage_focus on`): when the active pane runs an AI agent whose provider is enabled, only that provider is shown, overriding the side-by-side view and rotation. Otherwise the usual view shows. Other providers' problems are not surfaced while focused.
- **Detecting the agent** (from [What does tmux report as the running command for each AI agent?](https://github.com/isenthamiz/tmux-ai-usage/issues/37)): with focus on, the token is rewritten to `#('…/render.sh' all #{q:pane_current_command} #{q:pane_tty})`; a pane switch re-runs it at once.
  - `codex` → Codex. `claude`, `claude.exe`, or a version string like `2.1.328` → Claude.
  - `node` or a shell name → one `ps -t <pane_tty> -o pgid=,tpgid=,args=` call, keeping only the foreground process group (`pgid == tpgid`), so background jobs and the pane's shell don't count; a `cursor-agent` path → Cursor, a `claude` path → Claude, a `codex` path → Codex.
  - Anything else → no focus.
- Steps apply to the single provider like everywhere else.

### States

From [How are stale, missing, and failed readings shown?](https://github.com/isenthamiz/tmux-ai-usage/issues/9) and, per step, [How do problem states render at each step?](https://github.com/isenthamiz/tmux-ai-usage/issues/39).

| State | full | step 1 | step 2 | step 3 | step 4 |
|---|---|---|---|---|---|
| `ok`, fresh; or `error` that isn't yet stale (last good value, unmarked) | `cx 5h ▰▰▰▰▱ 47m` | `cx ▰▰▰▰▱ 47m` | `cx ▰▰▰▰▱` | `cx 81%` | `cx` in its usage colour |
| `stale`, whatever the cause (all dim) | `cx 5h ~▰▰▰▰▱ 47m` | `cx ~▰▰▰▰▱ 47m` | `cx ~▰▰▰▰▱` | `cx ~81%` | `cx` dim, no `~` |
| `signed_out` / `missing_dep` / `bad_shape` (crit colour, no last good value) | `cl !login` / `cx !deps` / `cu !format` | same | same | same | `cl!` |
| `error` with no last good value ever (crit colour) | `cl !error` | same | same | same | `cl!` |
| `pending` (all dim) | `cl …` | same | same | same | `cl` |

- `~` sits immediately before whatever shows usage at that step.
- At step 4, `cl!` keeps "action needed" distinct from a crit-coloured label meaning high usage.
- A passed reset shows 0% with no countdown.

A provider never disappears from the side-by-side `#{ai_usage}`; it keeps its position and separator. The words, `~` and `…` are fixed.

### Details popup

From [How should the details popup look and open?](https://github.com/isenthamiz/tmux-ai-usage/issues/42). The prototype is on the `prototype/details-popup` branch.

- **Opens** on `prefix + <@ai_usage_details_key>` (default `u`; empty binds nothing), titled ` AI usage · q close `; `q` or `Esc` closes it.
- **Sized to its content** (from [Size the details popup to its content](https://github.com/isenthamiz/tmux-ai-usage/issues/57)): the binding runs `details.sh --open` through `run-shell`, which renders the body once and opens `display-popup` at the widest line and the line count, plus one cell of padding on every side and the border. It is at least as wide as the title and at most the client's size. The size is fixed when it opens; the body still redraws every 10 s.
- **Reads** cached usage snapshots only, like the status line.
- **Table layout:** one row per quota window, every enabled provider, most-used first: provider, window label, 10-cell progress bar, percentage, countdown, and reset as local clock time (`Thu 22:39`). When the client is too narrow for the table (56 columns plus padding and border), it uses one line per provider instead (`Claude  5h 19% 3h39m  wk 0% 6d23h`). Problem and stale notes wrap to the layout's width.
- **Problems in words**, under the provider, using the status-line marker plus the fix:
  - `!login`: Claude "Run `claude` in a terminal and log in."; Codex "Run `codex login`."; Cursor "Open the Cursor app and sign in."
  - `!deps`: "Something it needs is missing. Run doctor.sh to see what."
  - `!format`: "The provider answered in a format the plugin doesn't know. The plugin may need an update."
  - `!error`: "Temporary error; retrying automatically."
  - Stale: "~ last good reading 2h ago; numbers may be out of date".

## Options

From [What tmux options configure the plugin?](https://github.com/isenthamiz/tmux-ai-usage/issues/7), plus `@ai_usage_stale_after` from [How are stale, missing, and failed readings shown?](https://github.com/isenthamiz/tmux-ai-usage/issues/9), and the step, rotation, focus and details options from [Which options control steps and the single view?](https://github.com/isenthamiz/tmux-ai-usage/issues/40) and [How should the details popup look and open?](https://github.com/isenthamiz/tmux-ai-usage/issues/42).

| Option | Type / validation | Default |
|---|---|---|
| `@ai_usage_providers` | space-separated subset of `claude codex cursor`; sets order for `#{ai_usage}` | `claude codex cursor` |
| `@ai_usage_<provider>_window` | `auto` or a window label; a missing label falls back to `auto` | `auto` |
| `@ai_usage_bar_width` | integer ≥ 0 (`0` = percentage in place of the progress bar at every step) | `5` |
| `@ai_usage_bar_filled` / `@ai_usage_bar_empty` | string | `▰` / `▱` |
| `@ai_usage_warn_at` / `@ai_usage_crit_at` | integer 0–100, warn < crit | `60` / `85` |
| `@ai_usage_ok_color` / `_warn_color` / `_crit_color` | tmux colour | `@thm_green` / `@thm_yellow` / `@thm_red`, else `#a6e3a1` / `#f9e2af` / `#f38ba8` |
| `@ai_usage_text_color` / `_dim_color` | tmux colour | `@thm_subtext_0` / `@thm_overlay_0`, else `#bac2de` / `#6c7086` |
| `@ai_usage_claude_label` / `_codex_label` / `_cursor_label` | string | `cl` / `cx` / `cu` |
| `@ai_usage_separator` | string; used at full and step 1 (steps 2–4 use one space) | ` │ ` |
| `@ai_usage_step_widths` | four descending integers: minimum client width for full, step 1, step 2, step 3 | `180 140 110 80` |
| `@ai_usage_step` | `auto`, `full`, `1`, `2`, `3`, `4` | `auto` |
| `@ai_usage_rotate` | `off`, `on` | `off` |
| `@ai_usage_rotate_interval` | integer seconds, rounded up to whole `status-interval` ticks | `10` |
| `@ai_usage_focus` | `off`, `on` | `off` |
| `@ai_usage_details_key` | a key for `bind-key` in the prefix table; empty binds nothing | `u` |
| `@ai_usage_refresh_interval` | integer seconds; values below 60 are raised to 60 | `60` |
| `@ai_usage_stale_after` | integer seconds, ≥ refresh interval | `900` |
| `@ai_usage_cache_dir` | path; created with mode 700 | `${XDG_CACHE_HOME:-$HOME/.cache}/tmux-ai-usage` |

A per-provider token renders whether or not that provider is in `@ai_usage_providers`. It follows the step but ignores rotation and focus.

`@ai_usage_focus` and `@ai_usage_details_key` are read when the plugin loads (they change the token rewrite and the key table), so changing them needs a reload; every other option applies on the next redraw.

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
- **Steps, rotation, focus:** the renderer's output for every step is compared as exact strings; rotation is tested by moving `AI_USAGE_NOW`; focus by passing pane command and tty arguments with a shimmed `ps`.
- **Details popup:** `details.sh` output with colours stripped, against the same fixtures and clock.
- **Refresh lock:**
  - A fresh snapshot starts no refresh.
  - A stale snapshot returns the cached value and starts exactly one refresh.
  - N concurrent stale renders start one refresh.

## README must cover

- TPM install: `set -g @plugin 'isenthamiz/tmux-ai-usage'`. List it after the theme plugin, so the tokens are already in `status-right` when it loads.
- Token placement and the option table, with the steps, rotation, focus and the details popup key.
- Dependencies per provider:
  - `jq` always.
  - Claude: the `claude` CLI, signed in.
  - Codex: `curl`, plus a signed-in Codex CLI.
  - Cursor: `curl`, `sqlite3`, `security`, Homebrew `openssl@3`, plus the Cursor app signed in.
- Cursor's one-time Keychain "Always Allow".
- **What it reads:** every file and endpoint, all read-only. Tokens are never refreshed and never written to the cache.
- `doctor.sh`, with an optional `bind-key … run-shell` line on a key other than the details key.
- tmux ≥ 3.2 for width-aware steps.
