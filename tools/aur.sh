#!/bin/bash
# Writes the AUR recipe, aur/caelestia-plus-git/{PKGBUILD,.SRCINFO}, from
# pkg/PKGBUILD: the same packages, built from the public GitHub repo instead
# of this checkout.
#
#   tools/aur.sh
#
# Publishing it needs an AUR account with your SSH key:
#   git clone ssh://aur@aur.archlinux.org/caelestia-plus-git.git /tmp/aur-cp
#   cp aur/caelestia-plus-git/{PKGBUILD,.SRCINFO} /tmp/aur-cp/
#   cd /tmp/aur-cp && git add -A && git commit -m "Update" && git push

set -euo pipefail

repo=$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)
out=$repo/aur/caelestia-plus-git
mkdir -p "$out"

sed -e 's/^pkgbase=caelestia-plus$/pkgbase=caelestia-plus-git/' \
    -e 's|^source=("${pkgbase}::git+file://$(realpath "${startdir}/..")"|source=("caelestia-plus::git+https://github.com/moimart/caelestia-plus.git"|' \
    -e 's|"${srcdir}/${pkgbase}|"${srcdir}/caelestia-plus|g' \
    -e '1,4c\# Maintainer: moimart\n# caelestia-plus: a Caelestia-based Hyprland desktop (the shell, Hyprland\n# config and app configs), built from git. Generated from pkg/PKGBUILD by\n# tools/aur.sh in https://github.com/moimart/caelestia-plus.' \
    "$repo/pkg/PKGBUILD" > "$out/PKGBUILD"

grep -q 'git+https://github.com/moimart/caelestia-plus.git' "$out/PKGBUILD" || { echo "source not rewritten" >&2; exit 1; }
grep -q 'srcdir}/${pkgbase}' "$out/PKGBUILD" && { echo "pkgbase paths left" >&2; exit 1; }

(cd "$out" && makepkg --printsrcinfo > .SRCINFO)
echo "Wrote $out/PKGBUILD and .SRCINFO"
