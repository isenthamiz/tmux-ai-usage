# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

tmux-ai-usage is a TPM (tmux plugin manager) plugin that shows plan-quota usage bars for AI coding agents (Claude, Codex, Cursor) in the tmux status line. It is configured through tmux options.

## Status: v1 under construction

`SPEC.md` is the build-ready v1 spec: architecture, file tree, usage-snapshot format, per-provider data sources, look, options and testing. Build from it, and don't reopen a decision it records without asking. The implementation work is tracked as GitHub issues labelled `ready-for-agent`.

## Commands

- `make test`: shellcheck on every script and test file, then the bats suite. Dev dependencies: `brew install bats-core shellcheck jq`.
- `make lint` / `make unit`: either half on its own.
- `bats test/render.bats`: one test file. `bats -f '<name regex>' test/refresh.bats`: one test.

All scripts must run on macOS `/bin/bash` 3.2. Tests run only at the seams `SPEC.md` names: each provider's `normalize.jq` against fixtures, and `scripts/render.sh` behind PATH shims in `test/shims/`, with the clock injected through `AI_USAGE_NOW`.

Each section of `SPEC.md` links the closed GitHub issue that holds the reasoning behind it. The issues are indexed by the wayfinder map, the issue labelled `wayfinder:map`.

## Domain vocabulary

`GLOSSARY.md` is the source of truth for terms. Use its words exactly (Provider, Plan quota, Quota window, Usage, Reset, Usage bar) in code, docs, and issues. Keep scope within these limits:

- The plugin reports **plan quota** only. It does not report *spend* (money or tokens against a self-set budget) or *session context* (how full one conversation's context window is).
- There is one account per provider.
- A provider can have several quota windows running at once (for example a rolling 5-hour window and a weekly window). Each window gets its own usage bar, and each bar shows the time until reset.

When a new domain term comes up, add it to `GLOSSARY.md` rather than defining it elsewhere.
