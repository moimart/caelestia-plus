<h1 align=center>caelestia-plus</h1>

<p align=center>
A complete Hyprland desktop for Arch, built on <a href="https://github.com/caelestia-dots">Caelestia</a>:
the shell, the Hyprland config and the app configs, installed as packages.
</p>

> **A personal fork.** This is moimart's own desktop: Caelestia reshaped to one
> person's taste, with the features, defaults and look they wanted. It isn't
> a replacement for Caelestia or an attempt to compete with it, and it
> follows upstream rather than leading it. If you want Caelestia as its
> authors intend it, use [caelestia-dots](https://github.com/caelestia-dots).
> If this particular taste suits you, you're welcome to it.

![moimart's desktop: a video wallpaper, the eyes and daruma widgets, and the clock](shell/docs/screenshots/desktop.jpg)

The shell is [moimart's fork of Caelestia's](shell/README.md). Around it: a
Hyprland config in Lua, and configs for fish, kitty, foot, ghostty, btop and
friends. Everything installs as pacman packages, and nothing in your home
folder is overwritten: the packages ship defaults, and your own files only
hold your changes.

## What's in it

### Window cards

![A browser and Steam paired into a window card, flipping over in 3D](shell/docs/screenshots/cards.webp)

Pair two windows into one card and flip it over in 3D to show the other:
**Super+Alt+Tab** pairs (the focused window is the front; pick the back),
**Super+Tab** flips, **Super+Shift+Tab** splits them again. No Hyprland plugin:
a card is a locked window group, and the shell draws the turn with real
perspective, then hands back to the live window.

### Plugins: desktop widgets

Upstream's empty plugin page made real, starting with widgets that live on the
desktop, above the wallpaper:

- **Eyes**, like xeyes but quiet: three abstract styles (orbit, almond, dots)
  that follow your pointer, blink, and half-close when it rests.
- **Daruma**: the winking daruma, its painted eye following the pointer. It
  winks now and then, and shuts both eyes when the pointer is still.
- **The editor** (**Super+Ctrl+W**): drag widgets to move them, drag a corner
  to resize, add more from the palette. Each widget's settings are in
  Settings → Plugins.
- **Your own**: a widget is a folder with a small manifest and a QML file, in
  `~/.config/caelestia/plugins/widgets/`. [PLUGINS.md](shell/PLUGINS.md)
  explains how, and [`examples/widgets/clock`](shell/examples/widgets/clock) is
  a working template.

<img src="shell/docs/screenshots/widgets-editor.jpg" alt="The widget editor with the eyes and daruma widgets" width="70%">

### Camera

<img src="shell/docs/screenshots/tutorial.jpg" alt="The hand gesture tutorial" width="70%">

One small Rust daemon, `caelestia-camerad`, is the only thing that touches the
webcam. It reads frames through PipeWire, and only while a feature needs one,
so the camera and its light are off the rest of the time.

- **Presence**: while you're idle, it checks whether you're still at the desk.
  Reading or watching without touching anything? The screen stays on. Gone?
  It locks. Back? The screen wakes and face unlock starts.
- **Face unlock**, with [howdy](https://github.com/boltgolt/howdy), through the
  lock screen. Tries count in a row, so failed ones overnight don't lock you
  out in the morning.
- **Hand gestures** (**Super+Alt+G**): an open palm plays or pauses, swipes
  skip tracks, thumbs up and down run whatever you assign. A guided tutorial,
  with a live view of your hand, teaches them the first time.
- **The camera panel** (**Super+Alt+C**): a mirror to check yourself before a
  call; zoom, pan, tilt, focus, white balance and image controls; saved
  presets; and **video recording** to `~/Videos/Camera`, with sound from the
  camera's microphone.
- **Who's using it**: a camera icon in the bar turns red while any app has the
  camera, and its popout says which.
- **Unlock-attempt photos**: after three wrong passwords, a photo of whoever is
  at the keyboard, shown to you once you unlock.
- **Light sensor**: the room's light can set your monitor's brightness and
  switch between light and dark.
- **It gives way**: apps sharing the camera through PipeWire (Chrome with its
  PipeWire camera flag, Firefox, OBS) run alongside it at full speed; apps
  that open the camera directly make the daemon let go at once.

Faces come from YuNet and gestures from MediaPipe's palm and hand models, on
ONNX Runtime.

### Emoji picker

![The emoji picker: frequently used and categories, a search for "heart", and the skin tones of the waving hand](shell/docs/screenshots/emoji.png)

**Ctrl+Super+Space**, like Ctrl+Cmd+Space on a Mac, opens it next to your
pointer:

- **Search as you type**, by name or keyword: "lol" finds 😂, "heart" finds every heart.
- **Frequently used** first, and the categories along the bottom.
- **Skin tones**: right-click, or press Tab, on an emoji with a dot under it;
  it remembers your choice for that emoji.
- **Into any app**: pick one and it lands in what you were typing in. Apps get
  it pasted (Chrome and other Chromium apps garble emoji typed through a
  virtual keyboard), terminals get it typed, and your clipboard is put back.

### Launchpad

![Launchpad: every app in a grid over the blurred desktop](shell/docs/screenshots/launchpad.jpg)

**Shift+Super+Space**, like Launchpad on a Mac: every app in a grid of pages in
the middle of the screen, over the desktop dimmed and blurred. Start typing
and it narrows to what you write; Enter or a click launches. The wheel, a drag
or the dots turn the pages.

<table>
<tr>
<td width="50%" valign="top">

### Video wallpapers

The desktop at the top is one. Any video in your wallpapers folder, picked
like an image and played through mpvpaper with hardware decoding, behind the
desktop clock and widgets. It pauses when it can't be seen, each monitor can
have its own, and the colour scheme follows it.

</td>
<td width="50%" valign="top">

### Keyboard shortcuts panel

<img src="shell/docs/screenshots/keybinds.jpg" alt="The keyboard shortcuts panel">

**Super+/** lists every shortcut you have, read from your own Hyprland config:
nothing is hardcoded. Searchable, grouped by your config's sections.

</td>
</tr>
<tr>
<td valign="top">

### Lock screen

<img src="shell/docs/screenshots/lock.jpg" alt="The lock screen with an animated profile picture and Home Assistant cards (blurred here)">

An animated profile picture, read-only Home Assistant cards (a camera, energy,
your devices), and face unlock.

</td>
<td valign="top">

### The daruma

<img src="shell/docs/screenshots/session.jpg" alt="The session menu with the winking daruma">

A winking daruma replaces Caelestia's mascots: the bar logo, the session
menu, and the media card while music plays.

</td>
</tr>
<tr>
<td colspan="2" valign="top">

### Settings for all of it

<img src="shell/docs/screenshots/settings.jpg" alt="Settings pages for plugins, the camera, shortcuts and window cards">

Each feature has its page in Settings, next to upstream's, and everything is
reachable from scripts (`caelestia shell <target> <function>`) and from AI
agents through an MCP server.

</td>
</tr>
</table>

### Talk to your desktop: the MCP server

An MCP server lets AI agents like Claude Code see and drive the desktop:
screenshots, wallpapers and colours, any setting, media, the shortcuts, window
cards, widgets, emoji and the camera (deliberately without a way to take
photos). 29 tools, set up with one line:

```sh
claude mcp add --scope user caelestia -- caelestia-mcp
```

Then ask things like "put a video wallpaper on my left monitor", "pair Chrome
and Steam into a card" or "is anything using my camera?". Every tool, with
examples: [docs/mcp](docs/mcp).

Around the shell, from the Hyprland config and app configs:

- **Super+Shift+Enter**: a floating terminal right at your pointer, kept on screen.
- **kitty with a CRT shader**, phase-locked to the wall clock so every window
  flickers in sync (`kitty-crt`).
- fish with starship, eza and handy git abbreviations; foot and ghostty
  (with an amber CRT shader) as alternatives.
- A download sorter and AppImage launcher entries, as user services.

The full tour, with every shortcut: [the shell's README](shell/README.md).

## Install

On Arch (or CachyOS, EndeavourOS...) with a user account:

```sh
# Trust the signing key and add the repo
curl -sL https://moimart.github.io/caelestia-plus-packages/caelestia-plus.asc | sudo pacman-key --add -
sudo pacman-key --lsign-key BC40964C5AA4206E09F6148BD849D193EECADBBB
printf '\n[caelestia-plus]\nSigLevel = Required\nServer = https://moimart.github.io/caelestia-plus-packages/$arch\n' \
    | sudo tee -a /etc/pacman.conf

# Install, then set up your user
sudo pacman -Syu caelestia-plus
caelestia-plus-setup
```

Log out, choose Hyprland (uwsm), and you're in. This is a fresh install,
seconds after setup (in a VM, so no video wallpaper):

![A fresh Arch install with caelestia-plus, seconds after setup (in a VM)](docs/fresh-install.png)

 The repo also carries the
AUR packages the shell needs (Quickshell, the Caelestia CLI, ...), built
together so they always match.

### Or build it yourself

The same packages, from source, without trusting the binary repo:

```sh
git clone https://github.com/moimart/caelestia-plus.git
cd caelestia-plus/pkg
makepkg -si          # builds the commit you have checked out
caelestia-plus-setup
```

This needs the AUR packages the shell depends on (`quickshell-git`,
`caelestia-cli`, `libcava`, `app2unit`, `ttf-rubik-vf`) from your AUR helper
first. An AUR recipe, [`caelestia-plus-git`](aur/caelestia-plus-git), is
ready for when AUR registration reopens.

## Make it yours

Settings stack in layers, each overriding the one before:

1. **The defaults**, from the packages (`/usr/share/caelestia-plus`,
   `/etc/xdg/caelestia`).
2. **Your personal layer**: what's yours on every machine (your face, your
   Home Assistant cards, your own binds).
3. **A host profile**: what belongs to one machine (monitors, scaling).
4. **Your files in `~/.config`**: `~/.config/hypr/hyprland.lua` loads the
   defaults and then your changes; `~/.config/caelestia/shell.json` holds
   only the settings you changed in the shell.

Layers 2 and 3 live in `~/.config/caelestia-plus/`, ideally your own private
git repo: `caelestia-plus-setup --overlay <git URL>` clones it.
[`hosts/README.md`](hosts/README.md) shows how they look, and
[`hosts/example`](hosts/example) is a starting point.

## What's here

| Folder | What |
| --- | --- |
| [`shell/`](shell) | The Quickshell shell, its C++ plugin and the camera daemon (fork of [caelestia-dots/shell](https://github.com/caelestia-dots/shell)) |
| [`hypr/`](hypr) | The Hyprland config, in Lua |
| [`dots/`](dots) | App configs and scripts (fork of [caelestia-dots/caelestia](https://github.com/caelestia-dots/caelestia)) |
| [`config/`](config) | The shell's default settings and art, fonts, the download sorter |
| [`hosts/`](hosts) | How host profiles and the personal layer work |
| [`setup/`](setup) | `caelestia-plus-setup` and the files it creates |
| [`pkg/`](pkg) | The PKGBUILD for all the packages |
| [`tools/`](tools) | Development ([`dev.sh`](tools/dev.sh), see [DEVELOPMENT.md](docs/DEVELOPMENT.md)), a fresh install in a VM, comparing Hyprland configs |

CI builds, signs and publishes the packages to
[caelestia-plus-packages](https://github.com/moimart/caelestia-plus-packages)
on every push. To work on it: [DEVELOPMENT.md](docs/DEVELOPMENT.md).
[PLAN.md](PLAN.md) has the design and how it came together.

## Credits

[Caelestia](https://github.com/caelestia-dots) by soramane and its
contributors, on [Quickshell](https://quickshell.outfoxxed.me) and
[Hyprland](https://hypr.land).
