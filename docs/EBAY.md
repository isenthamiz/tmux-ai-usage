# eBay corporate profile

Use **`@ai_usage_profile 'ebay'`** on an eBay-managed Mac. Personal installs keep the default **`personal`** profile.

## Corp fork and TPM

GitHub.com and `github.corp.ebay.com` are **different** hosts — there is no “Fork” button across them. Create a corp repo and **mirror or push** from public upstream. Prefer **`github-cli.corp.ebay.com`** for `git clone` / `git push` ([SDDZ GitHub FAQ](https://ebay.atlassian.net/wiki/spaces/ESIHOME/pages/151268909)). That hostname exists only on **corp DNS** (eBay laptop + GlobalProtect on the **eBay** gateway). If `Could not resolve host: github-cli.corp.ebay.com`, connect VPN or override:

```bash
export CORP_GITHUB_HOST=github.corp.ebay.com
```

Then re-run `initial-mirror` or `push-corp`. If push redirects to SSO or fails, run the sync from the eBay laptop instead.

### A. One-time: create corp repo + full mirror

1. In the browser: [github.corp.ebay.com](https://github.corp.ebay.com) → your org (e.g. `DataGov`) → **New repository** → `tmux-ai-usage` (empty, no README).
2. Create a corp PAT: [Settings → Tokens](https://github.corp.ebay.com/settings/tokens), classic scopes **`repo`** and **`workflow`** (required because this repo ships `.github/workflows/test.yml`). A `repo`-only token cannot push `main`.
3. From a machine that can reach GitHub.com and corp (eBay VPN):

```bash
export CORP_GITHUB_TOKEN='your-corp-pat'
export CORP_GITHUB_ORG='DataGov'    # your org or corp username

cd /path/to/tmux-ai-usage
scripts/ebay/sync-to-corp.sh initial-mirror
```

That pushes **`main` and tags** (not every feature branch or github.com `refs/pull/*`, which corp rejects). For all branches: `MIRROR_ALL_BRANCHES=1 scripts/ebay/sync-to-corp.sh initial-mirror` (still needs **`workflow`** on the PAT).

### B. What lives where

| Location | Owns |
|----------|------|
| [github.com/isenthamiz/tmux-ai-usage](https://github.com/isenthamiz/tmux-ai-usage) | **General** plugin: `personal` profile, providers, render, tests, CI — safe for public |
| github.corp.ebay.com/…/tmux-ai-usage | **General** (merged from upstream) **plus eBay-only** files below |

**Corp-only paths** (do not commit to github.com):

- `docs/EBAY.md` (this file)
- `scripts/ebay/` (`capture-usage.sh`, `sync-to-corp.sh`, …)
- `scripts/lib/ebay_acquire.sh`, `scripts/lib/normalize.ebay.jq`
- `scripts/providers/*/acquire.ebay.sh`
- `test/normalize_ebay.bats`, `test/profile_ebay.bats`

**Shared** (public first, then merge to corp): `@ai_usage_profile`, `scripts/lib/profile.sh`, `refresh.sh` / `smoke.sh` routing, Claude Code `PATH` helpers, etc.

### C. Ongoing workflow

**Personal laptop** (clone from github.com):

```bash
# feature work → public
git push origin main

# optional: update local main from your fork
scripts/ebay/sync-to-corp.sh pull-upstream   # or: sync (same fetch/merge)
```

Do **not** use `push-corp` from personal after corp has eBay-only commits on `main` — the script will refuse.

**eBay laptop** (clone from corp, add upstream once):

```bash
git remote add upstream https://github.com/isenthamiz/tmux-ai-usage.git

# After you (or a teammate) pushed general work to github.com:
git fetch upstream
git merge upstream/main
git push origin main

# eBay-only edits (capture scripts, aIQ parsers, …):
git add scripts/ebay/ …   # corp-only paths only
git commit -m "…"
git push origin main      # corp only — never push to github.com
```

**First-time publish of this split:** push general commits to github.com, then on the corp clone merge upstream and add a corp-only commit with the files in the table above.

Suggested remotes / TPM: `scripts/ebay/sync-to-corp.sh print-remotes` (corp clone only).

Tokens stay in the environment for that run — the script does **not** write them into `git config`.

### D. eBay laptop: TPM

```tmux
set -g @plugin 'https://github-cli.corp.ebay.com/DataGov/tmux-ai-usage.git'
set -g @ai_usage_profile 'ebay'
```

`prefix + I` (TPM install), then `prefix + r`. Use the same URL with `github-cli` for git, not `github.corp.ebay.com`, on CLI operations.

## Phase 1: capture files

eBay plan quota is **monthly capacity (aIQ)**, not vendor 5h/wk windows. Until CLI parsers land, refresh reads JSON capture files:

| File | Source |
|------|--------|
| `$CACHE/ebay-capture/claude.json` | aIQ card or `claude` → `/usage` |
| `$CACHE/ebay-capture/cursor.json` | aIQ card or Cursor CLI → `/usage` |
| `$CACHE/ebay-capture/codex.json` | aIQ or Codex usage UI |

Schema:

```json
{"provider": "claude", "mtd_usd": 42.5, "cap_usd": 150}
```

Write captures with:

```bash
scripts/ebay/capture-usage.sh claude 42.5 150
```

Then:

```bash
AI_USAGE_PROFILE=ebay scripts/smoke.sh
```

Status bars show a single **`mo`** window (month-to-date % of cap). Update captures when aIQ changes or automate in a later phase.

## References (eBay internal)

- [aIQ – Request guide](https://ebay.atlassian.net/wiki/spaces/AITOOLS/pages/288457414)
- [eBay AI Tool & Connectivity Map](https://github.corp.ebay.com/ebay-collab-hub/PDLC-reimagined/blob/main/eBay%20AI%20Tool%20&%20Connectivity%20Map.md)