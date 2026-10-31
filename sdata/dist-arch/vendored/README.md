# Vendored packages

Packages the dots need that no official Arch/CachyOS repo ships. They live here,
in the fork, instead of coming from the AUR (or chaotic-aur, which builds the
same AUR PKGBUILDs): every source is the project's own release or a pinned
commit, verified by sha256, and every change to these files is reviewed in a
rebase like the rest of the fork.

`install-deps.sh` builds these first (`makepkg -si --asdeps`), so the meta
packages find them installed. Of the meta packages' dependencies it installs
only the missing ones (`pacman -T`), from the official repos: one no repo has
fails the install, and one only chaotic-aur has (an AUR build) is refused.

| Package | Source | Reviewed from |
|---|---|---|
| `illogical-impulse-darkly` (provides `darkly-bin`) | Darkly's own release asset (Bali10050/darkly) | AUR `darkly-bin` 0.5.42-1, unchanged apart from names and comments |
| `illogical-impulse-space-grotesk` (provides `otf-space-grotesk`) | floriankarsten/space-grotesk release 2.0.0 | new (the AUR one is a 15-package bundle with unchecked sources) |
| `illogical-impulse-readex-pro` (provides `ttf-readex-pro`) | ThomasJockin/readexpro at a pinned commit | new |

They are named after illogical-impulse rather than the packages they replace:
chaotic-aur carries `ttf-readex-pro` too, and a same-named repo package with a
higher version would replace the reviewed one on the next `pacman -Syu`.

To update one: bump `pkgver` (or `_commit`), download the new source yourself,
put its `sha256sum` in, and look at what changed upstream.
