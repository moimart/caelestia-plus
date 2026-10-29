# Home Assistant on the lock screen

The lock screen's two side columns are a list of cards each, set in Settings →
Lock screen and kept in `~/.config/caelestia/lock.json`
(`services/LockLayout.qml`). The clock and password stay in the middle.

Home Assistant cards there only show: nothing on the lock screen can be
pressed. They use the shell's live connection to each instance
(`services/HomeAssistant.qml`, Settings → Home Assistant), so a card updates as
soon as the entity changes.

## lock.json

```json
{
    "left": [{ "type": "weather" }, { "type": "camera", "entity": "camera.door" }, { "type": "media" }],
    "right": [{ "type": "resources" }, { "type": "haEntity", "entity": "sensor.outside" }, { "type": "notifications" }]
}
```

Built in: `weather`, `fetch`, `media`, `resources`, `notifications`. Media and
notifications take the space left in their column.

Home Assistant, each with an optional `instance` (an id from Settings → Home
Assistant; the first one otherwise):

- `camera`: `entity`, optional `name`, `aspect` (height/width, default 9/16),
  `interval` (seconds between pictures, default 5)
- `energy`: `solar`, `home`, `grid`, `battery_soc`, `battery_power`,
  `autarky`, optional `title`, `grid_invert`, `battery_invert`
- `entities`: `title`, `entities` (ids, or `{ entity, name, icon }` with a
  Material Symbols icon name)
- `haEntity`: `entity`, optional `name`
- `haCard`: `card`, a dashboard card's config (Settings picks one from your
  dashboards)

Without `lock.json` the lock screen looks as it always has: weather, system,
media | resources, notifications, with the cards from the older
`lock-ha.json` (`left`, `right`, `hide`) if there is one.

`caelestia shell lockLayout get` prints the layout.

Anyone at the locked screen can see these cards, including the camera.
