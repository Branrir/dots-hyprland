# Vendored packages

Packages the dots need that no official Arch/CachyOS repo ships. They live here,
in the fork, instead of coming from the AUR (or chaotic-aur, which builds the
same AUR PKGBUILDs): every source is the project's own release or a pinned
commit, verified by sha256, and every change to these files is reviewed in a
rebase like the rest of the fork.

`install-deps.sh` builds these first (`makepkg -si --asdeps`), so the meta
packages find them installed; the meta packages' other dependencies come from
the official repos through pacman, and a dependency no repo has fails the
install instead of quietly pulling from the AUR.

| Package | Source | Reviewed from |
|---|---|---|
| `darkly-bin` | Darkly's own release asset (Bali10050/darkly) | AUR `darkly-bin` 0.5.42-1, unchanged apart from comments |
| `otf-space-grotesk` | floriankarsten/space-grotesk release 2.0.0 | new (the AUR one is a 15-package bundle with unchecked sources) |
| `ttf-readex-pro` | ThomasJockin/readexpro at a pinned commit | new |

To update one: bump `pkgver` (or `_commit`), download the new source yourself,
put its `sha256sum` in, and look at what changed upstream.
