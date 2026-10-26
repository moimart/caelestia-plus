#!/bin/sh
# Swap the running shell between the installed package and this checkout.
# In caelestia-plus, prefer tools/dev.sh shell on|off: it keeps your
# shortcuts working (see docs/DEVELOPMENT.md).
#   scripts/dev-shell.sh dev    # run this checkout with plugins from ./build
#   scripts/dev-shell.sh system # back to the installed shell
# Build first with: cmake -B build -G Ninja && cmake --build build
# Launched through Hyprland so the shell lives in the desktop session.
set -eu

repo="$(cd "$(dirname "$0")/.." && pwd)"
case "${1:-}" in
    dev) cmd="QML_IMPORT_PATH=$repo/build/qml qs -p $repo -d" ;;
    system) cmd="qs -c caelestia -n -d" ;;
    *) echo "usage: $0 dev|system" >&2; exit 2 ;;
esac

# The new shell is launched through hyprctl; without Hyprland's environment
# that fails after the old shell is gone, leaving no shell at all.
if ! hyprctl version > /dev/null 2>&1; then
    echo "Can't reach Hyprland (is HYPRLAND_INSTANCE_SIGNATURE set?); not swapping shells." >&2
    exit 1
fi

# Swapping shells kills the lock screen; with the session locked, Hyprland
# would show its "lockscreen crashed" screen. Refuse instead.
for target in "qs -c caelestia" "qs -p $repo"; do
    if [ "$($target ipc call lock isLocked 2>/dev/null)" = "true" ]; then
        echo "The session is locked; not swapping shells. Unlock first." >&2
        exit 1
    fi
done

for pid in $(pgrep -x qs); do
    case "$(tr '\0' ' ' < /proc/"$pid"/cmdline)" in
        "qs -c caelestia"* | "qs -p $repo"*) kill "$pid" ;;
    esac
done
sleep 1
hyprctl dispatch "hl.dsp.exec_cmd(\"sh -c '$cmd'\")" > /dev/null
