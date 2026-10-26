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

Host profiles and the personal layer live in a private overlay,
`~/.config/caelestia-plus/` (moimart's: the private repo
`moimart/caelestia-plus-private`, cloned by `caelestia-plus-setup --overlay`).
The defaults have placeholders instead: a daruma profile picture seeded to
`~/.face`, and `lock-ha.example.json` (the Home Assistant cards stay off
without a real `lock-ha.json`). See `hosts/README.md`.

Before this repo goes public, its history needs the private files purged
(`git filter-repo`): the face video, `lock-ha.json` and the behemoth profile
came in with the dotfiles and hypr-config histories. Secrets (the HA token)
were never tracked.

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
4. **Packages.** Done: `pkg/PKGBUILD` builds the four packages (version from
   the shell's tags, e.g. 2.5.0.r315), and `setup/caelestia-plus-setup`
   creates the user's files. Tested from the built packages unpacked in a
   staging folder: the packaged Hyprland config, loaded through the user's
   template, makes the same calls as the repo's; setup in a fresh home made
   every file, and a second run left them alone. Not yet tested on a real
   install: that's the VM in step 6.
5. **CI and the pacman repo.** `.github/workflows/packages.yml` builds the
   AUR packages Arch lacks (libcava, ttf-rubik-vf, quickshell-git,
   caelestia-cli, app2unit, and their AUR dependencies) and caelestia-plus,
   uploads them as an artifact, signs them (key
   `BC40964C5AA4206E09F6148BD849D193EECADBBB`, in
   `~/.local/share/caelestia-plus/signing/`) and publishes the repo to the
   gh-pages branch of the public `moimart/caelestia-plus-packages` (GitHub
   Pages). Creating that repo and storing the secrets is
   `pkg/bootstrap-publishing.sh`, run by hand.
6. **Test, then switch behemoth over.** `tools/vm/run.sh` installs the
   packages in a fresh Arch VM (nested; software rendering), runs setup and
   starts Hyprland. `tools/switch-over.sh --host behemoth` moves behemoth
   from the symlinked checkouts to the packages; `--rollback` undoes it.
   Rehearsed in a fake home shaped like behemoth's: the layers rebuild the
   live shell settings exactly, and rollback restores every link.
7. **Go public.** The private things are in the overlay; the packages hold
   nothing personal. `tools/purge-private-history.sh --push` rewrites this
   repo's history without the face video, `lock-ha.json` and the lock
   screenshot's unblurred versions (checked on a clone); then the repo can
   be made public. The AUR recipe is in `aur/caelestia-plus-git`
   (`tools/aur.sh`); publishing it needs an AUR account.
