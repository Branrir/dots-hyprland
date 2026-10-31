#!/usr/bin/env bash
# Keep the fork's `custom` branch (our changes) on top of end-4 upstream, then
# update the installed dots from it.
#
#   1. fork main  <- upstream main   (fast-forward only: main carries nothing of ours)
#   2. rebase this branch onto it; ./check-no-aur.sh (exit 1 if the rebase brought
#      an AUR package or helper back: nothing is pushed or installed then);
#      force-push it (with lease)
#   3. ./setup install-deps          (pacman -Syu, then the dots' packages: official
#                                     repos + sdata/dist-arch/vendored/, no AUR)
#   4. ./setup exp-update            (the dotfiles; its `git pull --ff-only` is a no-op)
#
# Options:
#   --no-deps        skip step 3
#   --no-sysupdate   step 3 without its pacman -Syu
#   --no-update      stop after step 2
#
# Run it from the installer clone (~/.cache/dots-hyprland) on the custom branch.
# A rebase conflict stops here: resolve it, `git rebase --continue`, run again.
set -euo pipefail
cd "$(dirname "$0")"

deps=true
sysupdate=true
update=true
for arg in "$@"; do
  case "$arg" in
    --no-deps) deps=false ;;
    --no-sysupdate) sysupdate=false ;;
    --no-update) update=false ;;
    *) echo "sync-custom: unknown option: $arg" >&2; exit 1 ;;
  esac
done

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
if ! ./check-no-aur.sh; then
  echo "sync-custom: stopping before the push and the install. The branch is rebased" >&2
  echo "  locally only; adapt the files above, commit, and run the update again." >&2
  exit 1
fi
git push --force-with-lease origin "$branch"

if ! $update; then
  echo "sync-custom: synced; skipping the package and dotfile update"
  exit 0
fi

if $deps; then
  if $sysupdate; then ./setup install-deps; else ./setup install-deps --skip-sysupdate; fi
fi
./setup exp-update
