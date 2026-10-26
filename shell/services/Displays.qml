pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Caelestia.Config
import qs.services
import qs.utils

// The displays, as Hyprland sees them, and changes to them: resolution,
// refresh rate, scale, rotation, VRR, mirroring, arrangement, on or off.
//
// Changes apply at once (hl.monitor). Ones that can leave a screen black wait
// to be kept, and undo themselves after `confirmSeconds`, like macOS. Kept
// changes are saved to displays.json, and to displays.lua, which Hyprland
// loads after the host profile: only what you changed, so the rest of a rule
// (10-bit colour, HDR, a host's own setup) stays as the config has it.
Singleton {
    id: root

    // hyprctl monitors all -j, disabled ones included
    property var monitors: []
    // What Settings changed, per output: { mode, position, scale, transform, vrr, mirror, disabled }
    property var saved: ({})
    // A change waiting to be kept: { name, before, after }
    property var pending: null
    property int countdown: 0
    property bool refreshAgain
    property bool reloadAfterSave

    readonly property int confirmSeconds: 15
    readonly property string jsonPath: `${Paths.config}/displays.json`
    readonly property string luaPath: `${Paths.config}/displays.lua`

    // Usual scale factors; each display only offers the ones that divide its
    // resolution into whole pixels, which Hyprland insists on
    readonly property list<real> scales: [1, 1.25, 1.333333, 1.5, 1.6, 1.666667, 1.75, 2, 2.25, 2.5, 3]

    function monitor(name: string): var {
        return monitors.find(m => m.name === name) ?? null;
    }

    // [{ width, height, rate, mode }] from "7680x2160@120.00Hz", best first
    function modes(m: var): var {
        const out = [];
        for (const s of m?.availableModes ?? []) {
            const r = /^(\d+)x(\d+)@([\d.]+)Hz$/.exec(s);
            if (r)
                out.push({
                    width: +r[1],
                    height: +r[2],
                    rate: +r[3],
                    mode: `${r[1]}x${r[2]}@${r[3]}`
                });
        }
        return out.sort((a, b) => b.width * b.height - a.width * a.height || b.rate - a.rate);
    }

    function resolutions(m: var): var {
        const seen = new Set();
        return modes(m).filter(x => {
            const key = `${x.width}x${x.height}`;
            if (seen.has(key))
                return false;
            seen.add(key);
            return true;
        });
    }

    function rates(m: var, width: int, height: int): var {
        return modes(m).filter(x => x.width === width && x.height === height);
    }

    // The mode it runs now, matched against its list (refreshRate is measured)
    function currentMode(m: var): var {
        const same = rates(m, m?.width ?? 0, m?.height ?? 0);
        let best = null;
        for (const x of same)
            if (!best || Math.abs(x.rate - m.refreshRate) < Math.abs(best.rate - m.refreshRate))
                best = x;
        return best;
    }

    function scalesFor(width: int, height: int): var {
        return scales.filter(s => {
            const w = width / s, h = height / s;
            return Math.abs(w - Math.round(w)) < 0.01 && Math.abs(h - Math.round(h)) < 0.01;
        });
    }

    // Its size on the desktop, after scale and rotation
    function logicalSize(m: var): var {
        const w = Math.round(m.width / m.scale), h = Math.round(m.height / m.scale);
        return m.transform % 2 === 1 ? Qt.size(h, w) : Qt.size(w, h);
    }

    // A display's settings now, as hl.monitor() fields
    function currentValues(m: var, keys: var): var {
        const now = {
            mode: currentMode(m)?.mode ?? `${m.width}x${m.height}@${m.refreshRate.toFixed(2)}`,
            position: `${m.x}x${m.y}`,
            scale: m.scale,
            transform: m.transform,
            bitdepth: /2101010/.test(m.currentFormat ?? "") ? 10 : 8,
            cm: m.colorManagementPreset || "srgb",
            vrr: m.vrr ? 1 : 0,
            mirror: m.mirrorOf && m.mirrorOf !== "none" ? m.mirrorOf : "",
            disabled: !!m.disabled
        };
        const out = {};
        for (const k of keys)
            out[k] = now[k];
        return out;
    }

    // The rule saved for a display: complete for its mode, position, scale
    // and rotation (and 10-bit or HDR colour, if it has them), because a
    // display with no rule of its own in the config gets a new one from
    // scratch, and a partial rule would lose its mode. Other fields in the
    // config's rule (VRR, HDR brightness...) stay as they are.
    function baseSpec(m: var): var {
        if (!m.width || m.disabled)
            return {};
        const keys = ["mode", "position", "scale", "transform"];
        if (/2101010/.test(m.currentFormat ?? ""))
            keys.push("bitdepth");
        if (m.colorManagementPreset && m.colorManagementPreset !== "srgb")
            keys.push("cm");
        return currentValues(m, keys);
    }

    // True if the change can leave a screen unusable, so it waits to be kept
    function risky(fields: var): bool {
        return ["mode", "scale", "transform", "mirror", "disabled"].some(k => k in fields);
    }

    function change(name: string, fields: var): void {
        const m = monitor(name);
        if (!m)
            return;
        if (Object.keys(fields).length === 1 && "position" in fields) {
            arrange(name, fields.position);
            return;
        }
        if (pending)
            keep();
        const full = Object.assign(baseSpec(m), fields);
        const before = currentValues(m, Object.keys(full));
        applyLive(name, full);
        if (risky(fields)) {
            pending = {
                name: name,
                before: before,
                after: full
            };
            countdown = confirmSeconds;
            countdownTimer.restart();
        } else {
            commit(name, full);
        }
    }

    // Moves a display, and saves where every display is, like macOS: what
    // the arrangement shows is what you get, and Hyprland's automatic
    // placement can't shift another display afterwards
    function arrange(name: string, position: string): void {
        if (pending)
            keep();
        const next = Object.assign({}, saved);
        for (const m of monitors) {
            if (m.disabled || (m.mirrorOf && m.mirrorOf !== "none"))
                continue;
            const spec = Object.assign({}, next[m.name], baseSpec(m));
            if (m.name === name)
                spec.position = position;
            next[m.name] = spec;
        }
        // The others first, where they are (no change, but no longer "auto"),
        // then the one that moved
        for (const [n, spec] of Object.entries(next))
            if (n !== name && monitor(n))
                applyLive(n, spec);
        if (next[name])
            applyLive(name, next[name]);
        saved = next;
        save();
    }

    function keep(): void {
        if (!pending)
            return;
        countdownTimer.stop();
        commit(pending.name, pending.after);
        pending = null;
    }

    function revert(): void {
        if (!pending)
            return;
        countdownTimer.stop();
        applyLive(pending.name, pending.before);
        pending = null;
    }

    // Forgets what Settings changed on this display, back to the config's rule
    function reset(name: string): void {
        const next = Object.assign({}, saved);
        delete next[name];
        saved = next;
        // Hyprland reloads once the new displays.lua is on disk, not before
        reloadAfterSave = true;
        save();
    }

    // The shell (bar, wallpaper, widgets) on a display or not: its per-display
    // settings file, on top of the host profile's. The last one keeps it.
    function hasShell(name: string): bool {
        return GlobalConfig.forScreen(name).enabled;
    }

    function setShell(name: string, on: bool): void {
        if (!on && monitors.filter(m => m.name !== name && hasShell(m.name)).length === 0)
            return;
        GlobalConfig.forScreen(name).enabled = on;
    }

    function isCustomised(name: string): bool {
        return name in saved;
    }

    function luaSpec(name: string, fields: var): string {
        const parts = [`output = ${JSON.stringify(name)}`];
        for (const [k, v] of Object.entries(fields))
            parts.push(`${k} = ${typeof v === "string" ? JSON.stringify(v) : v}`);
        return `hl.monitor({ ${parts.join(", ")} })`;
    }

    function applyLive(name: string, fields: var): void {
        Hypr.extras.message(`eval ${luaSpec(name, fields)}`);
        refreshTimer.restart();
    }

    function commit(name: string, fields: var): void {
        const next = Object.assign({}, saved);
        next[name] = Object.assign({}, next[name], fields);
        saved = next;
        save();
    }

    function save(): void {
        jsonFile.setText(JSON.stringify(saved, null, 4) + "\n");
        const lines = ["-- Written by the shell (Settings → Displays) from displays.json; changes", "-- here are overwritten. Loaded after the host profile: the displays you", "-- changed in Settings, with their mode, position, scale and rotation.", ""];
        for (const [name, fields] of Object.entries(saved))
            lines.push(luaSpec(name, fields));
        luaFile.setText(lines.join("\n") + "\n");
    }

    // A refresh asked for while one runs (its answer may predate the change)
    // runs again afterwards
    function refresh(): void {
        if (proc.running)
            refreshAgain = true;
        else
            proc.running = true;
    }

    Component.onCompleted: refresh()

    Process {
        id: proc

        command: ["hyprctl", "monitors", "all", "-j"]
        onExited: {
            if (root.refreshAgain) {
                root.refreshAgain = false;
                refreshTimer.restart();
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.monitors = JSON.parse(text).sort((a, b) => a.x - b.x || a.y - b.y);
                } catch (e) {}
            }
        }
    }

    // Hyprland's own events: plugged in, unplugged, layout changed, reloaded
    Connections {
        function onRawEvent(event: HyprlandEvent): void {
            const n = event.name;
            if (n.includes("mon") || n === "configreloaded")
                refreshTimer.restart();
        }

        target: Hyprland
    }

    Timer {
        id: refreshTimer

        interval: 300
        onTriggered: root.refresh()
    }

    Timer {
        id: countdownTimer

        interval: 1000
        repeat: true
        onTriggered: {
            root.countdown--;
            if (root.countdown <= 0)
                root.revert();
        }
    }

    IpcHandler {
        // The displays as JSON: what Hyprland reports, plus what Settings saved
        function list(): string {
            return JSON.stringify(root.monitors.map(m => ({
                        name: m.name,
                        description: m.description,
                        mode: root.currentMode(m)?.mode ?? null,
                        modes: root.modes(m).map(x => x.mode),
                        position: `${m.x}x${m.y}`,
                        scale: m.scale,
                        transform: m.transform,
                        vrr: m.vrr,
                        mirror: m.mirrorOf && m.mirrorOf !== "none" ? m.mirrorOf : "",
                        disabled: !!m.disabled,
                        saved: root.saved[m.name] ?? null
                    })));
        }

        // Changes a display, as Settings does: fields as JSON, e.g.
        // {"mode": "3840x2160@60.00"}. Risky changes wait for keep(), and undo
        // themselves after the countdown.
        function set(name: string, fields: string): string {
            if (!root.monitor(name))
                return `no display ${name}`;
            try {
                root.change(name, JSON.parse(fields));
            } catch (e) {
                return `bad JSON: ${e}`;
            }
            return root.pending ? `waiting to be kept (${root.confirmSeconds} s)` : "saved";
        }

        function keep(): void {
            root.keep();
        }

        function revert(): void {
            root.revert();
        }

        function pending(): string {
            return root.pending ? JSON.stringify(Object.assign({
                countdown: root.countdown
            }, root.pending)) : "";
        }

        function reset(name: string): void {
            root.reset(name);
        }

        function setShell(name: string, on: bool): void {
            root.setShell(name, on);
        }

        target: "displays"
    }

    FileView {
        id: jsonFile

        path: root.jsonPath
        printErrors: false
        onLoaded: {
            try {
                root.saved = JSON.parse(text()) ?? {};
            } catch (e) {
                root.saved = {};
            }
        }
    }

    FileView {
        id: luaFile

        path: root.luaPath
        printErrors: false
        onSaved: {
            if (root.reloadAfterSave) {
                root.reloadAfterSave = false;
                Quickshell.execDetached(["hyprctl", "reload"]);
            }
        }
    }
}
