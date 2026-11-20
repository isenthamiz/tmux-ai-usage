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

Options are ordinary tmux user options, set with `set -g @ai_usage_<name> '<value>'`. A complete `~/.tmux.conf`:

```tmux
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'catppuccin/tmux'
set -g @plugin 'isenthamiz/tmux-ai-usage'

set -g status-right '#{ai_usage} │ %H:%M'

set -g @ai_usage_providers 'claude cursor'
set -g @ai_usage_claude_window 'wk'
set -g @ai_usage_warn_at '70'

run '~/.tmux/plugins/tpm/tpm'
```

### When changes apply

- Options can go anywhere in `~/.tmux.conf`; they do not have to come before the plugin line.
- The status line reads options on every redraw, so a change applies on the next redraw. You can try one live with `tmux set -g @ai_usage_bar_width 0`.
- Adding or moving a `#{ai_usage…}` token in `status-left` or `status-right` needs a reload (`prefix + r`) or a tmux restart, because tokens are replaced when the plugin loads.
- Invalid values are reported at load time, one `display-message` per bad option, and reset to their defaults. A value that becomes invalid later silently falls back to the default.

### Recipes

Show only Claude and Cursor, in that order:

```tmux
set -g @ai_usage_providers 'claude cursor'
```

Always show Claude's weekly window instead of the most-used one:

```tmux
set -g @ai_usage_claude_window 'wk'
```

Percentage instead of the bar:

```tmux
set -g @ai_usage_bar_width '0'
```

Colours without catppuccin:

```tmux
set -g @ai_usage_ok_color '#50fa7b'
set -g @ai_usage_warn_color '#f1fa8c'
set -g @ai_usage_crit_color '#ff5555'
set -g @ai_usage_text_color '#f8f8f2'
set -g @ai_usage_dim_color '#6272a4'
```

One provider at a time, 20 s each:

```tmux
set -g @ai_usage_rotate 'on'
set -g @ai_usage_rotate_interval '20'
```

Always the compact step, whatever the width:

```tmux
set -g @ai_usage_step '2'
```

Each provider in its own place:

```tmux
set -g status-left '#{ai_usage_claude} '
set -g status-right '#{ai_usage_cursor} │ %H:%M'
```

### Window labels

`@ai_usage_<provider>_window` picks which quota window the usage bar shows. `auto` (the default) shows the window with the highest current usage. To pin one window, use its label:

| Provider | Window labels |
|---|---|
| Claude | `5h`, `wk`, and model-scoped weekly windows such as `wk-opus`, `wk-sonnet` (`wk-<model>`) |
| Codex | `5h`, `wk` |
| Cursor | `wk` on unified plans; `mo-auto`, `mo-api` on legacy plans |

A label the provider does not currently report falls back to `auto`.

### Reference

**What to show**

| Option | Value | Default |
|---|---|---|
| `@ai_usage_providers` | Space-separated subset of `claude codex cursor`; also the order in `#{ai_usage}` | `claude codex cursor` |
| `@ai_usage_claude_window` / `@ai_usage_codex_window` / `@ai_usage_cursor_window` | `auto` or a window label (see above) | `auto` |
| `@ai_usage_claude_label` / `@ai_usage_codex_label` / `@ai_usage_cursor_label` | String | `cl` / `cx` / `cu` |
| `@ai_usage_separator` | String between providers in `#{ai_usage}` at full and step 1 (steps 2–4 use one space) | ` │ ` |

**Steps**

Each usage bar shrinks with the terminal width, per tmux client. Every shown provider is drawn at the same step:

| Step | Client width (default) | Looks like |
|---|---|---|
| full | ≥ 180 | `cl 5h ▰▱▱▱▱ 3h58m │ cx wk ▰▰▰▱▱ 1d14h` |
| 1 | ≥ 140 | `cl ▰▱▱▱▱ 3h58m │ cx ▰▰▰▱▱ 1d14h` |
| 2 | ≥ 110 | `cl ▰▱▱▱▱ cx ▰▰▰▱▱` (countdown only when crit) |
| 3 | ≥ 80 | `cl 16% cx 66%` (countdown only when crit) |
| 4 | < 80 | `cl cx`, each label in its usage colour |

Width-aware steps need tmux ≥ 3.2; older tmux shows the full step unless `@ai_usage_step` forces one.

