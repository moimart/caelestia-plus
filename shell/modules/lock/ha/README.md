# Home Assistant lock cards

Read-only Home Assistant cards in the lock screen's side columns, polled
over HA's REST API only while the screen is locked.

## Configure

`~/.config/caelestia/lock-ha.json`, reloaded live:

| Key | Meaning |
|---|---|
| `url` | HA base URL |
| `tokenFile` | file holding a long-lived access token (default `~/.config/caelestia/ha-token`, keep it `chmod 600`) |
| `interval` | poll seconds while locked (default 10) |
| `hide` | built-in lock cards to hide: `"fetch"`, `"resources"` |
| `left`, `right` | cards for each side column, top to bottom |

Card types:

- `camera`: `entity`, optional `name`, `aspect` (height/width, default 9/16)
- `energy`: `solar`, `home`, `grid`, `battery_soc`, `battery_power`, `autarky`, optional `title`, `grid_invert`, `battery_invert`
- `entities`: `title`, `entities` (ids, or `{ entity, name, icon }` with a Material Symbols icon name)

Anyone at the locked screen can see these cards, including the camera.
