#!/bin/sh
# Swap the running shell between the installed package and this checkout.
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

for pid in $(pgrep -x qs); do
    case "$(tr '\0' ' ' < /proc/"$pid"/cmdline)" in
        "qs -c caelestia"* | "qs -p $repo"*) kill "$pid" ;;
    esac
done
sleep 1
hyprctl dispatch "hl.dsp.exec_cmd(\"sh -c '$cmd'\")" > /dev/null
