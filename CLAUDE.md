# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

tmux-ai-usage is a TPM (tmux plugin manager) plugin that shows plan-quota usage bars for AI coding agents (Claude, Codex, Cursor) in the tmux status line. It is configured through tmux options.

## Status: spec complete, no code yet

There are no build, lint, or test commands yet. `SPEC.md` is the build-ready v1 spec: architecture, file tree, usage-snapshot format, per-provider data sources, look, options and testing. Build from it, and don't reopen a decision it records without asking.

Each section of `SPEC.md` links the closed GitHub issue that holds the reasoning behind it. The issues are indexed by the wayfinder map, the issue labelled `wayfinder:map`.

## Domain vocabulary

`GLOSSARY.md` is the source of truth for terms. Use its words exactly (Provider, Plan quota, Quota window, Usage, Reset, Usage bar) in code, docs, and issues. Keep scope within these limits:

- The plugin reports **plan quota** only. It does not report *spend* (money or tokens against a self-set budget) or *session context* (how full one conversation's context window is).
- There is one account per provider.
- A provider can have several quota windows running at once (for example a rolling 5-hour window and a weekly window). Each window gets its own usage bar, and each bar shows the time until reset.

When a new domain term comes up, add it to `GLOSSARY.md` rather than defining it elsewhere.
