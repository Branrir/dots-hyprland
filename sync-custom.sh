#!/usr/bin/env bash
# Keep the fork's `custom` branch (our changes) on top of end-4 upstream, then
# update the installed dots from it.
#
#   1. fork main  <- upstream main   (fast-forward only: main carries nothing of ours)
#   2. rebase this branch onto it, and force-push it (with lease)
#   3. ./setup exp-update            (its `git pull --ff-only` is then a no-op)
#
# Run it from the installer clone (~/.cache/dots-hyprland) on the custom branch.
# A rebase conflict stops here: resolve it, `git rebase --continue`, run again.
set -euo pipefail
cd "$(dirname "$0")"

branch=$(git branch --show-current)
if [[ -z "$branch" || "$branch" == main ]]; then
  echo "sync-custom: run this on the custom branch, not '${branch:-detached HEAD}'" >&2
  exit 1
fi
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "sync-custom: commit or stash local changes first" >&2
  exit 1
fi
git remote get-url upstream &>/dev/null \
  || git remote add upstream https://github.com/end-4/dots-hyprland.git

git fetch --multiple upstream origin
git push origin upstream/main:refs/heads/main
git rebase upstream/main
git push --force-with-lease origin "$branch"

if [[ "${1:-}" == --no-update ]]; then
  echo "sync-custom: synced; skipping ./setup exp-update"
else
  ./setup exp-update
fi
