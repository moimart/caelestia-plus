# caelestia-plus: the plan

One repo for moimart's Caelestia desktop: the shell, every config, and the Arch
packages that install them. The goal is a fresh Arch install that becomes this
desktop with:

```sh
# once: trust the repo (see "The pacman repo")
sudo pacman -Syu caelestia-plus
caelestia-plus-setup
```

It's for moimart's machines first, but anyone should be able to use it: every
default can be overridden without editing packaged files.

## What's here

| Folder | What | Came from |
| --- | --- | --- |
| `shell/` | The Quickshell shell, its C++ plugin, the camera daemon | moimart/caelestia-shell (fork of caelestia-dots/shell) |
| `dots/` | App configs: fish, kitty (and `kitty-crt`), foot, ghostty, btop, fastfetch, uwsm, ... | moimart/caelestia (fork of caelestia-dots/caelestia) |
| `hypr/` | The Hyprland Lua config | moimart/hypr-config |
| `config/` | The shell's own config (`shell.json`, art), fonts, download sorter | moimart/dotfiles |

All four came in as git subtrees with their full history. The two forks can
still take upstream releases:

```sh
git subtree pull --prefix=shell https://github.com/caelestia-dots/shell v2.6.0
git subtree pull --prefix=dots  https://github.com/caelestia-dots/caelestia main
```

Until the switch-over (step 6), the old repos stay the live ones; changes made
there come in with `git subtree pull --prefix=<folder> ~/code/<repo> main`.

## Layers

Packages never touch your home folder. Settings come in three layers, each
overriding the one before:

1. **Package defaults**, in `/usr/share/caelestia-plus/`: the Hyprland modules,
   a base `shell.json`, app configs, art. Updated by pacman.
2. **A host profile**, for what belongs to one machine: monitors, TV/cast
   scripts, per-monitor shell settings. Picked by hostname; machines without
   one get autodetected defaults.
3. **Your overrides**, in `~/.config`: small files that load the layers below
   and change what you like. Created once by `caelestia-plus-setup`, never
   overwritten.

How each kind of config layers:

| Config | Package | Yours |
| --- | --- | --- |
| Hyprland | Lua modules on `package.path` | `~/.config/hypr/hyprland.lua` loads the packaged config, then adds or rebinds (or `~/.config/caelestia/hypr-user.lua`) |
| Shell | `/etc/xdg/caelestia/shell.json`; the host profile's `caelestia/` through `$XDG_CONFIG_DIRS` | `~/.config/caelestia/shell.json` holds only your changes |
| kitty, foot, ghostty | configs under `/usr/share/caelestia-plus/dots` | your config `include`s the packaged one |
| fish | `/usr/share/fish/vendor_conf.d/caelestia-plus.fish` | your `config.fish` runs after it |
| fastfetch | `/etc/xdg/fastfetch/config.jsonc` | your own file replaces it |
| Scripts (`kitty-crt`, `launch-or-focus`, ...) | `/usr/lib/caelestia-plus/bin` on `PATH` | `~/.local/share/bin` comes first |
| btop, micro, the CLI's `cli.json` | a starting point | copied once by setup, then yours |
| Browsers, editors, Spicetify, Thunar | optional | setup asks, like the upstream installer |

The shell's layering (in `shell/plugin/src/Caelestia/Settings/settingsfile.cpp`):
a file under `~/.config` reads the same path under each `$XDG_CONFIG_DIRS`
entry first, lowest priority first, and puts yours on top; objects merge key
by key, anything else replaces. Only what differs from those base files is
written back. Without base files nothing changes.

### Where things install

```
/usr/share/caelestia-plus/
  hypr/                     the Hyprland config (hypr/)
  hosts/<name>/             host profiles (hosts/)
  caelestia/assets/         the shell's art (config/caelestia/assets)
  dots/                     app configs (dots/)
/usr/lib/caelestia-plus/bin scripts (dots/bin)
/etc/xdg/caelestia/shell.json  the shell's defaults (config/caelestia/shell.json)
~/.config/hypr/hyprland.lua    yours: loads the packaged config, then your changes
                               (setup/templates/hypr/hyprland.lua)
```

### Private things

Some of what's here can't go public: `config/caelestia/assets/face.mp4` (a
video of a face), the Home Assistant lock cards (`lock-ha.json` names a home's
entities), and the behemoth host profile. Before the repo goes public these
move to a private overlay (a small private repo, or a local folder) that
`caelestia-plus-setup` layers on top. Secrets (the HA token) were never
tracked and stay that way.

## Packages

One split PKGBUILD in `pkg/`:

| Package | Contents |
| --- | --- |
| `caelestia-plus` | The meta package: depends on all of the below |
| `caelestia-shell-moimart` | The shell (what `shell/pkg` builds today) |
| `caelestia-plus-hypr` | The Hyprland modules; depends on hyprland, hypridle, app2unit, ... |
| `caelestia-plus-config` | Base shell config, art, fonts, app configs, user services, `caelestia-plus-setup` |

Optional extras stay `optdepends`: onnxruntime-cpu (camera features), howdy,
mpvpaper.

## The pacman repo

CI (GitHub Actions, in the Arch image the shell already uses) builds every
package, runs `repo-add`, signs with a GPG key kept as a GitHub secret, and
uploads to a fixed GitHub release (`x86_64`). It also rebuilds the AUR
dependencies (`quickshell-git`, `caelestia-cli`) so the shell's C++ plugin
always matches the Quickshell it was built against.

On a new machine:

```ini
# /etc/pacman.conf
[caelestia-plus]
SigLevel = Required
Server = https://github.com/moimart/caelestia-plus/releases/download/x86_64
```

plus trusting the key once (`pacman-key --recv-keys` and `--lsign-key`, later a
keyring package).

## Steps

1. **Monorepo.** Done: the four repos as subtrees, pushed (private).
2. **Split generic from host.** Done: `hosts/behemoth/` (see
   `hosts/README.md`) has the monitor rules, `tv_sink`/`tv_grid`,
   `GDK_SCALE=2`, the per-monitor shell settings, the HA lock cards and the
   face video. The default monitor rule is preferred/auto, wallpapers are in
   `~/Pictures/Wallpapers`, and `kitty-crt` no longer assumes a home folder.
   `hypr/tools/record.lua` showed the behemoth profile makes the same 299
   Hyprland calls as the old config. The shell side of the profile
   (`caelestia/shell.json`) only takes effect with step 3.

   Still personal, in the defaults: the `SUPER + A` bind to
   `~/.local/bin/hal-command`, and the app choices in `hypr/lua/variables.lua`
   (Chrome, nautilus). Fine as defaults, but `hal-command` should move to a
   personal layer before going public.
3. **Layering.** Done for Hyprland and the shell: the user's `hyprland.lua`
   template, the shell's base files (in caelestia-shell first, so behemoth
   gets it through its usual package; tested with a throwaway program, 9
   cases), and `hyprland.lua` adding the host profile to `$XDG_CONFIG_DIRS`.
   Still to check: the shell in the dev shell on behemoth's real config.
   The app configs' layering (table above) is set up with the packages, in
   step 4.
4. **Packages.** The split PKGBUILD and `caelestia-plus-setup`.
5. **CI and the pacman repo.** Build, sign, publish; the weekly AUR rebuild.
6. **Switch behemoth over** from symlinks to packages, then test a fresh Arch
   install in a VM.
7. **Go public.** Move private things to the overlay, add AUR recipes.
