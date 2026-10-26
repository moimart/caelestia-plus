#!/usr/bin/env bash
# The fast loop for working on caelestia-plus on your own machine: run the
# checkout live, check it, then build and install the packages locally.
# docs/DEVELOPMENT.md explains the workflow.
#
#   tools/dev.sh shell on|off|restart|log|status
#   tools/dev.sh plugin            # build the shell's C++ plugin for the live checkout
#   tools/dev.sh hypr on|off|status
#   tools/dev.sh check [--all]     # format and lint what you changed
#   tools/dev.sh build             # the packages, from HEAD, incrementally
#   tools/dev.sh install           # sudo pacman -U the last build, restart the shell
#   tools/dev.sh status
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
config=${XDG_CONFIG_HOME:-$HOME/.config}
link=$config/quickshell/caelestia
hypr_stub=$config/hypr/hyprland.lua
system_hypr=/usr/share/caelestia-plus/hypr/hyprland.lua
cache=${XDG_CACHE_HOME:-$HOME/.cache}/caelestia-plus/dev
plugin_dir=$repo/shell/build/qml

# Runs a command, showing its output only if it fails
quiet() {
    local out
    out=$("$@" 2>&1) && return
    echo "$out" >&2
    return 1
}

die() { echo "dev: $*" >&2; exit 1; }
note() { echo "dev: $*"; }

# Sessions started outside Hyprland (tmux, ssh, services) lack its socket
hypr_env() {
    hyprctl version > /dev/null 2>&1 && return
    local runtime=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
    HYPRLAND_INSTANCE_SIGNATURE=$(ls -t "$runtime/hypr" 2> /dev/null | head -1)
    export HYPRLAND_INSTANCE_SIGNATURE
    hyprctl version > /dev/null 2>&1 || die "can't reach Hyprland"
}

# Killing the shell while locked crashes the lock screen: never do it
ensure_unlocked() {
    if [ "$(qs -c caelestia ipc call lock isLocked 2> /dev/null)" = true ]; then
        die "the session is locked; not touching the shell. Unlock first."
    fi
}

shell_pids() {
    local pid
    for pid in $(pgrep -x qs); do
        case "$(tr '\0' ' ' < /proc/"$pid"/cmdline 2> /dev/null)" in
            "qs -c caelestia"* | "qs -p $repo/shell"*) echo "$pid" ;;
        esac
    done
}

# Restarts the shell and waits for it to load. Returns 1 if it doesn't.
shell_restart() {
    hypr_env
    ensure_unlocked

    local cmd="qs -c caelestia -n -d"
    if [ -L "$link" ] && [ -d "$plugin_dir/Caelestia" ]; then
        cmd="QML_IMPORT_PATH=$plugin_dir $cmd"
    fi

    local pids
    pids=$(shell_pids)
    if [ -n "$pids" ]; then
        # shellcheck disable=SC2086
        kill $pids
        for _ in $(seq 40); do
            [ -z "$(shell_pids)" ] && break
            sleep 0.25
        done
    fi
    hyprctl dispatch "hl.dsp.exec_cmd(\"sh -c '$cmd'\")" > /dev/null

    local log
    for _ in $(seq 60); do
        sleep 0.5
        log=$(timeout 2 qs -c caelestia log 2> /dev/null || true)
        if grep -q 'Configuration Loaded' <<< "$log"; then
            note "shell running: $(shell_source)"
            return 0
        fi
        if grep -qi 'failed to load configuration' <<< "$log"; then
            break
        fi
    done
    grep -E 'ERROR|unavailable|is not a type' <<< "$log" | head -20 >&2 || true
    return 1
}

shell_source() {
    if [ -L "$link" ]; then
        local src="the checkout ($(readlink "$link"))"
        [ -d "$plugin_dir/Caelestia" ] && src="$src, plugin from shell/build"
        echo "$src"
    else
        echo "the installed package"
    fi
}

