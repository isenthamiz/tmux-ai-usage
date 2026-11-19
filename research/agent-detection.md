# What does tmux report as the running command for each AI agent?

Resolves #37. Researched 2026-11-19.

## Answer

`#{pane_current_command}` is the name of the process leading the pane
tty's **foreground process group**. On macOS that is the kernel's `p_comm`:
the basename of the file that was actually exec'd, after symlinks are
resolved, cut to 16 characters. `argv[0]` plays no part on macOS. On Linux
it is the basename of `argv[0]`.

| Provider / install | macOS `pane_current_command` | Linux (from source) |
|---|---|---|
| Claude Code, native installer (`~/.local/bin/claude` → `versions/<ver>`) | **the version string, e.g. `2.1.328`** (observed live) | `claude` |
| Claude Code, Homebrew cask | `claude` | `claude` |
| Claude Code, npm (`bin/claude.exe` hard-linked to the native binary) | `claude.exe` | `claude` |
| Codex CLI, Homebrew cask (native binary) | `codex` | `codex` |
| Codex CLI, npm on Node ≥ 22.15 / 23.11 (`process.execve`) | `codex` | `codex` |
| Codex CLI, npm on older Node (child `spawn`) | `node` | `node` |
| Cursor CLI (`agent` / `cursor-agent`, install script or cask) | **`node`** | `agent` or `cursor-agent` (the launcher sets `argv[0]` with `exec -a "$0"`) |
| Any agent behind a wrapper script that does not `exec` | `bash`, `sh`, … | same |

So `pane_current_command` on its own picks out Claude and Codex in their
usual installs. Claude matches `claude`, `claude.exe` or a bare
`N.N.N` version. Codex matches `codex`. It **cannot** pick out Cursor on
macOS, because Cursor shows up as `node`, like any other Node program.
A cheap, reliable rule:

1. Classify by `pane_current_command` (free, because tmux has already
   computed it): `claude` | `claude.exe` | `^[0-9]+\.[0-9]+\.[0-9]+$` →
   claude. `codex` → codex. `agent` | `cursor-agent` → cursor.
2. Otherwise, for `node`, a shell name, or anything else, run **one**
   `ps -t <pane_tty> -o pid=,pgid=,tpgid=,args=` and look at the args of
   the foreground process group (rows where `pgid == tpgid`). The
   foreground group is the pgid tmux itself reads. Cursor's node process
   carries `…/cursor-agent/versions/<ver>/index.js` in its args. Codex on
   old Node carries `@openai/codex` / `codex.js`. A non-exec wrapper's
   child is in the same group. A single-pid `ps` measured about 1.4 ms on
   this machine (50 runs in 0.07 s). A full `ps -A` costs about 38 ms, so
   don't do that on every redraw.

The active pane's details **can** be passed into `render.sh` through
format expansion in the `#()` arguments. tmux expands `#{…}` inside the
`#()` command string before it runs the command. Each distinct expanded
string is its own job, and a change in the expansion makes the job re-run
at once rather than wait for `status-interval`. For example:

```
#('…/scripts/render.sh' all #{q:pane_current_command} #{q:pane_tty})
```

Use the `q:` modifier, because the command goes through `/bin/sh`.

## Sources examined

- tmux 3.5a source (the version installed here):
  - `osdep-darwin.c` `osdep_get_name`: `tcgetpgrp(fd)`, then
    `proc_pidinfo(pgrp, PROC_PIDT_SHORTBSDINFO)` → `pbsi_comm`.
  - `osdep-linux.c` `osdep_get_name`: `tcgetpgrp(fd)`, then the first
    NUL-terminated field of `/proc/<pgrp>/cmdline`.
  - `format.c` `format_cb_current_command`: falls back to the pane's start
    argv or shell, then `parse_window_name` (`names.c`), which strips
    leading `-` and `exec `, cuts at the first space and takes the basename
    of an absolute path.
  - `format.c` `format_job_get`: expands the `#()` command with
    `format_expand1` before `job_run`, and sets `force = 1` when the
    expanded string differs from the last one.
  - `tmux.1`: `pane_current_command` "Current command if available",
    `pane_pid` "PID of first process in pane", the `#()` section (runs via
    `/bin/sh`, does not wait, reuses the previous output), and the `q:`
    modifier (escapes sh(1) special characters).
