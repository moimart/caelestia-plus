#!/bin/bash
# Moves a machine from configs symlinked into git checkouts (the old
# dotfiles, caelestia dots and hypr-config repos) to the caelestia-plus
# packages and its layers.
#
#   tools/switch-over.sh --host NAME [--overlay GIT-URL] [--dry-run]
#   tools/switch-over.sh --rollback
#
# Install the packages first (caelestia-plus-hypr, caelestia-plus-config and
# the shell from this repo). Every symlink it replaces is recorded in
# ~/.local/share/caelestia-plus/switch-over/, with what was there, so
# --rollback puts everything back as it was.

set -euo pipefail

config=${XDG_CONFIG_HOME:-$HOME/.config}
data=${XDG_DATA_HOME:-$HOME/.local/share}
state=$data/caelestia-plus/switch-over
# Overridable to rehearse against a staged install
xdg=${CAELESTIA_PLUS_XDG:-/etc/xdg}
host=
overlay=git@github.com:moimart/caelestia-plus-private.git
dry=0
rollback=0

while [ $# -gt 0 ]; do
    case $1 in
        --host) host=$2; shift 2 ;;
        --overlay) overlay=$2; shift 2 ;;
        --dry-run|-n) dry=1; shift ;;
        --rollback) rollback=1; shift ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

run() {
    if [ $dry = 1 ]; then echo "would: $*"; else "$@"; fi
}

# The links this replaces: config dirs, scripts, the font
links=(
    "$config/hypr" "$config/caelestia" "$config/kitty" "$config/foot" "$config/ghostty"
    "$config/fish" "$config/btop" "$config/fastfetch" "$config/uwsm" "$config/starship.toml"
    "$data/bin" "$data/fonts/InstrumentSerif"
)
services=(download-sorter appimage-desktop)

if [ $rollback = 1 ]; then
    [ -f "$state/links" ] || { echo "nothing to roll back ($state/links missing)" >&2; exit 1; }
    for unit in "${services[@]}"; do systemctl --user disable --now "$unit" 2>/dev/null || true; done
    while IFS=$'\t' read -r path target; do
        if [ -e "$path" ] && [ ! -L "$path" ]; then
            mv "$path" "$state/after-${path//\//_}"
        fi
        rm -f "$path"
        ln -s "$target" "$path"
        echo "restored $path -> $target"
    done < "$state/links"
    while IFS=$'\t' read -r unit file; do
        systemctl --user enable --now "$file" >/dev/null 2>&1 && echo "re-enabled $unit ($file)"
    done < "$state/services"
    fc-cache -f "$data/fonts" >/dev/null 2>&1 || true
    hyprctl reload >/dev/null 2>&1 || true
    stamp=$(date +%Y%m%d-%H%M%S)
    mv "$state/links" "$state/links.rolled-back-$stamp"
    mv "$state/services" "$state/services.rolled-back-$stamp"
    echo "Rolled back. What the switch-over made is kept in $state/after-*."
    exit 0
fi

[ -n "$host" ] || { echo "--host NAME is required (the profile in your overlay)" >&2; exit 2; }
for pkg in caelestia-plus-hypr caelestia-plus-config caelestia-shell-moimart; do
    pacman -Q "$pkg" >/dev/null 2>&1 || { echo "install $pkg first" >&2; exit 1; }
done
if [ "$(caelestia shell lock isLocked 2>/dev/null)" = true ]; then
    echo "the session is locked; unlock first" >&2
    exit 1
fi
[ -f "$state/links" ] && [ $dry = 0 ] && { echo "already switched over (see $state); --rollback first" >&2; exit 1; }

# A dry run keeps its notes somewhere throwaway
if [ $dry = 1 ]; then state=$(mktemp -d); else mkdir -p "$state"; fi

echo "== Recording the links"
: > "${state}/links.new"
for path in "${links[@]}"; do
    [ -L "$path" ] || continue
    printf '%s\t%s\n' "$path" "$(readlink "$path")" >> "$state/links.new"
    echo "  $path -> $(readlink "$path")"