shell_on() {
    hypr_env
    ensure_unlocked
    if [ -e "$link" ] && [ ! -L "$link" ]; then
        die "$link is a real folder, not ours; move it away first"
    fi
    # An old symlinked build/ would load some other checkout's plugin
    [ -L "$repo/shell/build" ] && rm "$repo/shell/build"
    mkdir -p "$(dirname "$link")"
    ln -sfn "$repo/shell" "$link"
    if shell_restart; then
        note "QML changes now reload as you save. Shortcuts keep working."
        note "C++ plugin changes: tools/dev.sh plugin. Done: tools/dev.sh shell off"
    else
        note "the checkout doesn't load (errors above); back to the installed shell"
        rm -f "$link"
        shell_restart || die "the installed shell didn't load either: run 'caelestia shell -d'"
        exit 1
    fi
}

shell_off() {
    if [ ! -L "$link" ]; then
        note "already running the installed shell"
        return
    fi
    hypr_env
    ensure_unlocked
    rm "$link"
    rmdir "$(dirname "$link")" 2> /dev/null || true
    shell_restart || die "the installed shell didn't load: check 'qs -c caelestia log'"
}

plugin() {
    cd "$repo/shell"
    [ -L build ] && rm build
    cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_INSTALL_PREFIX=/ \
        -DVERSION="$(git describe --tags --abbrev=0 | sed 's/^v//')" \
        -DGIT_REVISION="$(git rev-parse HEAD)" -DDISTRIBUTOR="caelestia-plus (dev)" > /dev/null
    cmake --build build
    if [ -L "$link" ]; then
        shell_restart || die "the shell didn't load with the new plugin: tools/dev.sh shell off"
    else
        note "built; tools/dev.sh shell on runs the checkout with it"
    fi
}

hypr_set() {
    grep -q '^dofile(".*/hypr/hyprland.lua")' "$hypr_stub" \
        || die "$hypr_stub doesn't load caelestia-plus with dofile(); edit it by hand"
    sed -i "s|^dofile(\".*/hypr/hyprland.lua\")|dofile(\"$1\")|" "$hypr_stub"
    hypr_env
    hyprctl reload > /dev/null
    sleep 1
}

hypr_errors() {
    hyprctl configerrors | grep -v '^\s*$' || true
}

hypr_on() {
    hypr_set "$repo/hypr/hyprland.lua"
    local errors
    errors=$(hypr_errors)
    if [ -n "$errors" ]; then
        echo "$errors" >&2
        hypr_set "$system_hypr"
        die "the checkout's config has errors (above); back to the installed one"
    fi
    note "Hyprland runs the checkout's config: save, then 'hyprctl reload'. Done: tools/dev.sh hypr off"
}

hypr_source() {
    if grep -q "^dofile(\"$repo/hypr/hyprland.lua\")" "$hypr_stub" 2> /dev/null; then
        echo "the checkout"
    else
        echo "the installed package"
    fi
}

# Files changed from origin/main: committed, staged, unstaged and new
changed_files() {
    cd "$repo"
    if [ "${1:-}" = --all ]; then
        git ls-files
    else
        {
            git diff --name-only --diff-filter=d origin/main 2> /dev/null || git diff --name-only --diff-filter=d HEAD
            git ls-files --others --exclude-standard
        } | sort -u
    fi
}

