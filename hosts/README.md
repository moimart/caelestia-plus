# Host profiles

A host profile holds what belongs to one machine: its monitors, display
scaling, a TV setup. Everything else is the default config, shared by every
machine.

```
hosts/<name>/
  hypr/
    monitors.lua   replaces hypr/lua/monitors.lua (any default module can be
                   replaced by one of the same name)
    host.lua       runs after the default config: extra env, binds, modules
  caelestia/
    shell.json     settings on top of config/caelestia/shell.json
    monitors/      per-monitor shell settings
    ...            other files for ~/.config/caelestia (lock-ha.json, assets)
```

The profile name comes from, in order: `$CAELESTIA_PLUS_HOST`,
`~/.config/caelestia-plus/host`, the hostname. A machine without a profile
gets the defaults: every monitor at its preferred mode and scale.

Profiles can also live outside the repo, in
`~/.config/caelestia-plus/hosts/<name>/`, which is searched first. That's
where private ones go.

## behemoth

The desktop: a 7680x2160 ultrawide on DP-1 (scale 1.6666, 10-bit) and a TV
behind an AVR on HDMI-A-1, used as a cast target (`tv_sink.lua`), with the
shell off on it. Also `GDK_SCALE=2`, the Home Assistant lock cards and the
animated profile picture.

## Checking a profile

`hypr/tools/record.lua` runs the Hyprland config outside Hyprland and prints
every call it makes, so two versions can be compared:

```sh
CAELESTIA_PLUS_HOST=behemoth lua5.4 hypr/tools/record.lua "$PWD/hypr/hyprland.lua"
```
