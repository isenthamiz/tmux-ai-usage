# Can the renderer learn the tmux client width?

Resolves [#36](https://github.com/isenthamiz/tmux-ai-usage/issues/36). Researched 2026-11-19 against tmux 3.5a (the local `tmux -V`) on macOS. Source citations are to the [`3.5a` tag](https://github.com/tmux/tmux/tree/3.5a). Experiments ran on throwaway servers (`tmux -L wf36-in` / `-L wf36-out`, `-f /dev/null`). Each inner client was attached inside a pane of an outer server, so its width could be set with `resize-window`.

## Answer

**Yes.** There are two reliable ways to do it.

1. **Pass the width as an argument:** `#('…/render.sh' all #{client_width})`. tmux expands `#{client_width}` inside `#()` for each client before running the command. Each attached client gets its own job, with its own width and its own cached output. A resize re-runs the command at once and does not wait for `status-interval`. The catch is that until the new run finishes, that client shows the **previous width's output**. A client's first render is blank.
2. **Let tmux choose per redraw:** `render.sh` prints a tmux format conditional, for example `#{?#{e|<:#{client_width},100},<narrow>,<wide>}`. tmux re-expands `#()` output as a format, so the conditional is evaluated for each client on every redraw. This needs no width argument and no job re-run, so the output is never stale after a resize. It requires tmux ≥ 3.2 for `e|<`-style numeric comparisons.

Do **not** have `render.sh` call `tmux display -p '#{client_width}'` itself. With no `-c`, tmux picks one client, which is wrong when several clients of different widths are attached.

## Findings

### 1. `#{client_width}` is expanded inside `#()` arguments

- [`format_job_get`](https://github.com/tmux/tmux/blob/3.5a/format.c#L351-L414) runs `expanded = format_expand1(&next, cmd)` on the command text before `job_run(expanded, …)`. Every `#{…}` inside `#(…)` is therefore expanded with the format tree of the status line being drawn.
- That tree is built per client: [`status_redraw`](https://github.com/tmux/tmux/blob/3.5a/status.c#L369-L400) calls `format_create(c, …, FORMAT_STATUS)` and `format_defaults(ft, c, …)`. `client_width` is "Width of client" (tmux(1), FORMATS table).
- Verified: `status-right "[#(probe.sh #{client_width})]"` logged `args=[100]` for a 100-column client and `args=[60]` for a 60-column client.

### 2. Several attached clients get independent jobs and output

- The job cache is **per client**. `format_job_get` uses `ft->client->jobs` (a tree on the client), and falls back to the global `format_jobs` tree only when there is no client ([format.c#L360-L368](https://github.com/tmux/tmux/blob/3.5a/format.c#L360-L368)).
- Verified with two clients on one session, at 100 and 60 columns. Each showed its own width (`[W=100]`, `[W=60]`), and the log showed one run per client per redraw.
- Cost: with N attached clients, `render.sh` runs N times per redraw cycle. The render path must stay cheap (read the cached usage snapshot, never fetch).
- A detached client's job tree is freed ([`format_lost_client`](https://github.com/tmux/tmux/blob/3.5a/format.c#L455-L461), called from `server_client_lost`). A re-attaching client therefore starts from a blank first render again. Entries unused for an hour are also tidied ([`format_job_tidy`](https://github.com/tmux/tmux/blob/3.5a/format.c#L418-L441)).

### 3. A resize re-renders at once; it does not wait for `status-interval`

- `MSG_RESIZE` → `recalculate_sizes()` + `server_redraw_client(c)` ([server-client.c#L2819-L2835](https://github.com/tmux/tmux/blob/3.5a/server-client.c#L2819-L2835)). `server_redraw_client` sets `CLIENT_ALLREDRAWFLAGS`, which includes `CLIENT_REDRAWSTATUS` ([server-fn.c](https://github.com/tmux/tmux/blob/3.5a/server-fn.c), [tmux.h#L1908](https://github.com/tmux/tmux/blob/3.5a/tmux.h#L1908)).
- `status-interval` is only a periodic timer that sets `CLIENT_REDRAWSTATUS` ([`status_timer_callback`](https://github.com/tmux/tmux/blob/3.5a/status.c#L178-L199)). Any other redraw cause (resize, window switch, new window, a job finishing) also redraws the status line.
- Verified with `status-interval 0` (timer disabled). Resizing a client from 100 to 120 columns started `probe.sh 120` immediately, and the frame showed `[W=120]` 0.2 s later. Resizing one client also re-ran the other client's job, because `recalculate_sizes` redraws the session's clients.
- Rapid resizes collapse. Three resizes 0.1 s apart (95 → 96 → 97) produced runs for 95 and 97 only, and the final frame was correct.

### 4. How `#()` caching keys on the command string

- The cache key is `(tag, cmd)`, where `cmd` is the **unexpanded** text inside `#(…)` ([`format_job_cmp`](https://github.com/tmux/tmux/blob/3.5a/format.c#L77-L86)). A new width is therefore *not* a new cache entry. The client's single entry stores the last `expanded` string next to the last output.
- When the expanded string differs from the stored one (for example, the width changed), `force = 1`. Any in-flight job is killed (`job_free`) and the command is restarted immediately ([format.c#L385-L404](https://github.com/tmux/tmux/blob/3.5a/format.c#L385-L404)).
- While the new run is in flight, tmux returns the entry's **old output**, which was rendered for the old width. tmux(1): "tmux does not wait for #() commands to finish; instead, the previous result from running the same command is used, or a placeholder if the command has not been run before." When the job completes, `format_job_complete` calls `server_status_client`, and the status line redraws with the new output.
  - Verified with a probe that sleeps 1.5 s. After a resize from 120 to 90, the frame read `[W=120]` at about 0.2 s and 0.8 s, and `[W=90]` by about 1.4 s.
- **First render is blank.** With no previous output, `fj->out == NULL` → `""`. Verified: a newly attached client showed `[]` until its 3 s probe finished. If the job is still running more than 1 s after it started and has produced nothing, a redraw shows the placeholder `<'cmd' not ready>` instead ([format.c#L405-L406](https://github.com/tmux/tmux/blob/3.5a/format.c#L405-L406)).
- **Re-run on every redraw, rate-limited to once per second.** With an unchanged expanded string, the command is re-run on any redraw when no job is running and `fj->last != time(NULL)`. A job's completion itself triggers a redraw. So a command that takes **≥ 1 s** keeps itself running in a loop, regardless of `status-interval`.
  - Verified: a 2 s probe with `status-interval 0` ran every 2 s while idle (`18:36:23, :25, :27, :29, :31`).
  - A fast probe with `status-interval 15` ran only on the 15 s timer.
  - This is another reason `render.sh` must finish well under a second.

### 5. `#()` output is re-expanded as a format, so tmux can pick the width variant itself

- `format_job_get` returns `format_expand1(&next, fj->out)` ([format.c#L413](https://github.com/tmux/tmux/blob/3.5a/format.c#L413)). This is why `render.sh`'s `#[fg=…]` styles work at all, and it also means `#{…}` in the output is evaluated in the client's context on **every** redraw. `#()` inside the output is disabled (`FORMAT_EXPAND_NOJOBS`).
- Verified: a command that prints `#{?#{e|>=:#{client_width},100},WIDE-#{client_width},NARROW-#{client_width}}` showed `WIDE-120` on a 120-column client and `NARROW-70` on a 70-column client, from the same cached output. 0.15 s after resizing the first client to 90 it showed `NARROW-90`, with no job involved.
- Numeric comparison operators in formats arrived in tmux 3.2 ("Add numeric comparisons for formats", [CHANGES](https://github.com/tmux/tmux/blob/3.5a/CHANGES), 3.1c → 3.2 section). Plain `#{?cond,a,b}` and `#{client_width}` are older.
- A consequence: any literal `#` in usage text must be written as `##`. This already applies today.

### 6. Asking tmux from inside `render.sh` is unreliable

- `tmux display -p '#{client_width}'` without `-c` resolves to a single "best" client. Verified: with clients at 120 and 70 columns attached, it returned `70` regardless of which client's status line was being drawn. `run-shell` has the same problem. `display -c <name>` works, but needs `#{client_name}` passed in as an argument anyway, plus an extra tmux round-trip per render. Passing `#{client_width}` directly is strictly simpler.

## Implications for the design

| Approach | Correct per client | Stale after resize | Extra runs | tmux version |
|---|---|---|---|---|
| `#(render.sh all #{client_width})`, render.sh picks the step | Yes | Until the new run finishes (≈ render.sh runtime) | One run per client per resize | any |
| render.sh emits `#{?#{e|<:#{client_width},N},…}` with every step's text | Yes | Never | None | ≥ 3.2 |
| render.sh calls `tmux display -p` | No (multi-client) | n/a | +1 tmux call per run | any |

With a fast `render.sh` (cache read only), the argument approach is stale for well under a second. Its cost is that the first render is blank, which happens anyway. The format-conditional approach avoids staleness entirely, but the output carries every step's text, nested in conditionals. The choice between them belongs to [#38](https://github.com/isenthamiz/tmux-ai-usage/issues/38) and the steps it settles on.
