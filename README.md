# caelestia

This is the main repo of the caelestia dots and contains the user configs for
apps. This repo also includes an install script to install the entire dots.

## Installation

Simply clone this repo and run the install script (you need
[`fish`](https://github.com/fish-shell/fish-shell) installed).

> [!WARNING]
> The install script symlinks all configs into place, so you CANNOT
> move/remove the repo folder once you run the install script. If
> you do, most apps will not behave properly and some (e.g. Hyprland)
> will fail to start completely. I recommend cloning the repo to
> `~/.local/share/caelestia`.

The install script has some options for installing configs for some apps.

```
$ ./install.fish -h
usage: ./install.sh [-h] [--noconfirm] [--spotify] [--vscode] [--discord]

options:
  -h, --help                  show this help message and exit
  --noconfirm                 do not confirm package installation
  --spotify                   install Spotify (Spicetify)
  --vscode=[codium|code]      install VSCodium (or VSCode)
  --discord                   install Discord (OpenAsar + Equicord)
  --zen                       install Zen browser
```

For example:

```sh
git clone https://github.com/caelestia-dots/caelestia.git ~/.local/share/caelestia
~/.local/share/caelestia/install.fish
```

## Updating

Simply run `yay` to update the AUR packages, then `cd` into the repo directory and run `git pull` to update the configs.

## Usage

> [!NOTE]
> These dots do not contain a login manager (for now), so you must install a
> login manager yourself unless you want to log in from a TTY. I recommend
> [`greetd`](https://sr.ht/~kennylevinsen/greetd) with
> [`tuigreet`](https://github.com/apognu/tuigreet), however you can use
> any login manager you want.

There aren't really any usage instructions... these are a set of dotfiles.

Here's a list of useful keybinds though:

-   `Super` - open launcher
-   `Super` + `#` - switch to workspace `#`
-   `Super` `Alt` + `#` - move window to workspace `#`
-   `Super` + `T` - open terminal (foot)
-   `Super` + `W` - open browser (zen)
-   `Super` + `C` - open IDE (vscodium)
-   `Super` + `S` - toggle special workspace or close current special workspace
-   `Ctrl` `Alt` + `Delete` - open session menu
-   `Ctrl` `Super` + `Space` - toggle media play state
-   `Ctrl` `Super` `Alt` + `R` - restart the shell
