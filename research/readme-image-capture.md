# How can tmux screenshots and GIFs be captured reproducibly on macOS?

Resolves [#61](https://github.com/isenthamiz/tmux-ai-usage/issues/61). Researched 2026-11-22 on macOS 26.6.2 with tmux 3.5a. Terms follow [GLOSSARY.md](../GLOSSARY.md).

## Answer

**Use VHS (charmbracelet) to drive a nested tmux.** VHS renders the stills (`Screenshot x.png`) and the GIFs (`Output x.gif`) from one scripted `.tape` file. It runs on a Linux GitHub Actions runner through `vhs-action`, and it installs locally with `brew install vhs`. Inside the VHS terminal, an **outer** tmux with its status line off holds the **demo** tmux client in a pane. Resizing that pane with `resize-pane -x N` changes the demo client's `client_width`, and that is what steps the usage bars down. No recorder can resize its own terminal partway through a recording, so the nested tmux is how the resize GIF gets made.

The plugin needs **no code change** to show hand-written usage snapshots. Point `@ai_usage_cache_dir` at a demo directory and turn refresh off in one of two ways: `tmux set-environment -g AI_USAGE_NO_REFRESH 1`, or give each snapshot a `fetched_at` in the future. Both were tested and the snapshots stayed byte-identical. One small gap: the details popup ignores `AI_USAGE_NOW` (details below).

| | VHS | asciinema + agg | termshot | `screencapture` |
|---|---|---|---|---|
| Real tmux, status line, popup | Yes. It is a real terminal: ttyd + xterm.js in headless Chromium | Yes, recorded from a real pty | **No.** It renders one command's output, and "commands that reset the cursor position are known to create issues" | Yes, as pixels of a real terminal window |
| 24-bit hex colours | Yes. xterm.js supports truecolor, and VHS bundles `Catppuccin Mocha` and other themes | Yes. agg takes ad-hoc hex themes | Partly: SGR colours via `bunt`, but not a full-screen app | Yes, whatever the terminal shows |
| Still PNG | `Screenshot` command | `agg --select <t>` gives a one-frame GIF, not a PNG | PNG (but see the first row) | PNG |
| GIF | `Output x.gif` (also mp4, webm, PNG frames) | agg → GIF (gifski) | No | `-v` makes a `.mov`; ffmpeg turns it into a GIF |
| Resize mid-recording | **No.** "Setting must be administered at the top of the tape file". Use the nested tmux | asciinema records `"r"` resize events, but **agg ignores them**, and headless mode has no terminal to resize. Use the nested tmux | No | Only by resizing the window yourself (for example with AppleScript). Not reproducible |
| Headless / CI | Yes. `vhs-action` (tested on `ubuntu-latest`) or the Docker image | Yes. `asciinema rec --headless --window-size COLSxROWS` | Yes, but useless here | **No.** Needs a logged-in GUI session and the Screen Recording (TCC) permission |
| Install (brew) | `brew install vhs` pulls `ttyd` + `ffmpeg`. go-rod **downloads Chromium** on first run | `brew install asciinema agg`, both with no dependencies | `brew install homeport/tap/termshot` | Built in |

**Ranking:**

1. **VHS** gives PNG and GIF from one script, runs in CI, ships catppuccin themes, and has `Wait /regex/` to synchronise with tmux.
2. **asciinema + agg** is a good GIF-only fallback with a lighter install (no browser). Stills would need a second tool.
3. **`screencapture`** is the most faithful (real Ghostty or Terminal.app pixels, your own font), but it can't be scripted reproducibly or run in CI.
4. **termshot** is ruled out.

For stills without a browser there is a simpler path. Run `tmux -L outer capture-pane -p -e` on the outer pane: it gives the demo client's **whole screen, status line and popup included, as ANSI text with 24-bit SGR**. That text can then go through `freeze` (charmbracelet) or `termshot --raw-read` to make a PNG or SVG. This was tested; see the experiments below.

VHS itself was **not run locally**: it isn't installed, and Docker wasn't running. Its rows above come from its README and source. Everything about tmux and the plugin was tested.

---

## Tools

### VHS (charmbracelet/vhs v0.12.1, 2026-09-24)

Source: [README](https://github.com/charmbracelet/vhs), [`go.mod`](https://github.com/charmbracelet/vhs/blob/main/go.mod), [vhs-action](https://github.com/charmbracelet/vhs-action).

- **Dependencies:** "VHS requires `ttyd` and `ffmpeg` to be installed and available on your `PATH`." `brew info vhs` lists exactly those two. `go.mod` pulls `github.com/go-rod/rod`, which drives a headless Chromium and downloads it on first run ([vhs#438](https://github.com/charmbracelet/vhs/issues/438), open: "it downloads an executable from the web without disclosing it"). There is also a Docker image, `ghcr.io/charmbracelet/vhs`, with everything included.
- **Commands that matter here:** `Output out.gif` (more than one output is allowed: gif, mp4, webm, or a directory of PNG frames), `Screenshot path.png` ("captures the current frame"), `Hide`/`Show` (stop and resume capturing frames, for setup), `Wait[+Screen] /regex/` (default timeout 15 s), `Env KEY value`, `Sleep`, `Ctrl+<key>` (for the tmux prefix), `Set Theme "Catppuccin Mocha"` (bundled as `Catppuccin Frappe/Latte/Macchiato/Mocha` in `themes.json`), and `Set Width/Height` or `Set Columns/Rows`.
- **No mid-tape resize:** "Setting must be administered at the top of the tape file. Any setting (except `TypingSpeed`) applied after a non-setting or non-output command will be ignored."
- **CI:** vhs-action installs VHS (plus JetBrains Mono, with optional extra fonts) and runs a tape. Its own test workflow uses `runs-on: ubuntu-latest`. tmux and jq would come from `apt`.
- **Truecolor:** ttyd's terminal is xterm.js, which renders `38;2;r;g;b`. Whether tmux *sends* truecolor depends on its terminal features (see the gotchas).

### asciinema v3.2.1 + agg v1.9.0

Source: [asciinema README](https://github.com/asciinema/asciinema), [`src/cli.rs`](https://github.com/asciinema/asciinema/blob/develop/src/cli.rs), [asciicast v3](https://docs.asciinema.org/manual/asciicast/v3/), [agg README](https://github.com/asciinema/agg), [agg usage](https://docs.asciinema.org/manual/agg/usage/), [agg `src/asciicast.rs`](https://github.com/asciinema/agg/blob/main/src/asciicast.rs).

- **Recording:** `asciinema rec --headless --window-size 200x30 -c '<cmd>' demo.cast`. From `cli.rs`: headless mode means "without using the terminal for input/output … enabled automatically when running in an environment where a terminal is not available". `--window-size` sets the pty size.
- **Resize:** asciicast v3 has an `"r"` event, "captured in response to `SIGWINCH`", with `"{COLS}x{ROWS}"`. But agg's event model says "`Other` covers input, resize, exit, and unknown events: their payload is not modeled, only their timestamp". So agg renders the whole GIF at one geometry (or at a `--cols/--rows` override).
- **Rendering:** gifski encoder, built-in themes, or `--theme` as hex triplets. Also `--font-family`, `--font-size`, `--speed`, `--idle-time-limit`, `--fps-cap`, `--last-frame-duration`, and `--select` (a time range, one timestamp, or markers). No PNG output.
- **Install:** `brew install asciinema agg`. Neither has brew dependencies.

### termshot v0.6.1

Source: [README](https://github.com/homeport/termshot).

- "Reads the console output and renders an output image." You prefix a command with it, and it writes one PNG when the command exits. It is meant for command output, not full-screen apps: "commands that reset the cursor position are known to create issues". tmux positions the cursor for everything it draws.
- It can't make GIFs or resize. `--raw-read <file>` renders saved ANSI text, so it could turn a `capture-pane -e` dump into a still (not tried).

### macOS `screencapture`

Source: `man screencapture` on macOS 26.6.2.

- `-l <windowid>` captures one window, `-o` drops its shadow, `-R x,y,w,h` captures a rectangle, `-x` silences the sound. `-v` / `-V <seconds>` record video (a `.mov`, then ffmpeg makes the GIF).
- It captures real pixels of a real terminal, so tmux, the popup, the font and the colours are exactly what users see. But it needs a logged-in GUI session and the Screen Recording permission. Window ids, the font, the window size and Retina scale all differ between machines. And to resize, something outside the terminal has to resize the window. So it is not reproducible and doesn't belong in CI.

---

## Driving tmux for the captures (tested)

All of this ran on private servers (`tmux -L demo`, `tmux -L outer`), not the user's server.

**Nested tmux for width steps.** The outer server runs with `status off` and one pane: `env -u TMUX tmux -L demo attach -t demo`. After `split-window -h` and `resize-pane -t o:0.0 -x 120`, `tmux -L demo list-clients -F '#{client_width}'` reported `120`, and the demo status line had dropped to step 2. At `-x 90` it showed step 3 (`cl 71% cx 88% 44m cu 23%`). At the full 200 columns it showed the full step. In a VHS tape this is a hidden `Type "tmux -L outer resize-pane -t o:0.0 -x 120"` between `Sleep`s. A shell alias, or `bind` keys on the outer server, keeps it off screen.

**Capturing the status line and popup as text.** `capture-pane` on the demo server never includes its status line. On the **outer** pane, though, `capture-pane -p -e` returns the demo client's whole screen: status line, and the `display-popup` box after `details.sh --open <client> 200 20`. Colours come through as `\e[38;2;186;194;222m` and so on, which is truecolor intact. That file is a deterministic input for a still renderer (`freeze`, `termshot --raw-read`).

**Truecolor gotcha.** tmux only sends 24-bit colour when it knows the outer terminal supports RGB. Otherwise it maps hex colours to the 256-colour palette. Put `set -as terminal-features ',*:RGB'` (or the specific TERM) in the demo config. With it, the demo client reported `RGB` in `#{client_termfeatures}`. Under VHS/ttyd and asciinema, the TERM inside is whatever those tools set, so don't depend on it.

**Glyphs.** The bars use `▰▱` (U+25B0/U+25B1). Check that the recorder's font has them (VHS's default is JetBrains Mono, and agg falls back to symbol fonts). If it doesn't, set `@ai_usage_bar_filled/empty` in the demo config.

**Focus GIF.** Focus matches `pane_current_command` against `claude`, `codex` and `cursor-agent`, or a version string like `2.1.328` for Claude ([`scripts/lib/focus.sh`](../scripts/lib/focus.sh)). Demo panes can run stub executables with those names (for example a `demo-bin/claude` that prints a banner and sleeps). Then `select-pane` drives the GIF. The focus option has to be on before the plugin loads: the entrypoint reads `@ai_usage_focus` once ([`ai_usage.tmux`](../ai_usage.tmux)).

**Rotation GIF.** `rotation_pick` chooses `floor(now / interval) mod n` ([`scripts/render.sh`](../scripts/render.sh)), with the interval rounded up to `status-interval` ticks. Use `status-interval 1` and `@ai_usage_rotate_interval 2`, and leave `AI_USAGE_NOW` **unset**. A frozen clock freezes the rotation.

---

## Demo cache: can refresh be kept off hand-written snapshots?

**Yes, with no code change.** From the code:

1. **`@ai_usage_cache_dir`** sets `CACHE_DIR` ([`scripts/lib/options.sh`](../scripts/lib/options.sh), `load_options`). `snapshot_path` is `$CACHE_DIR/<provider>.json` ([`scripts/lib/snapshot.sh`](../scripts/lib/snapshot.sh)). render.sh, refresh.sh and details.sh all read it from there.
2. **Only render.sh starts a refresh**, in `maybe_start_refresh`. It returns early when `AI_USAGE_NO_REFRESH` is non-empty. Otherwise it refreshes only if the snapshot is missing, or `now >= retry_at` **and** `now - fetched_at >= REFRESH_INTERVAL`. refresh.sh checks `retry_at` and `fetched_at` again before calling any provider ([`scripts/refresh.sh`](../scripts/refresh.sh)). `focus.bats` already uses `AI_USAGE_NO_REFRESH=1`.
3. **How the environment gets to render.sh:** render.sh runs as a `#()` job. tmux's `job_run` builds the job's environment with `environ_for_session(s, …)`, which with no session means the **global** environment ([tmux `job.c`](https://github.com/tmux/tmux/blob/master/job.c), called from `format.c` with a NULL environment). So `tmux -L demo set-environment -g AI_USAGE_NO_REFRESH 1` reaches it. So does `AI_USAGE_NOW`, and so does exporting either one before starting the demo server.

That gives two independent locks. Use both:

- **`AI_USAGE_NO_REFRESH=1`** in the demo server's global environment.
- **`"fetched_at": 9999999999`** in every hand-written snapshot. `now - fetched_at` is negative, so it is never `>= REFRESH_INTERVAL`, and refresh never starts even without the variable. Tested: render.sh ran against the demo cache and the cache's md5 sums were unchanged afterwards, with no `*.lock` directory created.

No trick with failing providers or `refresh_interval` is needed. (`@ai_usage_refresh_interval` is clamped to at least 60, so it couldn't do this anyway.)

**Example snapshot** (the shape `render_read.jq` reads):

```json
{"provider":"claude","status":"ok","fetched_at":9999999999,"ok_at":NOW,"error":null,
 "windows":[{"label":"5h","used_pct":42,"resets_at":NOW_PLUS_7980},
            {"label":"wk","used_pct":71,"resets_at":NOW_PLUS_274000}]}
```

**Clock caveats:**

- **Staleness:** a reading is shown dimmed with `~` when `now - ok_at > @ai_usage_stale_after` (default 900 s, [`scripts/lib/format.sh`](../scripts/lib/format.sh) `is_stale`). With the real clock, either write `ok_at` and `resets_at` relative to `date +%s` just before capturing (a small generator script), or set `@ai_usage_stale_after` high in the demo config.
- **Stills:** `set-environment -g AI_USAGE_NOW <t>` freezes countdowns in the status line, so PNGs come out byte-stable.
- **The details popup ignores `AI_USAGE_NOW`.** Its interactive loop does `now=$(date +%s)` on every redraw ([`scripts/details.sh`](../scripts/details.sh), the `while :` loop). Its "Resets at" column is also local wall-clock time (`Sun 09:20`). So popup captures use the real clock and the machine's timezone. Pin `TZ=` for the capture. The smallest fix, if byte-stable popup PNGs matter, is a one-line change in that loop: `now=${AI_USAGE_NOW:-$(date +%s)}`. Otherwise, generate the snapshots relative to the real `now` just before capturing.

---

## Suggested shape for the capture script (for the follow-up ticket)

1. `demo/make-snapshots.sh` writes `claude.json`, `codex.json` and `cursor.json` into a temp cache, using the real `now` and `fetched_at: 9999999999`.
2. `demo/demo.conf` contains `@ai_usage_cache_dir`, `terminal-features ',*:RGB'`, the catppuccin `@thm_*` colours, `status-interval 1`, and `run-shell <repo>/ai_usage.tmux`.
3. One `.tape` per image. Under `Hide`, it starts `tmux -L demo -f demo.conf`, sets `AI_USAGE_NO_REFRESH`, and attaches through an outer tmux. Then, under `Show`, it does `Sleep`/`Wait`, then `Screenshot` or `resize-pane` steps, then `Output`.
4. Run it locally with `brew install vhs`, or in a `workflow_dispatch` job with `charmbracelet/vhs-action` on `ubuntu-latest` plus `apt-get install tmux jq`.
