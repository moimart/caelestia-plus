# dotfiles

Desktop configuration for my Caelestia setup. The shell itself is my fork,
[moimart/caelestia-shell](https://github.com/moimart/caelestia-shell).

```sh
./install.sh
```

| Path | What |
|---|---|
| `caelestia/` | The live `~/.config/caelestia` (the whole directory is symlinked). Only `shell.json`, `cli.json`, `lock-ha.json` and `monitors/*/shell.json` are tracked; the HA token (`ha-token`) and backups stay local. |
| `fonts/InstrumentSerif/` | Instrument Serif (SIL OFL, see `OFL.txt`), used for the desktop and lock screen clocks via `appearance.font.clock`. |
| `download-sorter/` | Two user services: **download-sorter** moves finished downloads by extension rules (AppImages → `~/Applications`), **appimage-desktop** keeps launcher entries in sync with `~/Applications`. See its README. |

Notable settings:

- `cli.json` `wallpaper.postHook` forces the **vibrant** scheme variant after
  every wallpaper change, while smart scheme still picks dark/light.
- `shell.json` `appearance.font.clock` is **Instrument Serif**.
- `lock-ha.json` defines the lock screen Home Assistant cards.

The whole `caelestia/` directory is linked, rather than the files, because the
shell saves `shell.json` by writing a temp file and renaming it, which would
replace a file symlink with a plain file.
