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

- **Window cards** (`modules/cards/`, `services/Cards.qml`): pair two windows
  into one "card" and flip it over in 3D to show the other. No Hyprland plugin
  is needed:
  - **Pairing:** a card is a locked Hyprland group of the two windows, tagged
    `caelestia-card`, with decorations off so no tab bar shows. The shell
    installs small Lua helpers into Hyprland on start and after every reload
    (`hyprctl eval`).
  - **Flipping:** the shell captures both windows, hides the real ones with a
    `caelestia-card-hidden` tag (an opacity-0, no-animation rule), turns a card
    with the captures on its faces in a perspective rotation, then shows the
    other window live.
  - **Shortcuts:** `caelestia:cardPair` (the focused window becomes the front;
    pick the back), `cardFlip` and `cardUnpair`, bound to Super+Alt+Tab,
    Super+Tab and Super+Shift+Tab.
  - **Other access:** IPC target `cards`
    (`pair`/`pairWindows`/`flip`/`unpair`/`cancel`/`list`), the `cards` MCP
    tool, and Nexus → Window cards for settings (`cards.*`).
  - **Needs** the Lua config (Hyprland 0.55+).

- **Plugins: desktop widgets** (`modules/widgets/`, `services/Widgets.qml`): widget
  plugins placed on the desktop, above the wallpaper. Built-in ones are in
  `modules/widgets/builtin/`; yours go in `~/.config/caelestia/plugins/widgets/`.
  - **Editing:** Super+Ctrl+W (`caelestia:widgets`) opens an editor on every
    monitor: drag widgets to move them, drag a corner to resize, and add more
    from a palette.
  - **Eyes:** the first widget, xeyes-like, in three abstract styles
    (orbit by default).
  - **Daruma:** your winking daruma (from `daruma-source.svg`), its painted
    eye following the pointer. It winks that eye now and then and rests with
    both shut when the pointer is still. Rebuild its images with
    `modules/widgets/builtin/daruma/make-art.py`.
  - **Settings:** Nexus → Plugins lists plugins and holds the settings
    (`widgets.*`). About counts the plugins.
  - **Other access:** IPC target `widgets` and the `widgets` MCP tool.
  - **Pointer:** comes from a new poller in `HyprExtras`
    (`cursorPos`/`trackCursor`), active only while a placed widget needs it.

  How to write a plugin: see [PLUGINS.md](PLUGINS.md); there's a working
  example in `examples/widgets/clock/`.

- **Camera** (`extras/camerad/`, `services/Camera.qml`, `daemons/CameraFeatures.qml`,
  `modules/camera/`). One Rust daemon, `caelestia-camerad`, is the only thing
  that touches the webcam. The shell runs it and talks JSON lines over its
  stdin and stdout.
  - **How it uses the camera:** it reads frames through **PipeWire**, and only
    while a feature needs them, so the camera and its light are off the rest
    of the time. Other PipeWire users share the camera with it, at no added
    latency, since the daemon is never in their video path:
    - Chrome, with `chrome://flags/#enable-webrtc-pipewire-camera`;
    - OBS, with its "Video Capture Device (PipeWire)" source.

    If an app opens the device directly, the daemon stops capturing at once
    and stays off until nobody has opened the camera for 30 s. Apps that read
    the camera directly can't share it with a running stream, so with gestures
    on, such an app's very first attempt can still find it busy; its retry
    works. Chrome avoids this entirely with its PipeWire camera flag.

    Some apps open the camera on a fixed beat only to list devices; Discord
    does it every 3 s, for as long as it runs. The daemon learns such a beat
    from opens made while the camera was free and ignores opens that fall on
    it. Gestures then resume about 20 s after starting, instead of staying
    paused.
  - **Who's using it:** an inotify watch on the device plus `/proc` for direct
    users, and the PipeWire graph for apps sharing it. The bar shows a red
    camera icon while another app has the camera; it's a `camera` status icon
    entry, with a popout listing the apps.
  - **Camera panel** (Super+Alt+C, `caelestia:camera`): a mirror, the camera's
    V4L2 controls (zoom, pan, tilt, focus, white balance, image), saved
    presets, and the feature switches.
  - **Utilities quick toggle:** the camera's master switch (`camera.enabled`).
  - **Presence:** after 60 s without input it checks every 20 s.
    - If you're there (reading, watching), it holds off idle actions.
    - After 3 checks without a face, it locks.
    - While locked, it checks every 6 s, and wakes the screen and starts face
      unlock when you sit back down.
  - **Light sensor:** a reading every 5 minutes sets monitor brightness, and can
    switch the light/dark scheme. The camera has no exposure control, so
    readings are relative; calibrate with "Read now" in Nexus → Camera. Off by
    default.
  - **Gestures** (Super+Alt+G, `caelestia:cameraGestures`):
    - an open palm held: play/pause;
    - a swipe left/right: previous/next track;
    - a thumbs up or down held: unassigned by default.

    Each action is configurable: `media.*`, `none`, or any shell command. While
    gestures are on, the camera stays on, except while another app uses it.
  - **Unlock-attempt photos:** after 3 wrong passwords on the lock screen,
    again at 6, saved to `~/Pictures/Unlock attempts` and shown in a
    notification once you unlock.
  - **Face unlock:** with howdy, through the lock screen's existing support.
    This camera has no infrared, so a photo could fool it.
  - **Models:** YuNet (faces) and MediaPipe palm and hand (gestures), from
    opencv_zoo, on ONNX Runtime (`onnxruntime-cpu`, loaded only when a model is
    first needed). The PKGBUILD fetches them, with pinned checksums, into
    `/usr/lib/caelestia/camera-models`.
  - **Testing models:** `caelestia-camerad --test photo.jpg` runs them on a
    picture.
  - **Other access:** settings in Nexus → Camera (`camera.*`), IPC target
    `camera`, and the `camera` MCP tool (deliberately without photos).

  Setup:
  ```sh
  sudo pacman -S onnxruntime-cpu        # presence, gestures, light
  paru -S howdy-git                     # face unlock (optional)
  sudo howdy config                     # set device_path = /dev/video0
  sudo howdy add                        # learn your face
  ```
  Then turn on Chrome's PipeWire camera flag, so Chrome shares the camera.

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
(cd extras/camerad && cargo build --release)      # the camera daemon
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
