pragma Singleton

import QtQuick
import Quickshell
import Caelestia
import Caelestia.Config
import Caelestia.I18n
import Caelestia.Services

// The Microsoft Surface Dial: pressing it cycles through modes, turning it
// acts in the current one. The device itself is read in C++ (DialDevice, in
// the shell's plugin): event driven, so an idle dial costs nothing. Settings
// are in GlobalConfig.surfaceDial (Nexus → Surface Dial).
//
// Besides the built-in modes, any Home Assistant entity with a level can be a
// mode ("ha:<id>"): a light's brightness, a player's volume, a cover's
// position, a thermostat's temperature... They're HomeAssistant.dialControls,
// added in Nexus → Home Assistant; what turning does comes from the entity's
// domain (haDomains below).
//
// Feedback is the shell's own: a toast for the mode, the OSD for levels
// (system volume through Audio, a Home Assistant entity's through haLevel).
Singleton {
    id: root

    readonly property var cfg: GlobalConfig.surfaceDial
    readonly property bool connected: DialDevice.connected
    readonly property string error: DialDevice.error

    readonly property list<string> builtinModes: ["volume", "zoom", "appScroll", "layoutScroll"]
    readonly property var builtinInfo: ({
            volume: {
                name: Tr.tr("Volume"),
                icon: "volume_up",
                description: Tr.tr("The system volume")
            },
            zoom: {
                name: Tr.tr("Zoom"),
                icon: "zoom_in",
                description: Tr.tr("Hyprland's cursor zoom")
            },
            appScroll: {
                name: Tr.tr("Scroll"),
                icon: "swap_vert",
                description: Tr.tr("Scrolls whatever is under the pointer")
            },
            layoutScroll: {
                name: Tr.tr("Scroll columns"),
                icon: "view_column",
                description: Tr.tr("Moves through the columns of Hyprland's scrolling layout")
            }
        })

    // What a Home Assistant entity's level is, per domain: where it's read
    // from, its range, the step a control gets unless it sets one, and how to
    // set it. Levels are in the entity's units (%, °C...).
    readonly property var haDomains: ({
            light: {
                icon: "lightbulb",
                what: Tr.tr("Brightness"),
                unit: "%",
                value: s => s.state === "on" ? Math.round((s.attributes.brightness ?? 255) / 2.55) : 0,
                range: s => [0, 100],
                step: s => 5,
                // Lights without brightness only go on (turned up) and off (down)
                set: (s, v) => !(s.attributes.supported_color_modes ?? []).some(m => m !== "onoff") ? [s.state !== "on" && v > 0 ? "turn_on" : "turn_off",
                        {}
                    ] : v > 0 ? ["turn_on",
                        {
                            brightness_pct: v
                        }
                    ] : ["turn_off",
                        {}
                    ]
            },
            media_player: {
                icon: "speaker",
                what: Tr.tr("Volume"),
                unit: "%",
                available: s => s.attributes.volume_level !== undefined,
                value: s => Math.round(s.attributes.volume_level * 100),
                range: s => [0, 100],
                step: s => 2,
                set: (s, v) => ["volume_set",
                        {
                            volume_level: v / 100
                        }
                    ]
            },
            cover: {
                icon: "blinds",
                what: Tr.tr("Position"),
                unit: "%",
                available: s => s.attributes.current_position !== undefined,
                value: s => s.attributes.current_position,
                range: s => [0, 100],
                step: s => 5,
                set: (s, v) => ["set_cover_position",
                        {
                            position: v
                        }
                    ]
            },
            valve: {
                icon: "valve",
                what: Tr.tr("Position"),
                unit: "%",
                available: s => s.attributes.current_position !== undefined,
                value: s => s.attributes.current_position,
                range: s => [0, 100],
                step: s => 5,
                set: (s, v) => ["set_valve_position",
                        {
                            position: v
                        }
                    ]
            },
            fan: {
                icon: "mode_fan",
                what: Tr.tr("Speed"),
                unit: "%",
                value: s => s.state === "on" ? (s.attributes.percentage ?? 0) : 0,
                range: s => [0, 100],
                step: s => s.attributes.percentage_step ?? 10,
                set: (s, v) => ["set_percentage",
                        {
                            percentage: v
                        }
                    ]
            },
            climate: {
                icon: "thermostat",
                what: Tr.tr("Temperature"),
                unit: "°",
                available: s => s.attributes.temperature !== undefined && s.attributes.temperature !== null,
                value: s => s.attributes.temperature,
                range: s => [s.attributes.min_temp ?? 7, s.attributes.max_temp ?? 35],
                step: s => s.attributes.target_temp_step ?? 0.5,
                set: (s, v) => ["set_temperature",
                        {
                            temperature: v
                        }
                    ]
            },
            water_heater: {
                icon: "water_heater",
                what: Tr.tr("Temperature"),
                unit: "°",
                available: s => s.attributes.temperature !== undefined && s.attributes.temperature !== null,
                value: s => s.attributes.temperature,
                range: s => [s.attributes.min_temp ?? 30, s.attributes.max_temp ?? 70],
                step: s => s.attributes.target_temp_step ?? 1,
                set: (s, v) => ["set_temperature",
                        {
                            temperature: v
                        }
                    ]
            },
            humidifier: {
                icon: "humidity_percentage",
                what: Tr.tr("Humidity"),
                unit: "%",
                available: s => s.attributes.humidity !== undefined,
                value: s => s.attributes.humidity,
                range: s => [s.attributes.min_humidity ?? 0, s.attributes.max_humidity ?? 100],
                step: s => 1,
                set: (s, v) => ["set_humidity",
                        {
                            humidity: v
                        }
                    ]
            },
            number: {
                icon: "tune",
                what: Tr.tr("Value"),
                unit: "",
                available: s => !isNaN(parseFloat(s.state)),
                value: s => parseFloat(s.state),
                range: s => [s.attributes.min ?? 0, s.attributes.max ?? 100],
                step: s => s.attributes.step ?? 1,
                set: (s, v) => ["set_value",
                        {
                            value: v
                        }
                    ]
            },
            input_number: {
                icon: "tune",
                what: Tr.tr("Value"),
                unit: "",
                available: s => !isNaN(parseFloat(s.state)),
                value: s => parseFloat(s.state),
                range: s => [s.attributes.min ?? 0, s.attributes.max ?? 100],
                step: s => s.attributes.step ?? 1,
                set: (s, v) => ["set_value",
                        {
                            value: v
                        }
                    ]
            }
        })
    readonly property list<string> haSupportedDomains: Object.keys(haDomains)

    // Every mode there is, in their usual order: Home Assistant ones after zoom
    readonly property list<string> allModes: ["volume", "zoom", ...HomeAssistant.dialControls.map(c => `ha:${c.id}`), "appScroll", "layoutScroll"]
    // The modes a press cycles through
    readonly property list<string> modes: cfg.modes.filter(m => allModes.includes(m))
    property int index
    readonly property string mode: modes.length ? modes[index % modes.length] : ""

    // The Home Assistant control the current mode is, or null
    readonly property var haControl: mode.startsWith("ha:") ? controlFor(mode) : null
    readonly property var haState: haControl ? HomeAssistant.entity(haControl.instance, haControl.entity) : null

    // What the current control is at, as far as we know: what we last asked
    // for, until Home Assistant reports back. In its units, and 0-1 for the OSD
    property real haValue
    property bool haPending
    readonly property real haLevel: {
        const r = haState && haDomain(haControl) ? haDomain(haControl).range(haState) : [0, 1];
        return r[1] > r[0] ? (haValue - r[0]) / (r[1] - r[0]) : 0;
    }
    // The OSD shows the control's level for a moment after the dial moves it
    readonly property bool haShowing: haShow.running
    readonly property string haIcon: haControl ? (haDomain(haControl)?.icon ?? "home_iot_device") : "home_iot_device"
    signal haLevelShown

    // Rotation since the last step: steps are taken at most every 120 ms, one
    // per tick whatever the speed, as the dial sends many small events
    property int pending

    function controlFor(mode: string): var {
        const id = mode.slice(3);
        return HomeAssistant.dialControls.find(c => c.id === id) ?? null;
    }

    function haDomain(control: var): var {
        return control ? haDomains[control.entity.split(".")[0]] ?? null : null;
    }

    // A mode's name and icon, for toasts and settings
    function info(mode: string): var {
        if (!mode.startsWith("ha:"))
            return builtinInfo[mode] ?? {
                name: mode,
                icon: "adjust",
                description: ""
            };
        const c = controlFor(mode);
        const d = haDomain(c);
        const s = c ? HomeAssistant.entity(c.instance, c.entity) : null;
        const name = c?.name || s?.attributes?.friendly_name || c?.entity || mode;
        return {
            name: name,
            icon: d?.icon ?? "home_iot_device",
            description: d ? Tr.tr("%1 of %2").arg(d.what).arg(c.entity) : Tr.tr("%1 can't be turned by the dial").arg(c?.entity ?? "")
        };
    }

    // A control's step: its own, or what suits the entity
    function stepOf(control: var): real {
        if (control?.step > 0)
            return control.step;
        const d = haDomain(control);
        const s = control ? HomeAssistant.entity(control.instance, control.entity) : null;
        return d && s ? d.step(s) : 1;
    }

    function step(dir: int): void {
        if (mode.startsWith("ha:")) {
            haStep(dir);
            return;
        }
        switch (mode) {
        case "volume":
            Audio.setVolume(Audio.volume + dir * cfg.volumeStep / 100);
            break;
        case "zoom":
            zoom.step(dir);
            break;
        case "appScroll":
            // Clockwise scrolls down, like a wheel turned towards you
            DialDevice.scroll(-dir * cfg.scrollSpeed);
            break;
        case "layoutScroll":
            layout.step(dir);
            break;
        }
    }

    function haStep(dir: int): void {
        const d = haDomain(haControl);
        if (!d || !haState || haState.state === "unavailable" || !(d.available?.(haState) ?? true)) {
            toast(Tr.tr("%1 isn't available").arg(info(mode).name), haIcon, Toast.Warning);
            return;
        }
        setHaValue(haValue + dir * stepOf(haControl));
    }

    // In the control's units; also for the OSD's slider (setHaLevel)
    function setHaValue(value: real): void {
        const d = haDomain(haControl);
        if (!d || !haState)
            return;
        const r = d.range(haState);
        const step = stepOf(haControl);
        // On the step's grid, as Home Assistant would round it anyway
        const decimals = step < 1 ? Math.ceil(-Math.log10(step)) : 0;
        const next = Number(Math.max(r[0], Math.min(r[1], value)).toFixed(decimals));
        haShow.restart();
        if (next !== haValue) {
            haValue = next;
            haPending = true;
            haSettle.restart();
            const call = d.set(haState, next);
            HomeAssistant.call(haControl.instance, haControl.entity.split(".")[0], call[0], call[1], {
                entity_id: haControl.entity
            });
        }
        haLevelShown();
    }

    function setHaLevel(level: real): void {
        const d = haDomain(haControl);
        if (!d || !haState)
            return;
        const r = d.range(haState);
        setHaValue(r[0] + level * (r[1] - r[0]));
    }

    function syncHaValue(): void {
        const d = haDomain(haControl);
        haValue = d && haState && (d.available?.(haState) ?? true) ? d.value(haState) : 0;
    }

    function cycle(): void {
        if (modes.length === 0)
            return;
        index = (index + 1) % modes.length;
        const i = info(mode);
        toast(i.name, i.icon);
    }

    // One dial toast at a time: a new one replaces the last
    function toast(title: string, icon: string, type: int): void {
        if (!cfg.toasts)
            return;
        const toasts = Toaster.toasts;
        for (let i = 0; i < toasts.length; i++)
            if (toasts[i].message === dialLabel && !toasts[i].closed)
                toasts[i].close();
        Toaster.toast(title, dialLabel, icon, type ?? Toast.Info, 1500);
    }

    readonly property string dialLabel: Tr.tr("Surface Dial")

    onModesChanged: {
        if (index >= modes.length)
            index = 0;
    }

    onHaControlChanged: {
        haPending = false;
        syncHaValue();
    }

    // Home Assistant reported: that's the truth again, unless we're still
    // waiting for ours to land
    onHaStateChanged: {
        if (!haPending)
            syncHaValue();
    }

    // Keep the controls in the cycle live, one watch per instance
    readonly property var haWatched: {
        const out = {};
        if (cfg.enabled)
            for (const m of modes) {
                const c = controlFor(m);
                if (c?.entity)
                    (out[c.instance] = out[c.instance] ?? []).push(c.entity);
            }
        return out;
    }
    property var haWatchedBefore: ({})

    onHaWatchedChanged: syncWatches()

    function syncWatches(): void {
        for (const inst of Object.keys(haWatchedBefore))
            if (!(inst in haWatched))
                HomeAssistant.unwatch("surface-dial", inst);
        for (const inst of Object.keys(haWatched))
            HomeAssistant.watch("surface-dial", inst, haWatched[inst]);
        haWatchedBefore = haWatched;
    }

    // Before dial controls, one media player could be the "haVolume" mode
    Component.onCompleted: {
        syncWatches();
        if (cfg.modes.includes("haVolume"))
            cfg.modes = cfg.modes.filter(m => m !== "haVolume");
    }

    Timer {
        id: haShow

        interval: 2000
    }

    Timer {
        id: haSettle

        interval: 1500
        onTriggered: {
            root.haPending = false;
            root.syncHaValue();
        }
    }

    Binding {
        target: DialDevice
        property: "enabled"
        value: root.cfg.enabled
    }

    Connections {
        function onRotated(delta: int): void {
            root.pending += Math.sign(delta);
            // Idle: act on the first event at once, then at the tick's pace
            if (!tick.running) {
                tick.triggered();
                tick.start();
            }
        }

        function onPressed(): void {
            root.cycle();
        }

        function onConnectedChanged(): void {
            if (DialDevice.connected)
                root.toast(Tr.tr("Connected"), "radio_button_checked");
            else
                root.toast(Tr.tr("Disconnected"), "radio_button_unchecked");
        }

        target: DialDevice
    }

    Timer {
        id: tick

        interval: 120
        repeat: true
        onTriggered: {
            const dir = Math.sign(root.pending);
            root.pending = 0;
            if (dir === 0) {
                stop();
                return;
            }
            root.step(dir);
        }
    }

    // Hyprland's cursor zoom: kept here rather than read back on every step
    QtObject {
        id: zoom

        property real factor: 1
        property real lastSet: 0

        function step(dir: int): void {
            // Reread after a pause: something else may have changed it
            if (Date.now() - lastSet > 5000)
                factor = Number(Hypr.options["cursor:zoom_factor"] ?? factor) || 1;
            const next = Math.max(1, Math.min(root.cfg.maxZoom, factor + dir * root.cfg.zoomStep));
            if (next === factor)
                return;
            factor = next;
            lastSet = Date.now();
            const value = next.toFixed(2);
            Hypr.extras.message(Hypr.usingLua ? `eval hl.config({ cursor = { zoom_factor = ${value} } })` : `keyword cursor:zoom_factor ${value}`);
        }
    }

    // Hyprland's scrolling layout
    QtObject {
        id: layout

        property real last: 0

        function step(dir: int): void {
            const px = root.cfg.layoutPixels;
            let msg;
            if (px > 0) {
                msg = `move ${dir > 0 ? "+" : "-"}${px}`;
            } else {
                // A column at a time: let the animation finish first
                if (Date.now() - last < 350)
                    return;
                msg = `move ${dir > 0 ? "+" : "-"}col`;
            }
            last = Date.now();
            Hypr.dispatch(Hypr.usingLua ? `hl.dsp.layout("${msg}")` : `layoutmsg ${msg}`);
        }
    }
}