| Option | Value | Default |
|---|---|---|
| `@ai_usage_step_widths` | Four descending integers: minimum client width for full, step 1, step 2, step 3 | `180 140 110 80` |
| `@ai_usage_step` | `auto`, `full`, `1`, `2`, `3`, `4` | `auto` |

**Rotation**

With `@ai_usage_rotate on`, `#{ai_usage}` shows one provider at a time, cycling through `@ai_usage_providers` in order. Every provider gets an equal turn, whatever its usage or state, and every client shows the same one. With one enabled provider nothing rotates. Per-provider tokens never rotate.

| Option | Value | Default |
|---|---|---|
| `@ai_usage_rotate` | `off`, `on` | `off` |
| `@ai_usage_rotate_interval` | Seconds per provider; rounded up to whole `status-interval` ticks | `10` |

**Focus**

With `@ai_usage_focus on`, `#{ai_usage}` shows only the provider whose AI agent runs in the active pane: Claude Code, Codex or Cursor's CLI. Focus takes precedence over the side-by-side view and over rotation. In a pane with no agent, or one whose provider isn't in `@ai_usage_providers`, the usual view returns. Per-provider tokens ignore focus.

Focus changes how `#{ai_usage}` is rewritten when the plugin loads, so turning it on or off needs a reload (`prefix + r`). Only the foreground process counts, so an agent suspended with `^Z` isn't detected.

| Option | Value | Default |
|---|---|---|
| `@ai_usage_focus` | `off`, `on` | `off` |

**Details popup**

`prefix + u` opens a popup listing every quota window of every enabled provider, most-used first, with its progress bar, percentage, time until reset and the reset as local clock time. Problems are spelled out with their fix (for example `!login Run \`codex login\`.`), and a stale reading shows how old the last good reading is. Below about 60 columns it shows one line per provider. `q` or `Esc` closes it. Like the status line, it only reads cached usage snapshots.

| Option | Value | Default |
|---|---|---|
| `@ai_usage_details_key` | A key in the prefix table; empty binds nothing. Read at load, so a change needs a reload | `u` |

**Bar**

| Option | Value | Default |
|---|---|---|
| `@ai_usage_bar_width` | Integer ≥ 0; `0` puts the percentage where the bar would be, at every step | `5` |
| `@ai_usage_bar_filled` / `@ai_usage_bar_empty` | String | `▰` / `▱` |

**Colours and thresholds**

If a catppuccin theme is loaded, colours follow its palette; otherwise the hex defaults below apply.

| Option | Value | Default |
|---|---|---|
| `@ai_usage_warn_at` / `@ai_usage_crit_at` | Integer 0–100; warn must be less than crit | `60` / `85` |
| `@ai_usage_ok_color` / `@ai_usage_warn_color` / `@ai_usage_crit_color` | tmux colour; bar and percentage below warn, at or above warn, at or above crit | `#a6e3a1` / `#f9e2af` / `#f38ba8` |
| `@ai_usage_text_color` | tmux colour; provider label | `#bac2de` |
| `@ai_usage_dim_color` | tmux colour; window label, countdown, separator | `#6c7086` |

**Refresh and cache**

| Option | Value | Default |
|---|---|---|
| `@ai_usage_refresh_interval` | Seconds between fetches; values below 60 are raised to 60 | `60` |
| `@ai_usage_stale_after` | Seconds before a reading is shown as stale; must be ≥ the refresh interval | `900` |
| `@ai_usage_cache_dir` | Path; created with mode `700` if missing | `${XDG_CACHE_HOME:-$HOME/.cache}/tmux-ai-usage` |

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
bind-key D run-shell 'bash /path/to/tmux-ai-usage/scripts/doctor.sh'
```

Replace `/path/to/tmux-ai-usage` with the plugin directory TPM cloned (often `~/.tmux/plugins/tmux-ai-usage`).

Output includes dependency checks, one line per provider (status, age of last good reading, `retry_at`, short error text), and effective options.

For a one-off live fetch (manual debugging, not used in CI), run `scripts/smoke.sh`; it prints usage numbers only, never tokens.

## Development

```bash
make test   # shellcheck + bats
```

See [`SPEC.md`](SPEC.md) for architecture and [`GLOSSARY.md`](GLOSSARY.md) for vocabulary.