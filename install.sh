#!/bin/sh
# Link this repo into place. Safe to re-run; anything it would replace is
# moved aside to <name>.pre-dotfiles first.
#   ~/.config/caelestia            -> caelestia/
#   ~/.local/share/fonts/InstrumentSerif -> fonts/InstrumentSerif/
#   download-sorter + appimage-desktop user services, enabled
set -eu

repo="$(cd "$(dirname "$0")" && pwd)"
config="${XDG_CONFIG_HOME:-$HOME/.config}"
data="${XDG_DATA_HOME:-$HOME/.local/share}"

link() { # link <target in repo> <path>
    if [ -L "$2" ] && [ "$(readlink -f "$2")" = "$(readlink -f "$1")" ]; then
        return
    fi
    if [ -e "$2" ] || [ -L "$2" ]; then
        if [ -d "$2" ] && [ ! -L "$2" ] && [ -d "$1" ]; then
            # Keep local-only files (tokens, backups) from an existing dir.
            cp -an "$2"/. "$1"/
        fi
        mv "$2" "$2.pre-dotfiles"
        echo "moved existing $2 to $2.pre-dotfiles"
    fi
    mkdir -p "$(dirname "$2")"
    ln -s "$1" "$2"
    echo "linked $2"
}

link "$repo/caelestia" "$config/caelestia"
link "$repo/fonts/InstrumentSerif" "$data/fonts/InstrumentSerif"
fc-cache -f "$data/fonts" >/dev/null

[ -f "$repo/caelestia/ha-token" ] || echo "note: put a Home Assistant token in $repo/caelestia/ha-token (chmod 600) for the lock screen cards"

if [ ! -f "$config/download-sorter/config.toml" ]; then
    mkdir -p "$config/download-sorter"
    cp "$repo/download-sorter/config.example.toml" "$config/download-sorter/config.toml"
    echo "created $config/download-sorter/config.toml"
fi
for unit in download-sorter appimage-desktop; do
    systemctl --user enable --now "$repo/download-sorter/$unit.service" >/dev/null 2>&1 \
        || systemctl --user enable --now "$repo/download-sorter/$unit.service"
done
echo "services: $(systemctl --user is-active download-sorter appimage-desktop | tr '\n' ' ')"
