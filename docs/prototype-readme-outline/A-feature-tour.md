# PROTOTYPE — README outline, variant A: "feature tour, tables inline"

> Throwaway skeleton for [Rough README outline and section skeleton](https://github.com/isenthamiz/tmux-ai-usage/issues/62).
> Each feature section is self-contained: picture → what it is → when you'd want it → snippet → its options table.
> There is no separate big Reference section; the options table lives with the feature it controls.

---

# tmux-ai-usage

One line: see how much of your Claude / Codex / Cursor plan quota you've used, and when it resets, in the tmux status line.

`[IMAGE hero.png — a real tmux window, status line with three usage bars, cropped to the bottom ~6 lines]`

Three bullets: what you get (one bar per provider, time to reset, colours by usage), that it never slows tmux (cached, background refresh), macOS only.

## Quick start

1. Add to `~/.tmux.conf` (TPM lines + `#{ai_usage}` in `status-right`) — one copy-paste block.
2. `prefix + I`, then `prefix + r`.
3. Install deps: `brew install jq` (+ per-provider list, short, link to [Requirements](#requirements)).
4. "You should now see …" `[IMAGE quickstart-result.png]`. Not seeing it? → [Troubleshooting](#troubleshooting).

## Reading a usage bar

`[IMAGE anatomy.png — one usage bar with callouts: provider label · window label · progress bar · countdown]`

- What each part means (glossary words: provider, quota window, usage, reset).
- Colours: green / yellow / red, thresholds 60 / 85 → snippet to change them.
- Which window is shown (`auto` = most used) — one sentence, link to [Choosing the window](#choosing-which-window-a-bar-shows).

## Where the bars go (placement)

- `#{ai_usage}` vs `#{ai_usage_claude}` etc., in plain words: "all in one place" vs "each where you like".
- Snippet: theme status-right example; catppuccin example.
- ⚠ Load order: plugin after your theme. Adding/moving a token needs `prefix + r`.
- Options table: providers, labels, separator.

## Fitting narrow terminals (steps)

`[GIF steps.gif — terminal resized wide → narrow, bars shrink full → 1 → 2 → 3 → 4]`

- What a step is; the five steps as a small picture table.
- "I always want the full bar" (= the original "detailed view") → `set -g @ai_usage_step full`.
- Change the breakpoints → `@ai_usage_step_widths`.
- Options table: step, step_widths. Note tmux ≥ 3.2.

## One provider at a time (rotation)

`[GIF rotation.gif — single slot cycling cl → cx → cu]`

- What / when you'd want it (short status line, many providers).
- Snippet: rotate on, interval 20.
- Options table: rotate, rotate_interval.

## Follow the agent in the active pane (focus)

`[GIF focus.gif — switching panes: Claude pane shows cl only, Codex pane shows cx, plain shell shows all]`

- What / when (you run one agent per pane and only care about that one).
- How it detects the agent (foreground process; `^Z` not detected).
- Focus beats rotation; works with steps.
- ⚠ Needs `prefix + r` after changing.
- Options table: focus.

## Every window at a glance (details popup)

`[IMAGE popup.png — prefix + u popup with all providers/windows, one stale, one !login with fix]`

- What it shows; `q`/`Esc` closes.
- Snippet: change key / unbind.
- Options table: details_key.

## Choosing which window a bar shows

- `auto` vs pinning `wk` / `5h`; table of window labels per provider.
- Options table: `<provider>_window`.

## Look: bar and colours

- Percentage instead of bar; custom glyphs; colours without catppuccin.
- Options table: bar_*, colours, thresholds.

## When something's wrong (status-line markers)

`[IMAGE markers.png — one strip showing ok, pending, stale ~, !login, !deps, !format, !error]`

- Table: marker → meaning → fix (one line each).
- Tip: open the details popup, it spells out the fix.

## Requirements

- Dependency matrix per provider (existing table).
- Cursor Keychain prompt → "Always Allow" `[IMAGE keychain.png?]`.

## Troubleshooting

- Nothing shows / literal `#{ai_usage}` → load order, reload.
- `!jq`, `!deps`, `!login` → fixes.
- `scripts/doctor.sh` and how to bind it.
- When option changes apply (moved here from Options).

## Privacy: what it reads

- Short reassurance first (read-only, never refreshes tokens, cache holds usage only), then per-provider detail.

## Development

- `make test`, links to SPEC / GLOSSARY.
