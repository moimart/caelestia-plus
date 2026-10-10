# moimart's Caelestia

A long-lived fork of [caelestia-dots/shell](https://github.com/caelestia-dots/shell),
based on upstream `v2.3.0`. It is installed as the `caelestia-shell-moimart`
package, which replaces the AUR `caelestia-shell`.

## Changes from upstream

- **Lock screen Home Assistant cards** (`modules/lock/ha/`): read-only camera,
  energy and entities cards, configured in `~/.config/caelestia/lock-ha.json`.
- **Lock clock** uses the configured clock font (`appearance.font.clock`).
- **Lock profile picture** is a rounded square instead of the clamshell.

## Build and install

```sh
cd pkg && makepkg -si
```

This builds the commit checked out on this machine (commit first), QML and plugin
together, so they always match.

## Pulling upstream changes

```sh
git fetch upstream --tags
git merge v2.5.0          # or any upstream tag
cd pkg && makepkg -si
```

`upstream` is fetch-only; pushes go to `origin` (moimart/caelestia-shell).
