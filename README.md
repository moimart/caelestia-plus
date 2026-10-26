<h1 align=center>caelestia-plus</h1>

<p align=center>
A complete Hyprland desktop for Arch, built on <a href="https://github.com/caelestia-dots">Caelestia</a>:
the shell, the Hyprland config and the app configs, installed as packages.
</p>

![A fresh Arch install with caelestia-plus, seconds after setup (in a VM)](docs/fresh-install.png)

![A browser and Steam paired into a window card, flipping over in 3D](shell/docs/screenshots/cards.webp)

The shell is [moimart's fork of Caelestia's](shell/README.md), with video
wallpapers, desktop widgets, window cards, an emoji picker, a camera that
knows when you're there and more. Around it: a Hyprland config in Lua, and
configs for fish, kitty, foot, ghostty, btop and friends.

Everything installs as pacman packages, and nothing in your home folder is
overwritten: the packages ship defaults, and your own files only hold your
changes.

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

Log out, choose Hyprland (uwsm), and you're in. The repo also carries the
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