done
: > "${state}/services.new"
for unit in "${services[@]}"; do
    file=$(systemctl --user show -p FragmentPath --value "$unit" 2>/dev/null || true)
    case $file in
        /usr/lib/*|"") ;;
        *) printf '%s\t%s\n' "$unit" "$file" >> "$state/services.new" ;;
    esac
done
if [ $dry = 1 ]; then
    rm -rf "$state"
else
    mv "$state/links.new" "$state/links"
    mv "$state/services.new" "$state/services"
fi

echo "== The overlay"
plus=$config/caelestia-plus
if [ ! -d "$plus/.git" ]; then
    run git clone -q "$overlay" "$plus"
fi
[ $dry = 1 ] || echo "$host" > "$plus/host"

# Moves a linked config dir aside and makes a real one, keeping the named
# local files (things that were never in git, like tokens)
unlink_dir() { # unlink_dir <path> [files to keep...]
    local path=$1; shift
    [ -L "$path" ] || return 0
    local target; target=$(readlink -f "$path")
    run rm "$path"
    run mkdir -p "$path"
    for keep in "$@"; do
        [ -e "$target/$keep" ] && run cp -a "$target/$keep" "$path/$keep"
    done
    return 0
}

echo "== The shell's config"
oldcaelestia=$(readlink -f "$config/caelestia" 2>/dev/null || true)
if [ -L "$config/caelestia" ]; then
    unlink_dir "$config/caelestia" ha-token cli.json lock-ha.json
    # Your shell.json, minus what the layers now provide
    if [ $dry = 0 ]; then
        python3 - "$oldcaelestia/shell.json" "$config/caelestia/shell.json" \
            "$xdg/caelestia/shell.json" "$plus/personal/caelestia/shell.json" "$plus/hosts/$host/caelestia/shell.json" <<'EOF'
import json, os, sys
live, out, *bases = sys.argv[1:]
home = os.path.expanduser("~")

def merged(base, over):
    base = dict(base)
    for k, v in over.items():
        base[k] = merged(base[k], v) if isinstance(base.get(k), dict) and isinstance(v, dict) else v
    return base

def same(a, b):
    if isinstance(a, str) and isinstance(b, str):
        return a.replace("~", home, 1) == b.replace("~", home, 1)
    return a == b

def without(full, base):
    diff = {}
    for k, v in full.items():
        if k not in base:
            diff[k] = v
        elif isinstance(v, dict) and isinstance(base[k], dict):
            sub = without(v, base[k])
            if sub:
                diff[k] = sub
        elif not same(v, base[k]):
            diff[k] = v
    return diff

base = {}
for path in bases:
    if os.path.exists(path):
        base = merged(base, json.load(open(path)))
mine = without(json.load(open(live)), base)
# Art from the old config folder: the package and your layers provide it now
for section, key in (("general", "logo"), ("paths", "face"), ("paths", "mediaGif"), ("paths", "sessionGif")):
    if str(mine.get(section, {}).get(key, "")).startswith("~/.config/caelestia/assets/"):
        del mine[section][key]
        if not mine[section]:
            del mine[section]
json.dump(mine, open(out, "w"), indent=4, ensure_ascii=False)
open(out, "a").write("\n")
print(f"  shell.json: {len(json.dumps(mine))} bytes of your own settings (was {os.path.getsize(live)})")
EOF
    else
        echo "would: write $config/caelestia/shell.json (your settings minus the layers')"
    fi
fi

echo "== fish: a real config dir, keeping your variables and snippets"
unlink_dir "$config/fish" fish_variables conf.d completions

echo "== The other links"
for path in "$config/hypr" "$config/kitty" "$config/foot" "$config/ghostty" "$config/btop" \
    "$config/fastfetch" "$config/uwsm" "$config/starship.toml" "$data/bin" "$data/fonts/InstrumentSerif"; do
    [ -L "$path" ] || continue
    if [ "$path" = "$config/hypr" ]; then
        # Keep the colour scheme the shell wrote
        scheme=$(readlink -f "$path")/scheme/current.conf
        run rm "$path"
        run mkdir -p "$path/scheme"
        [ -f "$scheme" ] && run cp "$scheme" "$path/scheme/current.conf"
    else
        run rm "$path"
    fi
done

echo "== Services: the packaged units"
for unit in "${services[@]}"; do
    run systemctl --user disable --now "$unit" 2>/dev/null || true
done
run systemctl --user daemon-reload

echo "== caelestia-plus-setup"
if [ $dry = 1 ]; then
    caelestia-plus-setup --dry-run --host "$host" || true
else
    caelestia-plus-setup --host "$host"
    fc-cache -f >/dev/null 2>&1 || true
    hyprctl reload >/dev/null
    echo "Hyprland reloaded. Restart the shell to pick up the new config (check it isn't locked)."
fi
echo "Undo everything with: $0 --rollback"
