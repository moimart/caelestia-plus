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
**Super+Alt+Tab** pairs, **Super+Tab** flips, **Super+Shift+Tab** splits them
again. No Hyprland plugin: a card is a locked window group, and the shell
draws the turn with real perspective.

<table>
<tr>
<td width="50%" valign="top">

### Video wallpapers

The desktop at the top is one. Any video in your wallpapers folder, picked
like an image and played through
mpvpaper with hardware decoding, behind the desktop clock and widgets. It
pauses when it can't be seen, each monitor can have its own, and the colour
scheme follows it.

</td>
<td width="50%" valign="top">

### Desktop widgets

<img src="shell/docs/screenshots/widgets-editor.jpg" alt="The widget editor with the eyes and daruma widgets">

Upstream's empty plugin page made real: widgets you place and resize on the
desktop (**Super+Ctrl+W**). Eyes that follow your pointer, a winking daruma,
and your own in `~/.config/caelestia/plugins/widgets`.

</td>
</tr>
<tr>
<td valign="top">

### Keyboard shortcuts panel

<img src="shell/docs/screenshots/keybinds.jpg" alt="The keyboard shortcuts panel">

**Super+/** lists every shortcut you have, read from your own Hyprland config:
nothing is hardcoded. Searchable, grouped by your config's sections.

</td>
<td valign="top">

### Emoji picker

<img src="shell/docs/screenshots/emoji.png" alt="The emoji picker: the grid, a search, and skin tones">

**Ctrl+Super+Space**, like macOS: search by name or keyword, skin tones, your
most used first, and the emoji lands in whatever you were typing in.

</td>
</tr>
<tr>
<td valign="top">

### A camera that knows you're there

<img src="shell/docs/screenshots/tutorial.jpg" alt="The hand gesture tutorial">

One small Rust daemon reads the webcam only when a feature needs it, and steps
aside for any other app. It keeps the screen awake while you read, locks when
you leave, wakes it with face unlock when you're back, and plays or skips
music with hand gestures (taught by a tutorial). The camera panel
(**Super+Alt+C**) has a mirror, the camera's controls, presets and video
recording.

</td>
<td valign="top">

### Lock screen

<img src="shell/docs/screenshots/lock.jpg" alt="The lock screen with an animated profile picture and Home Assistant cards (blurred here)">

An animated profile picture, read-only Home Assistant cards (a camera, energy,
your devices), face unlock, and photos of anyone who gets the password wrong.

</td>
</tr>
<tr>
<td valign="top">

### The daruma

<img src="shell/docs/screenshots/session.jpg" alt="The session menu with the winking daruma">

A winking daruma replaces Caelestia's mascots: the bar logo, the session
menu, and the media card while music plays.

</td>
<td valign="top">

### Settings for all of it

<img src="shell/docs/screenshots/settings.jpg" alt="Settings pages for plugins, the camera, shortcuts and window cards">

Each feature has its page in Settings, next to upstream's, and everything is
reachable from scripts (`caelestia shell <target> <function>`) and from AI
agents through an MCP server.

</td>
</tr>
</table>

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
| [`tools/`](tools) | Testing: a fresh install in a VM, comparing Hyprland configs |

CI builds, signs and publishes the packages to
[caelestia-plus-packages](https://github.com/moimart/caelestia-plus-packages)
on every push. [PLAN.md](PLAN.md) has the design and how it came together.

## Credits

[Caelestia](https://github.com/caelestia-dots) by soramane and its
contributors, on [Quickshell](https://quickshell.outfoxxed.me) and
[Hyprland](https://hypr.land).
