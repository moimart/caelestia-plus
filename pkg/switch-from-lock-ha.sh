#!/bin/sh
# One-off: replace the AUR caelestia-shell + lock-ha patch setup with this
# fork's package. Run as root: sudo ./switch-from-lock-ha.sh
set -eu
cd "$(dirname "$0")"

pkg="$(ls -t caelestia-shell-moimart-*.pkg.tar.zst | head -1)"

# The old hook would re-patch the new files during the install; remove it first.
rm -f /etc/pacman.d/hooks/caelestia-lock-ha.hook
rm -rf /usr/local/share/caelestia-lock-ha
# Installed by lock-ha's script, not owned by any package; the new package ships these.
rm -rf /etc/xdg/quickshell/caelestia/modules/lock/ha

# Answer "y" when asked to remove the conflicting caelestia-shell.
pacman -U "$pkg"