- Claude Code: npm `@anthropic-ai/claude-code@2.1.328`. Its `bin` is
  `bin/claude.exe`. `install.cjs` hard-links or copies the platform native
  binary over that placeholder ("`claude` execs the native binary
  directly — no Node.js process stays resident"). `cli-wrapper.cjs` is a
  `spawnSync` fallback, so that path shows `node`. Homebrew cask
  `claude-code`: `binary "claude"`.
- Codex CLI: npm `@openai/codex@0.170.0` `bin/codex.js`. It finds
  `vendor/<triple>/codex/codex`, then calls
  `process.execve(binaryPath, [binaryPath, …])` when that function exists.
  Otherwise it calls `spawn(binaryPath, …, {stdio: "inherit"})`, which
  leaves the child in node's process group. Homebrew cask `codex`:
  `binary "bin/codex"`.
- Cursor CLI: `https://cursor.com/install` (build `2026.11.19-f005e9d`)
  unpacks into `~/.local/share/cursor-agent/versions/<ver>/` and symlinks
  `~/.local/bin/agent` and `~/.local/bin/cursor-agent` to its
  `cursor-agent`. That file is a bash launcher that ends in
  `exec -a "$0" "$SCRIPT_DIR/node" [flags] "$SCRIPT_DIR/index.js" "$@"`,
  using a bundled binary that is literally named `node`. It also exports
  `CURSOR_INVOKED_AS`. Homebrew cask `cursor-cli` installs the same
  launcher.
- This machine, read-only: tmux 3.5a. `claude` is installed
  (`~/.local/bin/claude` → `~/.local/share/claude/versions/2.1.328`, a
  Mach-O binary). `codex`, `cursor-agent` and `agent` are **not**
  installed, so the Codex and Cursor rows come from source plus the
  simulation below.

## Empirical checks

**Live Claude pane (this session).**
`tmux display -p -t %1 '#{pane_current_command}'` → `2.1.328`.
`ps` for that pane:

```
  PID  PPID  PGID TPGID UCOMM    COMM
65109 55833 65109 65433 zsh      -zsh      <- #{pane_pid} (login shell)
65433 65109 65433 65433 2.1.328  claude    <- foreground group leader
60394 65433 65433 65433 caffeinate caffeinate
```

`pane_pid` is the shell, not the agent. The agent is a child of it in its
own process group, the one that equals `tpgid`. On macOS, `ps -o comm`
shows `claude` (argv[0]), while `ps -o ucomm` shows `2.1.328`, the same
name tmux reads. Claude Code's own tool subprocesses (the Bash tool that
ran these commands) run outside the pane's tty and process group. While
the agent works, the pane keeps reporting the agent.

**Simulation on a throwaway server** (`tmux -L wf-research`, since killed).
A tiny compiled `sleep` binary stood in for each native agent. A copied
`/bin/sleep` is SIGKILLed by code signing.

| Pane started as | `pane_current_command` | foreground process args |
|---|---|---|
| `bin/claude` → symlink to `versions/2.1.999` | `2.1.999` | `…/bin/claude` |
| bash launcher, `exec -a "$0" node …` (Cursor shape), run as `bin/agent` | `node` | `…/bin/agent -e …` |
| `node codex.js` that calls `process.execve(vendor/codex)` (Node 26) | `codex` | `…/vendor/codex` |
| `node codex.js` that calls `spawn(vendor/codex)` | `node` | `node codex-spawn.js` (+ child `codex`, same pgid) |
| bash script that runs `bin/claude` without `exec` | `bash` | `/bin/bash wrap.sh` (+ child `2.1.999`, same pgid) |
| interactive zsh, then `bin/claude` typed | `2.1.999` | `…/bin/claude` (own pgid = tpgid) |

**`#()` argument expansion.** On the same server, with a client attached
through `script(1)`, `status-interval 15` and
`status-right "#(log.sh '#{pane_current_command}' '#{pane_pid}' '#{pane_id}')"`:
each `select-pane` produced a new invocation within about 1 s with that
pane's values (`2.1.999 … %0`, `node … %1`, `codex … %2`, `node … %3`).
Starting `bin/claude` in the active pane, or killing it, also re-ran the
job within a second, without waiting 15 s. In each case the change in the
expanded command string triggered the re-run.

## Implications for the plugin

- Pass `#{q:pane_current_command}` (and `#{q:pane_tty}` for the fallback)
  as arguments. Don't call `tmux display` from inside `render.sh`, because
  that is another fork, and `#()` jobs have no pane context of their own.
- The expansion uses the **attached client's** current pane, so each
  client gets its own job.
- When the pane switches, tmux shows the previous output until the new
  job finishes. It never blocks the redraw.
- Because jobs are keyed by expanded string, a fast `render.sh` matters,
  but there is no per-redraw cost beyond what `all` already pays. The one
  extra `ps -t` runs only when the name is ambiguous.
- Matching the version-number name is specific to Claude's native
  installer, and it changes on every Claude update. Match the
  `N.N.N` pattern, never a fixed version.
- Detection reflects the foreground process only. An agent that has been
  backgrounded (`^Z`) or is running under `nohup` in the pane will not be
  detected.
