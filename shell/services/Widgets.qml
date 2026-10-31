pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config
import Caelestia.State
import qs.services
import qs.utils

// Desktop widgets: plugins found on disk, and the widgets placed on each
// monitor. A widget plugin is a folder holding widget.json (its manifest) and
// the QML file it names; built-in ones ship in modules/widgets/builtin, your
// own go in ~/.config/caelestia/plugins/widgets. Placed widgets are kept in
// ~/.local/state/caelestia/widgets.json.
Singleton {
    id: root

    readonly property string builtinDir: Quickshell.shellPath("modules/widgets/builtin")
    readonly property string userDir: `${Paths.config}/plugins/widgets`
    readonly property string statePath: `${Paths.state}/widgets.json`

    // [{ id, name, description, icon, author, version, dir, url, builtin,
    //    defaultSize: [w, h], minSize: [w, h], keepAspect, needsCursor }]
    property var plugins: []
    // [{ uid, type, screen, x, y, width, height, settings }] in screen-local logical px
    property var instances: []
    // The placed widget Settings → Plugins is editing (its uid)
    property string settingsUid
    property bool loaded
    // Placing and resizing widgets (modules/widgets shows the editor)
    property bool editing

    readonly property bool needsCursor: GlobalConfig.widgets.enabled && instances.some(i => pluginFor(i.type)?.needsCursor)

    // Settings asked for on a widget (modules/widgets/WidgetsEditor opens it)
    signal settingsRequested(uid: string)

    function pluginFor(type: string): var {
        return plugins.find(p => p.id === type) ?? null;
    }

    function instancesOn(screen: string): var {
        return instances.filter(i => i.screen === screen);
    }

    // A widget that shows nothing until it's told what (a Home Assistant
    // entity or card): Settings opens on it as soon as it's placed
    function needsSetup(type: string): bool {
        return (pluginFor(type)?.schema ?? []).some(f => f.type === "haEntity" || f.type === "haCard");
    }

    // Opens Settings on a placed widget's page (closing the editor, which would
    // cover the window)
    function openSettings(uid: string): void {
        settingsUid = uid;
        editing = false;
        settingsRequested(uid);
    }

    // Places a widget; its uid, or "" if it couldn't be
    function add(type: string, screen: ShellScreen): string {
        const p = pluginFor(type);
        if (!p || !screen)
            return "";
        const [w, h] = p.defaultSize;
        // Centre it, nudged so repeated adds don't stack exactly
        const n = instancesOn(screen.name).length % 6;
        const uid = `${type}-${Date.now().toString(36)}`;
        save([...instances,
            {
                uid: uid,
                type: type,
                screen: screen.name,
                x: Math.round((screen.width - w) / 2 + n * 32),
                y: Math.round((screen.height - h) / 2 + n * 32),
                width: w,
                height: h,
                settings: {}
            }
        ]);
        return uid;
    }

    function remove(uid: string): void {
        save(instances.filter(i => i.uid !== uid));
    }

    function update(uid: string, changes: var): void {
        save(instances.map(i => i.uid === uid ? Object.assign({}, i, changes) : i));
    }

    // Several of a placed widget's settings at once: { key: value }
    function setSettings(uid: string, changes: var): void {
        const inst = instances.find(i => i.uid === uid);
        if (inst)
            update(uid, {
                settings: Object.assign({}, inst.settings, changes)
            });
    }

    // One of a placed widget's settings
    function setSetting(uid: string, key: string, value: var): void {
        const inst = instances.find(i => i.uid === uid);
        if (!inst)
            return;
        const settings = Object.assign({}, inst.settings);
        if (value === undefined || value === "")
            delete settings[key];
        else
            settings[key] = value;
        update(uid, {
            settings: settings
        });
    }

    function save(next: var): void {
        instances = next;
        stateFile.setText(JSON.stringify(next, null, 4));
    }

    // The clock used to be built into the background (background.desktopClock
    // in shell.json); it's the clock widget now. Where the old one is on, a
    // clock widget takes its place, size and settings, and the old setting
    // goes off, so this happens once. New installs get theirs the same way.
    function migrateClock(): void {
        const plugin = pluginFor("clock");
        if (!loaded || !plugin)
            return;
        const next = instances.slice();
        let found = false;
        for (const screen of Screens.screens) {
            const old = GlobalConfig.forScreen(screen.name).background.desktopClock;
            if (!old.enabled)
                continue;
            found = true;
            if (next.some(i => i.type === "clock" && i.screen === screen.name))
                continue;
            const w = Math.round(plugin.defaultSize[0] * old.scale);
            const h = Math.round(plugin.defaultSize[1] * old.scale);
            // Where it sat: clear of the bars at the sides, a margin otherwise
            const side = 96;
            const margin = 40;
            const pos = old.position;
            next.push({
                uid: `clock-${Date.now().toString(36)}-${screen.name}`,
                type: "clock",
                screen: screen.name,
                x: Math.round(pos.endsWith("left") ? side : pos.endsWith("right") ? screen.width - w - side : (screen.width - w) / 2),
                y: Math.round(pos.startsWith("top") ? margin : pos.startsWith("bottom") ? screen.height - h - margin : (screen.height - h) / 2),
                width: w,
                height: h,
                settings: {
                    invertColors: old.invertColors,
                    shadow: old.shadow.enabled,
                    background: old.background.enabled,
                    backgroundOpacity: Math.round(old.background.opacity * 100)
                }
            });
        }
        if (!found)
            return;
        save(next);
        GlobalConfig.background.desktopClock.enabled = false;
    }

    function rescan(): void {
        scanProc.running = true;
    }

    onLoadedChanged: Qt.callLater(migrateClock)
    onPluginsChanged: Qt.callLater(migrateClock)

    // Only poll the pointer while a widget that follows it can be seen
    Binding {
        target: Hypr.extras
        property: "trackCursor"
        value: root.needsCursor && !RuntimeState.gameMode
    }

    FileView {
        id: stateFile

        path: root.statePath
        printErrors: false
        onLoaded: {
            try {
                const data = JSON.parse(text());
                root.instances = Array.isArray(data) ? data : [];
            } catch (e) {
                root.instances = [];
            }
            root.loaded = true;
        }
        onLoadFailed: root.loaded = true
    }

    // Every plugin folder with a widget.json, one "dir<TAB>json" line each
    Process {
        id: scanProc

        running: true
        command: ["sh", "-c", `for d in "$1"/*/ "$2"/*/; do [ -f "$d/widget.json" ] && printf '%s\\t%s\\n' "$d" "$(tr -d '\\n' < "$d/widget.json")"; done; true`, "sh", root.builtinDir, root.userDir]
        stdout: StdioCollector {
            onStreamFinished: {
                const found = [];
                for (const line of text.split("\n")) {
                    const tab = line.indexOf("\t");
                    if (tab < 0)
                        continue;
                    const dir = line.slice(0, tab).replace(/\/$/, "");
                    try {
                        const m = JSON.parse(line.slice(tab + 1));
                        if (!m.id || !m.main || found.some(p => p.id === m.id))
                            continue;
                        found.push({
                            id: m.id,
                            name: m.name ?? m.id,
                            description: m.description ?? "",
                            icon: m.icon ?? "widgets",
                            author: m.author ?? "",
                            version: m.version ?? "",
                            dir: dir,
                            url: `file://${dir}/${m.main}`,
                            builtin: dir.startsWith(root.builtinDir),
                            defaultSize: m.defaultSize ?? [240, 160],
                            minSize: m.minSize ?? [64, 64],
                            keepAspect: m.keepAspect ?? false,
                            needsCursor: m.needsCursor ?? false,
                            // [{ key, type, label, ... }]: the form Settings → Plugins shows
                            schema: Array.isArray(m.settings) ? m.settings : []
                        });
                    } catch (e) {
                        console.warn(`Widgets: bad manifest in ${dir}: ${e}`);
                    }
                }
                root.plugins = found;
            }
        }
    }
}
