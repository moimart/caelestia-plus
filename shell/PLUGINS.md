# Writing plugins

This fork's plugins come in two kinds: **desktop widgets** and **actions**
(buttons on the right bar; see [Action plugins](#action-plugins) at the end).
A widget is a piece of QML that lives on the desktop, above the wallpaper and
below your windows. You place and resize widgets with **Super+Ctrl+W**, which
binds the shell's `caelestia:widgets` global shortcut, or from Nexus →
Plugins.

The built-in Eyes widget (`modules/widgets/builtin/eyes/`) and the example in
`examples/widgets/clock/` are complete, working plugins to copy from.

## Where plugins live

| Folder | What goes there |
| --- | --- |
| `modules/widgets/builtin/<name>/` | Built-in widgets, shipped with the shell |
| `~/.config/caelestia/plugins/widgets/<name>/` | Your own widgets |

Each plugin is one folder holding a `widget.json` manifest and the QML file
it names. The shell scans both places at start-up. To scan again, use any of:
- Nexus → Plugins → Rescan;
- opening the editor;
- `caelestia shell widgets rescan`.

Placed widgets, meaning which plugin, which monitor, where, how big, and each
one's settings, are saved in `~/.local/state/caelestia/widgets.json`.

## widget.json

```json
{
    "id": "example-clock",
    "name": "Clock",
    "description": "The time, in the scheme's colours",
    "icon": "schedule",
    "author": "you",
    "version": "1.0",
    "main": "Clock.qml",
    "defaultSize": [220, 90],
    "minSize": [80, 32],
    "keepAspect": false,
    "needsCursor": false
}
```

| Key | Required | Meaning |
| --- | --- | --- |
| `id` | yes | Unique id. Placed widgets refer to it, so don't change it once you use the widget. If two plugins share an id, the built-in one wins. |
| `main` | yes | The QML file to load, relative to the folder |
| `name` | | Shown in the editor's palette and in Nexus |
| `description`, `author`, `version` | | Shown in Nexus |
| `icon` | | A [Material Symbols](https://fonts.google.com/icons) name, for the palette |
| `defaultSize` | | `[width, height]` when first placed, in logical pixels (default `[240, 160]`) |
| `minSize` | | The smallest the editor lets it be resized to (default `[64, 64]`) |
| `keepAspect` | | Keep the width:height ratio while resizing |
| `needsCursor` | | Give the widget the pointer position (see below). The shell only polls the pointer while a placed widget asks for it. |

## The QML file

The root item fills the rectangle the widget is given, so lay it out relative
to its own size. Declare any of these properties on the root item to receive
them; leave out the ones you don't need:

| Property | Type | What you get |
| --- | --- | --- |
| `cursor` | `point` | The pointer relative to the widget's top-left, updated up to 60 times a second. It can be outside the widget, even on another monitor. Needs `"needsCursor": true`. |
| `editing` | `bool` | True while the editor is open, e.g. to show a hint or pause animations |
| `screen` | `ShellScreen` | The monitor the widget is on |
| `settings` | `var` | This widget's own settings object, `{}` until set |

You can import the shell's own modules, so a widget matches the rest of the
desktop and follows the colour scheme:

```qml
import QtQuick
import Caelestia.Config      // Tokens: fonts, rounding, spacing, animation curves
import qs.components         // StyledText, StyledRect, MaterialIcon, ...
import qs.services           // Colours, Time, Audio, Players, Weather, ...

Item {
    id: root

    property var settings: ({})

    StyledText {
        anchors.fill: parent
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: Time.format(root.settings.format ?? "hh:mm")
        color: Colours.palette.m3onSurface
        font: Tokens.font.clock.size(Math.max(8, root.height * 0.45)).build()
    }
}
```

Guidelines:

- **Colours:** use `Colours.palette.m3*` rather than fixed colours, so the
  widget follows the wallpaper's scheme and light or dark mode.
- **Keep it quiet:** the desktop isn't a dashboard. Use thin strokes, the
  scheme's text colour at partial opacity, little motion, and no backgrounds
  unless the widget needs one.
- **Scale with the widget:** it can be resized to anything from `minSize` up,
  so derive stroke widths, font sizes and margins from `width` and `height`.
- **Mind the cost:** widgets run all the time. Avoid timers faster than you
  need, and stop work while `editing` if it gets in the way.
- **No input:** widgets sit under your windows, and they are moved by
  dragging in the editor. Treat them as something to look at, not to click.

## Settings

Each placed widget carries a `settings` object that your QML reads, as in
`root.settings.format` above. Describe them in `widget.json` and Settings →
Plugins → (the placed widget) draws a form for them:

```json
"settings": [
    { "key": "format", "type": "string", "label": "Format", "placeholder": "hh:mm" },
    { "key": "size", "type": "number", "label": "Size", "min": 8, "max": 64, "step": 2, "default": 24 },
    { "key": "seconds", "type": "bool", "label": "Show seconds" },
    { "key": "style", "type": "enum", "label": "Style",
      "options": [{ "value": "orbit", "label": "Orbit" }, { "value": "dots", "label": "Dots" }] },
    { "key": "instance", "type": "haInstance", "label": "Home Assistant" },
    { "key": "entity", "type": "haEntity", "label": "Light", "domains": ["light"] },
    { "key": "card", "type": "haCard", "label": "Dashboard card" }
]
```

`haInstance` picks one of your Home Assistant instances (Settings → Home
Assistant), `haEntity` searches its entities (only the `domains` given, if
any), and `haCard` picks a card from one of its dashboards: it sets
`dashboard`, `cardPath` and `card` (the card's config).

Without the form, set them with any of:
- the IPC call: `caelestia shell widgets configure <uid> '{"format": "hh:mm:ss"}'`;
- the `widgets` MCP tool;
- editing `widgets.json` while the shell is stopped.

`caelestia shell widgets list` shows each widget's `uid`.

### Home Assistant in a widget

The built-in Home Assistant widgets (switch, button, entity, camera, dashboard
card) are ordinary plugins in `modules/widgets/builtin/ha-*`. Yours can use the
same pieces: `import qs.components.ha` gives `HaTile` (an entity: icon, name,
state; tapping it acts like tapping it in Home Assistant unless `readOnly`),
`HaCameraView` and `HaCard` (a dashboard card's config, drawn natively).
`import qs.services` gives the `HomeAssistant` singleton: `entity(instance,
id)` for live state (after `watch(consumer, instance, ids)`; `unwatch` when you
go), `activate(instance, id)` and `call(instance, domain, service, data)`. An
empty `instance` means the first one.

## Trying a plugin out

1. Copy the plugin's folder into `~/.config/caelestia/plugins/widgets/`, for
   example `cp -r examples/widgets/clock ~/.config/caelestia/plugins/widgets/`.
2. Press Super+Ctrl+W. The editor rescans, and your widget appears in the
   palette at the bottom. Click it to add it to that monitor.
3. Drag it into place, resize it by its corners, then press Esc.

QML errors appear in the shell's log: `qs -c caelestia log`, or
`qs -p <repo> log` for a dev shell. Qt caches a loaded widget file, so after
editing your QML, restart the shell (Ctrl+Super+Alt+R) to see the change.

## Controlling widgets from scripts

IPC target `widgets`. `caelestia shell widgets <function> ...` runs
`qs -c caelestia ipc call widgets <function> ...`:

| Call | Does |
| --- | --- |
| `list` | Plugins and placed widgets, as JSON |
| `add <plugin-id> <monitor>` | Place a new widget, centred |
| `place <uid> <x> <y> <width> <height>` | Move/resize, in the monitor's logical pixels |
| `configure <uid> <json>` | Replace its settings |
| `remove <uid>` | Remove it |
| `edit` / `done` / `toggle` | Open/close the editor |
| `rescan` | Re-read the plugin folders |

## How it works (for working on the shell itself)

- `services/Widgets.qml` finds plugins, and keeps and saves placed widgets.
  It also turns on `Hypr.extras.trackCursor` when a placed widget needs the
  pointer, except in game mode.
- The pointer comes from Hyprland's `cursorpos` request, polled by
  `HyprExtras` in the C++ plugin. It polls at about 60 Hz while the pointer
  moves and drops to 10 Hz once it has been still for a second.
- `modules/widgets/WidgetHost.qml` loads one widget, turns the global pointer
  position into the widget's own coordinates, and passes in the properties
  above.
- `modules/widgets/DesktopWidgets.qml` holds a screen's widgets inside the
  background window (`modules/background/Background.qml`). Widgets only appear
  on monitors where the background is enabled.
- `modules/widgets/WidgetsEditor.qml`, `EditView.qml` and `EditFrame.qml`
  form the editor: an overlay on each monitor that shows the widgets above
  your windows while you place them.

## Action plugins

An action is a button on the right bar (Settings → Panels → Right bar), like
the built-in screenshot and screen recording ones. An action plugin is a folder
in `~/.config/caelestia/plugins/actions/` with an `action.json`, and nothing
else needed:

```json
{
    "id": "downloads",
    "name": "Downloads",
    "icon": "download",
    "description": "Open the Downloads folder",
    "shell": "xdg-open \"$(xdg-user-dir DOWNLOAD)\""
}
```

- `id`: unique; the ones of built-in actions are taken.
- `name` and `description`: what Settings shows.
- `icon`: a [Material Symbols](https://fonts.google.com/icons) name.
- What it runs, one of:
  - `command`: a list, run in the plugin's folder (`["./run.sh", "--fast"]`);
  - `shell`: a line for `sh -c`, also in the plugin's folder;
  - `ipc`: the shell's own IPC, `["target", "function", args...]`, e.g.
    `["picker", "openFreeze"]` (`qs -c caelestia ipc show` lists them all).

Once the folder is there, the action shows in Settings → Panels → Right bar
(opening that page looks again), with a switch to put it on the bar.
[`examples/actions/downloads`](examples/actions/downloads) is the one above.

