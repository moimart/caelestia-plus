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
// are in GlobalConfig.surfaceDial (Nexus → Surface Dial; the Home Assistant
// media player is chosen in Nexus → Home Assistant).
//
// Feedback is the shell's own: a toast for the mode, the OSD for volumes
// (system volume through Audio, a Home Assistant player's through haVolume).
Singleton {
    id: root

    readonly property var cfg: GlobalConfig.surfaceDial
    readonly property bool connected: DialDevice.connected
    readonly property string error: DialDevice.error

    // What each mode is called and shown with
    readonly property var modeInfo: ({
            volume: {
                name: Tr.tr("Volume"),
                icon: "volume_up"
            },
            zoom: {
                name: Tr.tr("Zoom"),
                icon: "zoom_in"
            },
            haVolume: {
                name: haName || Tr.tr("Home Assistant volume"),
                icon: "speaker"
            },
            appScroll: {
                name: Tr.tr("Scroll"),
                icon: "swap_vert"
            },
            layoutScroll: {
                name: Tr.tr("Scroll columns"),
                icon: "view_column"
            }
        })
    readonly property list<string> allModes: ["volume", "zoom", "haVolume", "appScroll", "layoutScroll"]
    // The modes a press cycles through: haVolume only once a player is picked
    readonly property list<string> modes: cfg.modes.filter(m => allModes.includes(m) && (m !== "haVolume" || cfg.haEntity))
    property int index
    readonly property string mode: modes.length ? modes[index % modes.length] : ""

    // Home Assistant's player, live while the mode is in the cycle
    readonly property string haInstance: cfg.haInstance || HomeAssistant.defaultId
    readonly property bool haWanted: cfg.enabled && modes.includes("haVolume")
    readonly property var haState: haWanted ? HomeAssistant.entity(haInstance, cfg.haEntity) : null
    readonly property string haName: haState?.attributes?.friendly_name ?? ""
    readonly property bool haAvailable: haState !== null && haState.state !== "unavailable" && haState.attributes?.volume_level !== undefined
    // What the player is at, as far as we know: what we last asked for, until
    // Home Assistant reports back
    property real haVolume: haState?.attributes?.volume_level ?? 0
    property bool haPending
    // The OSD shows the player's volume for a moment after the dial moves it
    readonly property bool haShowing: haShow.running
    signal haVolumeShown

    // Rotation since the last step: steps are taken at most every 120 ms, one
    // per tick whatever the speed, as the dial sends many small events
    property int pending

    function step(dir: int): void {
        switch (mode) {
        case "volume":
            Audio.setVolume(Audio.volume + dir * cfg.volumeStep / 100);
            break;
        case "zoom":
            zoom.step(dir);
            break;
        case "haVolume":
            haStep(dir);
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
        if (!haAvailable) {
            toast(Tr.tr("%1 isn't available").arg(haName || cfg.haEntity), "speaker", Toast.Warning);
            return;
        }
        setHaVolume(haVolume + dir * cfg.haStep / 100);
    }

    // Also for the OSD's slider
    function setHaVolume(volume: real): void {
        const next = Math.round(Math.max(0, Math.min(1, volume)) * 100) / 100;
        haShow.restart();
        if (next === haVolume) {
            haVolumeShown();
            return;
        }
        haVolume = next;
        haPending = true;
        haSettle.restart();
        HomeAssistant.call(haInstance, "media_player", "volume_set", {
            volume_level: next
        }, {
            entity_id: cfg.haEntity
        });
        haVolumeShown();
    }

    function cycle(): void {
        if (modes.length === 0)
            return;
        index = (index + 1) % modes.length;
        const info = modeInfo[mode];
        toast(info.name, info.icon);
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

    // Home Assistant reported a volume: it's the truth again, unless we're
    // still waiting for ours to land
    onHaStateChanged: {
        if (!haPending)
            haVolume = haState?.attributes?.volume_level ?? 0;
    }

    onHaWantedChanged: {
        if (haWanted)
            HomeAssistant.watch("surface-dial", haInstance, [cfg.haEntity]);
        else
            HomeAssistant.unwatch("surface-dial", haInstance);
    }

    Component.onCompleted: {
        if (haWanted)
            HomeAssistant.watch("surface-dial", haInstance, [cfg.haEntity]);
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
            root.haVolume = root.haState?.attributes?.volume_level ?? root.haVolume;
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
