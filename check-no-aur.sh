#!/usr/bin/env bash
# Fail (exit 1) if the Arch install path of this branch would take anything from
# the AUR. Run by sync-custom.sh right after rebasing onto upstream, before the
# push and the install, so an upstream change that brings an AUR package back
# stops the update instead of reaching this machine.
#
# Checks, for every PKGBUILD in sdata/dist-arch/ (the illogical-impulse-* meta
# packages and vendored/):
#   1. each depends/makedepends entry is in an official repo, or is one of the
#      dots' own or vendored packages (by name or `provides`)
#   2. none of them resolves only through chaotic-aur (it builds AUR PKGBUILDs)
#   3. no source is fetched from aur.archlinux.org
# and that the install scripts do not run an AUR helper (yay/paru) again.
#
# Fix a finding by switching to an official package, or by adding a reviewed
# PKGBUILD to sdata/dist-arch/vendored/ (see its README).
#
# Usage: ./check-no-aur.sh [REPO_ROOT]   (default: this script's directory)
set -euo pipefail

root="${1:-$(dirname "$0")}"
dist="$root/sdata/dist-arch"
[[ -d "$dist" ]] || { echo "check-no-aur: no $dist" >&2; exit 2; }

pkgbuilds=()
for f in "$dist"/*/PKGBUILD "$dist"/vendored/*/PKGBUILD; do
  [[ -f "$f" ]] && pkgbuilds+=("$f")
done

# Read the fields we need from each PKGBUILD in a subshell, so nothing leaks.
fields() { # fields PKGBUILD -> "pkgname|provides...|depends...|makedepends...|source..."
  bash -c 'source "$1" >/dev/null 2>&1
    printf "%s|%s|%s|%s|%s\n" "${pkgname[*]}" "${provides[*]:-}" "${depends[*]:-}" \
      "${makedepends[*]:-}" "${source[*]:-}"' _ "$1"
}

declare -A local_pkg=()
for f in "${pkgbuilds[@]}"; do
  IFS='|' read -r names provides _ _ _ < <(fields "$f")
  for n in $names $provides; do local_pkg["${n%%[<>=]*}"]=1; done
done

problems=()
for f in "${pkgbuilds[@]}"; do
  rel="${f#"$root"/}"
  IFS='|' read -r _ _ depends makedepends sources < <(fields "$f")
  for dep in $depends $makedepends; do
    name="${dep%%[<>=]*}"
    [[ -n "${local_pkg[$name]:-}" ]] && continue
    repo=$(pacman -Sp --print-format '%r' "$dep" 2>/dev/null | tail -1 || true)
    if [[ -z "$repo" ]]; then
      problems+=("$rel: '$dep' is in no official repo (AUR?)")
    elif [[ "$repo" == chaotic-aur ]]; then
      problems+=("$rel: '$dep' only resolves through chaotic-aur (an AUR build)")
    fi
  done
  for src in $sources; do
    [[ "$src" == *aur.archlinux.org* ]] && problems+=("$rel: source from the AUR: $src")
  done
done

# AUR helpers run by the install scripts (definitions and comments are fine).
while IFS= read -r hit; do
  problems+=("${hit#"$root"/}: runs an AUR helper")
done < <(grep -n -H -E '^[[:space:]]*((x|v|try)[[:space:]]+)?(sudo[[:space:]]+)?(yay|paru)[[:space:]]|^[[:space:]]*(x|v|showfun)[[:space:]]+install-yay([[:space:]]|$)' \
  "$dist"/*.sh 2>/dev/null || true)

if (( ${#problems[@]} > 0 )); then
  echo "check-no-aur: the install would use the AUR:" >&2
  printf '  %s\n' "${problems[@]}" >&2
  echo "Switch to an official package, or add a reviewed PKGBUILD to sdata/dist-arch/vendored/." >&2
  exit 1
fi
echo "check-no-aur: ok (${#pkgbuilds[@]} PKGBUILDs, nothing from the AUR)"