check() {
    cd "$repo"
    local files fail=0 f
    mapfile -t files < <(changed_files "${1:-}")
    [ ${#files[@]} -eq 0 ] && { note "nothing changed from origin/main"; return; }

    for f in "${files[@]}"; do
        [ -f "$f" ] || continue
        case "$f" in
            shell/build/* | */target/*) ;;
            *.qml)
                /usr/lib/qt6/bin/qmlformat "$f" | diff -u "$f" - || { note "format: /usr/lib/qt6/bin/qmlformat -i $f"; fail=1; }
                quiet python3 shell/scripts/qml-lint-conventions.py --file "$f" || fail=1
                ;;
            shell/*.cpp | shell/*.hpp)
                (cd shell && clang-format --dry-run --Werror "${f#shell/}") || fail=1
                ;;
            *.lua) luac5.5 -p "$f" || fail=1 ;;
            *.py) python3 -c "import ast, sys; ast.parse(open(sys.argv[1]).read(), sys.argv[1])" "$f" || fail=1 ;;
            *.sh) bash -n "$f" || fail=1 ;;
            # dots/ has editor configs with comments, which aren't JSON
            config/*.json | hosts/*.json | shell/*.json)
                python3 -m json.tool "$f" > /dev/null || { note "bad JSON: $f"; fail=1; }
                ;;
        esac
    done
    if printf '%s\n' "${files[@]}" | grep -q '^shell/.*\.qml$'; then
        (cd shell && quiet python3 scripts/trs-check.py) || fail=1
    fi
    if printf '%s\n' "${files[@]}" | grep -q '^shell/extras/camerad/.*\.rs$'; then
        (cd shell/extras/camerad && cargo fmt --check) || fail=1
    fi

    if [ "$fail" = 0 ]; then
        note "checked ${#files[@]} files: all good"
    else
        die "some checks failed (above)"
    fi
}

build() {
    cd "$repo"
    if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
        die "uncommitted changes: the packages build HEAD, so commit first (you can amend later)"
    fi
    mkdir -p "$cache"/{build,out,sources}
    # makepkg writes the version into the PKGBUILD; put yours back after
    cp pkg/PKGBUILD "$cache/PKGBUILD.orig"
    local status=0
    (cd pkg && BUILDDIR="$cache/build" PKGDEST="$cache/out" SRCDEST="$cache/sources" \
        makepkg -f --noconfirm) > "$cache/makepkg.log" 2>&1 || status=$?
    cp "$cache/PKGBUILD.orig" pkg/PKGBUILD
    if [ "$status" != 0 ]; then
        tail -30 "$cache/makepkg.log" >&2
        die "makepkg failed (full log: $cache/makepkg.log)"
    fi
    local ver
    ver=$(sed -n 's/^\s*pkgver = //p' "$cache/build/caelestia-plus/pkg/caelestia-plus/.PKGINFO")
    echo "$ver" > "$cache/last"
    find "$cache/out" -name '*.pkg.tar.zst' ! -name "*-$ver-*" -delete
    note "built $ver: tools/dev.sh install"
}

install_pkgs() {
    [ -f "$cache/last" ] || die "nothing built yet: tools/dev.sh build"
    local ver
    ver=$(cat "$cache/last")
    [ "$ver" = "$(pacman -Q caelestia-plus 2> /dev/null | cut -d' ' -f2 | sed 's/-[0-9]*$//')" ] \
        && note "$ver is already installed; reinstalling"
    sudo pacman -U --noconfirm "$cache"/out/*-"$ver"-*.pkg.tar.zst
    if [ -L "$link" ]; then
        note "installed; the shell still runs the checkout (tools/dev.sh shell off to use the package)"
    else
        shell_restart || die "the new shell didn't load: check 'qs -c caelestia log'"
    fi
}

status() {
    cd "$repo"
    echo "shell:     $(shell_source)"
    echo "hyprland:  $(hypr_source)"
    echo "installed: $(pacman -Q caelestia-plus 2> /dev/null | cut -d' ' -f2)"
    echo "built:     $(cat "$cache/last" 2> /dev/null || echo nothing)"
    echo "checkout:  $(git describe --long --tags --match 'v*' | sed 's/^v//; s/\([^-]*-g\)/r\1/; s/-/./g')$([ -n "$(git status --porcelain)" ] && echo ', with uncommitted changes')"
    if [ -L "$link" ] && [ -d "$plugin_dir/Caelestia" ] \
        && [ -n "$(find shell/plugin -newer "$plugin_dir/Caelestia" -type f | head -1)" ]; then
        echo "note:      plugin sources changed since the last 'tools/dev.sh plugin'"
    fi
}

case "${1:-} ${2:-}" in
    "shell on") shell_on ;;
    "shell off") shell_off ;;
    "shell restart") shell_restart || die "the shell didn't load (errors above)" ;;
    "shell log") exec qs -c caelestia log -f ;;
    "shell status" | "shell ") shell_source ;;
    "plugin "*) plugin ;;
    "hypr on") hypr_on ;;
    "hypr off") hypr_set "$system_hypr" && note "Hyprland runs the installed config" ;;
    "hypr status" | "hypr ") hypr_source ;;
    "check "*) check "${2:-}" ;;
    "build "*) build ;;
    "install "*) install_pkgs ;;
    "status "* | " ") status ;;
    *) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
esac
