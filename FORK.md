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

## Pulling upstream changes

```sh
git fetch upstream --tags
git merge v2.5.0          # or any upstream tag
cd pkg && makepkg -si
```

`upstream` is fetch-only; pushes go to `origin` (moimart/caelestia-shell).
