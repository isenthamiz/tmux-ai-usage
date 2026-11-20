#!/bin/bash
# Sync github.com/isenthamiz/tmux-ai-usage → github.corp.ebay.com (CLI host).
# Uses HTTPS + PAT only (corp network blocks SSH). Never stores tokens in git config.
#
# One-time env (shell session):
#   export CORP_GITHUB_TOKEN='...'   # corp PAT: scopes repo + workflow (.github/workflows on main)
#   export CORP_GITHUB_ORG='DataGov' # or your user/org on corp
#
# Optional:
#   CORP_GITHUB_REPO=tmux-ai-usage
#   CORP_GITHUB_HOST=github-cli.corp.ebay.com
#   UPSTREAM_REPO_URL=https://github.com/isenthamiz/tmux-ai-usage.git
set -e

UPSTREAM_REPO_URL=${UPSTREAM_REPO_URL:-https://github.com/isenthamiz/tmux-ai-usage.git}
CORP_GITHUB_HOST=${CORP_GITHUB_HOST:-github-cli.corp.ebay.com}
CORP_GITHUB_REPO=${CORP_GITHUB_REPO:-tmux-ai-usage}
CORP_GITHUB_ORG=${CORP_GITHUB_ORG:-}
CORP_BRANCH=${CORP_BRANCH:-main}

_die() { echo "sync-to-corp: $*" >&2; exit 1; }

_preflight_corp_host() {
  if host "$CORP_GITHUB_HOST" >/dev/null 2>&1 \
    || dscacheutil -q host -a name "$CORP_GITHUB_HOST" 2>/dev/null | grep -q 'ip_address'; then
    return 0
  fi
  _die "DNS cannot resolve $CORP_GITHUB_HOST.

Connect GlobalProtect (eBay gateway, not TCGplayer) and retry, or run from the eBay laptop.

If only github.corp.ebay.com resolves on your network, try:
  export CORP_GITHUB_HOST=github.corp.ebay.com
  $0 $*"
}

_corp_url() { # prints authenticated push URL (ephemeral; not for git remote add)
  local org=$1 repo=$2 tok=$3
  printf 'https://x-access-token:%s@%s/%s/%s.git' "$tok" "$CORP_GITHUB_HOST" "$org" "$repo"
}

_corp_url_public() {
  local org=$1 repo=$2
  printf 'https://%s/%s/%s.git' "$CORP_GITHUB_HOST" "$org" "$repo"
}

_require_token() {
  [ -n "${CORP_GITHUB_TOKEN:-}" ] || _die "set CORP_GITHUB_TOKEN (corp PAT with repo scope)"
  [ -n "$CORP_GITHUB_ORG" ] || _die "set CORP_GITHUB_ORG (e.g. DataGov or your corp username)"
}

_usage() {
  cat <<'EOF'
Usage: sync-to-corp.sh <command>

Commands:
  initial-mirror     One-time: push main (+ tags) from github.com to an empty corp repo.
                     Set MIRROR_ALL_BRANCHES=1 to push every branch (not PR refs); needs workflow scope.
  pull-upstream      In this repo: fetch github.com and merge into current branch (default: main).
  push-corp          Push current branch to corp (set upstream after initial-mirror).
  sync               Fetch/merge github.com into local main (does not push corp — see EBAY.md).
  push-corp          Push local main to corp if corp has no extra commits (ebay-only guard).
  print-remotes      Show suggested git remote commands (no network).

Env:
  CORP_GITHUB_TOKEN   Corp PAT (required for push / initial-mirror)
  CORP_GITHUB_ORG     Target org or user on corp
  CORP_GITHUB_REPO    Default: tmux-ai-usage
  CORP_GITHUB_HOST    Default: github-cli.corp.ebay.com
  UPSTREAM_REPO_URL   Default: https://github.com/isenthamiz/tmux-ai-usage.git

Examples:
  export CORP_GITHUB_TOKEN='ghp_...'
  export CORP_GITHUB_ORG='DataGov'
  scripts/ebay/sync-to-corp.sh initial-mirror

  cd tmux-ai-usage && git remote add upstream https://github.com/isenthamiz/tmux-ai-usage.git
  scripts/ebay/sync-to-corp.sh sync
EOF
}

_mirror_push_fail_hint() {
  cat >&2 <<'EOF'
sync-to-corp: corp rejected the push. Common fixes:
  - Regenerate the corp PAT with classic scopes repo AND workflow
    (this repo has .github/workflows/test.yml on main).
  - Do not use git push --mirror: corp rejects refs/pull/* from github.com.
  - Use default initial-mirror (main + tags only) unless you need every branch.
EOF
}

_cmd_initial_mirror() {
  _require_token
  _preflight_corp_host initial-mirror
  local work url rc=0
  work=$(mktemp -d "${TMPDIR:-/tmp}/tmux-ai-usage-mirror.XXXXXX") || _die "mktemp failed"
  trap 'rm -rf "$work"' EXIT
  echo "Cloning public upstream (mirror) ..."
  git clone --mirror "$UPSTREAM_REPO_URL" "$work/repo.git"
  url=$(_corp_url "$CORP_GITHUB_ORG" "$CORP_GITHUB_REPO" "$CORP_GITHUB_TOKEN")
  echo "Pushing to $CORP_GITHUB_HOST/$CORP_GITHUB_ORG/$CORP_GITHUB_REPO ..."
  if [ -n "${MIRROR_ALL_BRANCHES:-}" ]; then
    echo "(MIRROR_ALL_BRANCHES=1: all heads, no github.com pull refs)"
    git -C "$work/repo.git" push "$url" '+refs/heads/*:refs/heads/*' || rc=$?
  else
    echo "(default: branch $CORP_BRANCH and tags only — enough for TPM)"
    git -C "$work/repo.git" push "$url" \
      "+refs/heads/$CORP_BRANCH:refs/heads/$CORP_BRANCH" || rc=$?
    if [ "$rc" -eq 0 ] && git -C "$work/repo.git" for-each-ref --format='%(refname)' refs/tags \
        | grep -q .; then
      git -C "$work/repo.git" push "$url" 'refs/tags/*:refs/tags/*' || rc=$?
    fi
  fi
  if [ "$rc" -ne 0 ]; then
    _mirror_push_fail_hint
    exit "$rc"
  fi
  echo "Done. Clone on eBay laptop:"
  echo "  git clone $(_corp_url_public "$CORP_GITHUB_ORG" "$CORP_GITHUB_REPO")"
}

_find_git_root() {
  local d
  d=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
  [ -d "$d/.git" ] || _die "run from a git checkout (expected repo root at $d)"
  printf '%s' "$d"
}

_cmd_pull_upstream() {
  local root remote
  root=$(_find_git_root)
  cd "$root"
  remote=upstream
  if ! git remote get-url "$remote" >/dev/null 2>&1; then
    echo "Adding remote upstream -> $UPSTREAM_REPO_URL"
    git remote add upstream "$UPSTREAM_REPO_URL"
  fi
  git fetch upstream
  git checkout "$CORP_BRANCH"
  if git merge-base --is-ancestor "upstream/$CORP_BRANCH" HEAD 2>/dev/null \
    && git merge-base --is-ancestor HEAD "upstream/$CORP_BRANCH" 2>/dev/null; then
    echo "Already even with upstream/$CORP_BRANCH"
    return 0
  fi
  git merge --no-edit "upstream/$CORP_BRANCH"
}

_cmd_push_corp() {
  _require_token
  _preflight_corp_host push-corp
  local root url corp_sha head_sha
  root=$(_find_git_root)
  cd "$root"
  git checkout "$CORP_BRANCH"
  url=$(_corp_url "$CORP_GITHUB_ORG" "$CORP_GITHUB_REPO" "$CORP_GITHUB_TOKEN")
  head_sha=$(git rev-parse HEAD)
  corp_sha=$(git ls-remote "$url" "refs/heads/$CORP_BRANCH" | awk 'NR==1{print $1}')
  if [ -n "$corp_sha" ] && [ "$corp_sha" != "$head_sha" ]; then
    if git merge-base --is-ancestor "$corp_sha" "$head_sha" 2>/dev/null; then
      :
    elif git merge-base --is-ancestor "$head_sha" "$corp_sha" 2>/dev/null; then
      _die "corp/main has commits not on this branch (eBay-only work?). \
Merge on the corp clone instead: git fetch upstream && git merge upstream/main && git push. \
Do not push-corp from a personal-only checkout."
    else
      _die "local main and corp/main have diverged. Reconcile on the eBay corp clone \
(fetch upstream, merge, push corp)."
    fi
  fi
  echo "Pushing $CORP_BRANCH to $CORP_GITHUB_HOST/$CORP_GITHUB_ORG/$CORP_GITHUB_REPO ..."
  git push "$url" "HEAD:refs/heads/$CORP_BRANCH"
}

_cmd_sync() {
  _cmd_pull_upstream
  cat <<'EOF'
sync-to-corp: updated local main from github.com (upstream).
Corp is not pushed from here while eBay-only commits live on corp/main.

On the eBay laptop (corp clone):
  git fetch upstream
  git merge upstream/main
  git push origin main

On personal: push new work to github.com only:
  git push origin main
EOF
}

_cmd_print_remotes() {
  local pub
  pub=$(_corp_url_public "${CORP_GITHUB_ORG:-<ORG>}" "$CORP_GITHUB_REPO")
  cat <<EOF
# On corp/eBay laptop (after corp repo exists):
git clone "$pub"
cd $CORP_GITHUB_REPO
git remote add upstream "$UPSTREAM_REPO_URL"

# On personal laptop (already cloned from github.com):
git remote add upstream "$UPSTREAM_REPO_URL"   # if missing
# Push to corp without saving token in config:
CORP_GITHUB_TOKEN=... CORP_GITHUB_ORG=... scripts/ebay/sync-to-corp.sh push-corp

TPM (~/.tmux.conf on eBay):
set -g @plugin '$pub'
set -g @ai_usage_profile 'ebay'
EOF
}

cmd=${1:-}
case $cmd in
  initial-mirror) _cmd_initial_mirror ;;
  pull-upstream) _cmd_pull_upstream ;;
  push-corp) _cmd_push_corp ;;
  sync) _cmd_sync ;;
  print-remotes) _cmd_print_remotes ;;
  -h|--help|help|'') _usage ;;
  *) _die "unknown command: $cmd (try --help)" ;;
esac