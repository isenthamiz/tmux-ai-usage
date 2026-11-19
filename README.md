# tmux-ai-usage

A [TPM](https://github.com/tmux-plugins/tpm) plugin that draws **plan-quota usage bars** in the tmux status line for Claude, Codex, and Cursor. Each bar shows how full the selected quota window is and the time until it resets. Readings are cached and refreshed in the background; the status line never blocks on network I/O.

**Platform:** macOS only in v1.

Example (with default labels and colours):

```
cl wk ▰▰▰▱▱ 67% 3d4h │ cx 5h ▰▰▰▰▱ 81% 47m │ cu wk ▰▰▰▱▱ 58% 4d2h
```

Terms such as *plan quota*, *quota window*, and *usage snapshot* are defined in [`GLOSSARY.md`](GLOSSARY.md).

## Install

1. Install [TPM](https://github.com/tmux-plugins/tpm) if you do not already use it.
2. Add the plugin **after your theme plugin**, so tokens like `#{ai_usage}` are already in `status-left` or `status-right` when this plugin loads and rewrites them:

```tmux
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'catppuccin/tmux'          # or your theme — must load first
set -g @plugin 'isenthamiz/tmux-ai-usage'
```

3. Press **prefix + I** in tmux to install plugins, or run your usual TPM install step.
4. Install dependencies (see below), sign in to each provider you want, then reload tmux (`prefix + r`) or restart the server.

## Placement

Put one of these tokens in `status-left` or `status-right` (often via your theme’s status format):

| Token | Renders |
|---|---|
| `#{ai_usage}` | All enabled providers, joined with `@ai_usage_separator` |
| `#{ai_usage_claude}` | Claude only |
| `#{ai_usage_codex}` | Codex only |
| `#{ai_usage_cursor}` | Cursor only |

On load, the plugin replaces each token with a `#(…/scripts/render.sh …)` command. A per-provider token still works even if that provider is omitted from `@ai_usage_providers`.

Example:

```tmux
set -g status-right '#{prefix} │ #{ai_usage} │ %H:%M'
```

## Options

Invalid values are reset to their defaults at load time (you get one `display-message` per bad option). The renderer silently falls back to defaults if an option becomes invalid later.

| Option | Type / validation | Default |
|---|---|---|
| `@ai_usage_providers` | Space-separated subset of `claude codex cursor`; order for `#{ai_usage}` | `claude codex cursor` |
| `@ai_usage_claude_window` / `@ai_usage_codex_window` / `@ai_usage_cursor_window` | `auto` or a window label (`5h`, `wk`, `mo`, `mo-auto`, …); unknown label → `auto` | `auto` |
| `@ai_usage_bar_width` | Integer ≥ 0 (`0` = percentage only, no bar glyphs) | `5` |
| `@ai_usage_bar_filled` / `@ai_usage_bar_empty` | String | `▰` / `▱` |
| `@ai_usage_warn_at` / `@ai_usage_crit_at` | Integer 0–100; warn must be &lt; crit | `60` / `85` |
| `@ai_usage_ok_color` / `@ai_usage_warn_color` / `@ai_usage_crit_color` | tmux colour | `@thm_green` / `@thm_yellow` / `@thm_red`, else `#a6e3a1` / `#f9e2af` / `#f38ba8` |
| `@ai_usage_text_color` / `@ai_usage_dim_color` | tmux colour | `@thm_subtext_0` / `@thm_overlay_0`, else `#bac2de` / `#6c7086` |
| `@ai_usage_claude_label` / `@ai_usage_codex_label` / `@ai_usage_cursor_label` | String | `cl` / `cx` / `cu` |
| `@ai_usage_separator` | String | ` │ ` |
| `@ai_usage_refresh_interval` | Integer seconds; values below 60 are raised to 60 | `60` |
| `@ai_usage_stale_after` | Integer seconds; must be ≥ refresh interval | `900` |
| `@ai_usage_cache_dir` | Path; created with mode `700` if missing | `${XDG_CACHE_HOME:-$HOME/.cache}/tmux-ai-usage` |

With `auto`, the bar shows the quota window with the highest current usage (including model-scoped windows).

## Dependencies

| Component | Claude | Codex | Cursor |
|---|---|---|---|
| [`jq`](https://jqlang.org/) | required | required | required |
| `claude` CLI | required, signed in | — | — |
| `curl` | — | required | required |
| Codex CLI sign-in | — | required (`~/.codex/auth.json`) | — |
| `sqlite3` | — | — | required |
| `security` (Keychain) | — | — | required |
| Homebrew [`openssl@3`](https://formulae.brew.sh/formula/openssl@3) | — | — | required (must support `openssl kdf`; macOS `/usr/bin/openssl` is not enough) |
| Cursor app | — | — | required, signed in |

The plugin checks for `jq` when tmux loads. If `jq` is missing, every usage token is replaced with `!jq` in the crit colour.

## Cursor Keychain

The first time Cursor’s encrypted token is decrypted, macOS may prompt for Keychain access to **Cursor Safe Storage**. Choose **Always Allow** so refreshes do not block on a dialog. Refusal is recorded as a `missing_dep` snapshot (`!deps` on the bar) until access is granted.

## What it reads (read-only)

The plugin **never refreshes OAuth tokens** and **never writes credentials** to the usage cache. Cache files hold usage snapshots only (`$CACHE_DIR/<provider>.json`).

### Claude

- **Live:** Claude Code CLI (`claude …`), experimental `get_usage` control request (authentication handled by the CLI; the plugin does not read Keychain credentials).
- **Fallback:** `~/.claude.json` — **only** the `.cachedUsageUtilization` object (not the rest of the file).

### Codex

- **File:** `~/.codex/auth.json` — `tokens.access_token` and `tokens.account_id` (read only; no token refresh).
- **Endpoint:** `GET https://chatgpt.com/backend-api/wham/usage` with those headers.

### Cursor

- **File:** `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb` (`sqlite3 -readonly`, key `cursorAuth/accessToken`).
- **Keychain:** `security find-generic-password` for service **Cursor Safe Storage** (account **Cursor Key** or legacy **Cursor**).
- **Endpoints** (session cookie derived from the JWT; no token refresh):
  - `POST https://cursor.com/api/dashboard/get-sand-usage-status` (body `{}`)
  - `GET https://cursor.com/api/usage-summary` — only when the unified response is not active

Spend, budgets, and conversation context are out of scope; those fields are ignored.

## Status-line states

Markers are fixed in v1. A provider keeps its slot in `#{ai_usage}` even when something is wrong.

| What you see | Meaning |
|---|---|
| `cl …` (dim) | **Pending** — no snapshot yet; first refresh may still be running |
| `cx 5h ▰▰▰▰▱ ~81% 47m` (dim, `~` before %) | **Stale** — last good reading is older than `@ai_usage_stale_after` |
| `cl !login` | Not signed in (`signed_out`) |
| `cx !deps` | Missing dependency or Keychain refused (`missing_dep`) |
| `cu !format` | Provider response did not match a known shape (`bad_shape`) |
| `cl !error` | Transient failure with no prior good reading (`error`) |
| `!jq` | `jq` missing at plugin load |

Healthy readings look like the example at the top: bar colour follows warn/crit thresholds; label, window name, and countdown use text/dim colours.

## Diagnostics

`scripts/doctor.sh` reads **cached snapshots only** (no live fetch). From a shell inside a tmux session it uses your global tmux options; you can also bind it:

```tmux
bind-key u run-shell 'bash /path/to/tmux-ai-usage/scripts/doctor.sh'
```

Replace `/path/to/tmux-ai-usage` with the plugin directory TPM cloned (often `~/.tmux/plugins/tmux-ai-usage`).

Output includes dependency checks, one line per provider (status, age of last good reading, `retry_at`, short error text), and effective options.

For a one-off live fetch (manual debugging, not used in CI), run `scripts/smoke.sh`; it prints usage numbers only, never tokens.

## Development

```bash
make test   # shellcheck + bats
```

See [`SPEC.md`](SPEC.md) for architecture and [`GLOSSARY.md`](GLOSSARY.md) for vocabulary.