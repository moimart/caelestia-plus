# moimart's Caelestia

A long-lived fork of [caelestia-dots/shell](https://github.com/caelestia-dots/shell),
based on upstream `v2.3.0`. It is installed as the `caelestia-shell-moimart`
package, which replaces the AUR `caelestia-shell`.

## Changes from upstream

- **Lock screen Home Assistant cards** (`modules/lock/ha/`): read-only camera,
  energy and entities cards, configured in `~/.config/caelestia/lock-ha.json`.
- **Lock clock** uses the configured clock font (`appearance.font.clock`).
- **Lock profile picture** is a rounded square instead of the clamshell.
- **Video wallpapers** (`modules/background/VideoPlayer.qml`, `services/Posters.qml`):
  videos in `paths.videoWallpaperDir` (default `~/VideoWallpapers`) appear in the
  wallpaper pickers next to images and play through mpvpaper under the shell's
  background, so the desktop clock and visualiser still draw on top. A cached
  poster frame crossfades in first and the colour scheme comes from it.
  Settings in `shell.json`:

  ```json
  "background": { "video": { "hwdec": "auto-safe", "pauseWhenHidden": true, "mpvOptions": "" } }
  ```

  `pauseWhenHidden` pauses while the monitor has a fullscreen window, in game
  mode and while locked. Needs `mpvpaper` and `ffmpeg`.
- **Per-monitor wallpapers** (images or videos): Shift+Enter in the launcher's
  wallpaper list sets it for that monitor only; Enter sets it everywhere and
  clears per-monitor choices. Over IPC:
  `qs -c caelestia ipc call wallpaper setFor DP-1 <path>` / `clearFor DP-1` / `getFor DP-1`.
  The colour scheme follows the global wallpaper.

- **Keyboard shortcuts panel** (`modules/keybinds/`, `services/Keybinds.qml`,
  `assets/hyprbinds.py`): a searchable cheatsheet of every active bind. Nothing
  is hardcoded. `hyprbinds.py` reads `hyprland.lua` and the modules it
  `require()`s (or `hyprland.conf` and its `source`s), evaluates each
  `hl.bind()`, binds made in loops included, and pairs it with `hyprctl binds`.
  Titles come, in order of preference, from:
  - the bind's `description`;
  - a `-- SUPER + X → …` comment;
  - the dispatcher, command, desktop entry or global shortcut description;
  - the config's comments.

  Categories come from the config's `-- ====` section banners. The list
  refreshes when Hyprland reloads. To open it:
  - press `hl.dsp.global("caelestia:keybinds")` (bound to Super+/);
  - choose `>Shortcuts` in the launcher;
  - run `qs -c caelestia ipc call keybinds toggle|open|close|list|settings`;
  - use the `keybinds` MCP tool.

  Settings are in Nexus → Keyboard shortcuts (`keybinds.*` in shell.json).
  Sizes are under `sizes.keybinds` in the tokens.

- **MCP server** (`mcp/`): lets Claude Code agents control the shell (screenshots,
  wallpapers, scheme, settings, lock, media, panels, raw IPC, keybinds). See `mcp/README.md`.

## Build and install

```sh
cd pkg && makepkg -si
```

This builds the commit checked out on this machine (commit first), QML and plugin
together, so they always match.

## Developing

```sh
cmake -B build -G Ninja && cmake --build build   # plugins, after C++ changes
scripts/dev-shell.sh dev      # run this checkout (hot-reloads on save)
scripts/dev-shell.sh system   # back to the installed shell
```

The dev shell watches this whole checkout, and `makepkg` normally unpacks
copies of the shell into `pkg/`, which breaks its hot reload. While it runs,
build the package outside the repo:

```sh
cd pkg && BUILDDIR=/tmp/caelestia-pkg/build SRCDEST=/tmp/caelestia-pkg/src PKGDEST=$PWD makepkg -si
```

## Pulling upstream changes

```sh
git fetch upstream --tags
git merge v2.5.0          # or any upstream tag
cd pkg && makepkg -si
```

`upstream` is fetch-only; pushes go to `origin` (moimart/caelestia-shell).
