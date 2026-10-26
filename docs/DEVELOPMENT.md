# Developing caelestia-plus

How to work on a new feature on your own machine, fast: try it live, check
it, install it, then publish it. You never wait for CI, which only builds
for everyone else.

Everything goes through one script, [`tools/dev.sh`](../tools/dev.sh):

```sh
tools/dev.sh status            # what's running: the checkout or the package
```

## The loop

```
 edit ──▶ see it live ──▶ check ──▶ commit ──▶ build + install ──▶ push
          (seconds)       (secs)              (a few minutes)     (CI publishes)
```

### 1. See it live

**The shell (QML)**: run the checkout as your shell.

```sh
tools/dev.sh shell on
```

`~/.config/quickshell/caelestia` becomes a link to `shell/` in the checkout,
which Quickshell prefers over the installed config, and the shell restarts on
it. From then on:

- **Every save reloads the shell**, in about a second. A broken edit doesn't
  take the shell down: Quickshell keeps the last version that loaded and logs
  the error. Watch the log with `tools/dev.sh shell log`.
  Tools that replace a file instead of writing into it (`sed -i`, some
  editors' safe-save) can lose the watch: if a change doesn't show, run
  `tools/dev.sh shell restart`. Open settings windows keep the old page
  until you close them.
- **Your shortcuts keep working**: it's still the `caelestia` config, so
  `qs -c caelestia ipc ...`, `caelestia shell ...` and the MCP server all
  reach it.
- If the checkout doesn't load at all, `shell on` puts the installed shell
  back by itself.

**The C++ plugin** (`shell/plugin/`): Quickshell can't reload a plugin, so
build it and the shell restarts on it:

```sh
tools/dev.sh plugin            # first build ~1 min, then seconds
```

Until you've run this once, the live checkout uses the installed plugin. That's
fine for QML-only work, and wrong if your QML needs plugin changes.

**The Hyprland config** (`hypr/`): point your `~/.config/hypr/hyprland.lua` at
the checkout.

```sh
tools/dev.sh hypr on           # then save and run `hyprctl reload`
```

If the checkout's config has errors, it switches back to the installed one
and shows them.

**When you're done**, go back to the package:

```sh
tools/dev.sh shell off
tools/dev.sh hypr off
```

Leaving them on is safe, but it means your desktop runs whatever the checkout
has, even after a reboot (without the dev plugin: login starts the plain
`caelestia` config).

**What isn't live**: the camera daemon, the scripts on `PATH`
(`/usr/lib/caelestia-plus/bin`), the default `shell.json` in
`/etc/xdg/caelestia` and the app configs come from the installed packages.
For those, build and install.

### 2. Check

```sh
tools/dev.sh check             # what you changed since origin/main
tools/dev.sh check --all       # everything (~20 s)
```

Runs what CI's linters would complain about: Qt 6 `qmlformat` and the QML
conventions, the translation checks, `clang-format`, `cargo fmt`, and a syntax
check of Lua, Python, shell and JSON files. Logic with tests in `tools/tests/` (the display
arrangement so far, `node tools/tests/arrange.test.js`) gets them run when it
changes. Fix QML formatting with
`/usr/lib/qt6/bin/qmlformat -i <file>` (not plain `qmlformat`: that's Qt 5's).

### 3. Build and install

The packages build from **HEAD**, so commit first. A local commit is enough;
amend it as often as you like before pushing.

```sh
git commit -am "..."
tools/dev.sh build             # first build ~5 min, then incremental
tools/dev.sh install           # sudo pacman -U, then restarts the shell
```

The build keeps its work in `~/.cache/caelestia-plus/dev`, so only what
changed recompiles. The log is in `~/.cache/caelestia-plus/dev/makepkg.log`.

The version comes from `git describe` (like `2.5.0.r352.gabc1234`), the same
one CI will give the same commit, so when CI publishes it `pacman -Syu` has
nothing to do.

### 4. Push

```sh
git push
```

CI builds, signs and publishes the packages to the pacman repo for your other
machines and anyone else, in about 15 minutes. Nothing on this machine waits
for it.

## Safety rails

The script won't touch the shell while the session is **locked**: killing the
shell under the lock screen crashes it, and presence detection can lock the
screen on its own while you're away. Unlock and run it again.

It also finds Hyprland's socket by itself, so it works from tmux, SSH or an
agent's session.

## Working with an agent

Claude Code (or any agent) can run the whole loop except `install`, which
needs your password: the agent runs `tools/dev.sh build`, and you run
`tools/dev.sh install`. With the [MCP server](mcp) it can also take
screenshots of the live checkout to see its own changes.

Things that have gone wrong before, worth telling an agent:

- Run changed QML live (`shell on`) before building packages: one bad import
  stops the whole shell from loading, and the package has no fallback.
- Never restart the shell while locked (the script refuses; don't work
  around it).
- Check every frame of a screenshot or recording before publishing it: lock
  screens, notifications and camera feeds slip in.

## Testing a fresh install

For changes to setup, packaging or defaults, try them on a clean Arch in a VM:
[`tools/vm`](../tools/vm) (`run.sh ~/.cache/caelestia-plus/dev/out` installs
your local build, `run.sh --published` the public repo). To compare Hyprland configs before and after a
refactor: [`hypr/tools/record.lua`](../hypr/tools/record.lua).
