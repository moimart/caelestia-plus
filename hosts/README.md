# Host profiles, and your personal layer

The default config is complete on its own. Two layers can extend it:

- **A host profile**: what belongs to one machine (its monitors, display
  scaling, a TV setup).
- **Your personal layer**: what's yours on every machine (your profile
  picture, your home's Home Assistant cards, your own binds).

Both are usually private, so they live in an overlay outside this repo:
`~/.config/caelestia-plus/`, best kept as your own private git repo.
`caelestia-plus-setup --overlay <git URL>` clones it there.

```
~/.config/caelestia-plus/
  host                     the profile this machine uses (not in git)
  hosts/<name>/
    hypr/
      monitors.lua         replaces hypr/lua/monitors.lua (any default module
                           can be replaced by one of the same name)
      host.lua             runs last: extra env, binds, modules
    caelestia/
      shell.json           shell settings on top of the defaults
      monitors/            per-monitor shell settings
  personal/
    hypr/personal.lua      runs after the defaults, before host.lua
    caelestia/
      shell.json           shell settings on top of the defaults
      lock-ha.json         Home Assistant lock cards (setup copies it to
                           ~/.config/caelestia; see lock-ha.example.json)
      assets/              files your settings point at
```

The layers stack in this order, each overriding the ones before: the
defaults, your personal layer, the host profile, then your own files in
`~/.config` (`~/.config/hypr/hyprland.lua`, `~/.config/caelestia/shell.json`).
Settings → Displays saves what you change there in
`~/.config/caelestia/displays.lua` (from `displays.json`), loaded after the
host profile, as partial rules: only the fields you changed, so the rest of
the profile's monitor rules stays. Its "Reset" forgets them again. Which
displays get the shell is `monitors/<output>/shell.json` (`enabled`), on top
of the profile's.
The shell gets the layers' `caelestia/` folders through `$XDG_CONFIG_DIRS`,
which the Hyprland config sets.

The profile name comes from, in order: `$CAELESTIA_PLUS_HOST`,
`~/.config/caelestia-plus/host`, the hostname. A machine without a profile
gets the defaults: every monitor at its preferred mode and scale. Profiles
shipped here (`hosts/example`) are searched after your overlay.

## Checking a config

`hypr/tools/record.lua` runs the Hyprland config outside Hyprland and prints
every call it makes, so two versions can be compared:

```sh
CAELESTIA_PLUS_HOST=example lua5.4 hypr/tools/record.lua "$PWD/hypr/hyprland.lua"
```
