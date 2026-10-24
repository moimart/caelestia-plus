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
    property bool loaded
    // Placing and resizing widgets (modules/widgets shows the editor)
    property bool editing

    readonly property bool needsCursor: GlobalConfig.widgets.enabled && instances.some(i => pluginFor(i.type)?.needsCursor)

    function pluginFor(type: string): var {
        return plugins.find(p => p.id === type) ?? null;
    }

    function instancesOn(screen: string): var {
        return instances.filter(i => i.screen === screen);
    }

    function add(type: string, screen: ShellScreen): void {
        const p = pluginFor(type);
        if (!p || !screen)
            return;
        const [w, h] = p.defaultSize;
        // Centre it, nudged so repeated adds don't stack exactly
        const n = instancesOn(screen.name).length % 6;
        save([...instances,
            {
                uid: `${type}-${Date.now().toString(36)}`,
                type: type,
                screen: screen.name,
                x: Math.round((screen.width - w) / 2 + n * 32),
                y: Math.round((screen.height - h) / 2 + n * 32),
                width: w,
                height: h,
                settings: {}
            }
        ]);
    }

    function remove(uid: string): void {
        save(instances.filter(i => i.uid !== uid));
    }

    function update(uid: string, changes: var): void {
        save(instances.map(i => i.uid === uid ? Object.assign({}, i, changes) : i));
    }

    function save(next: var): void {
        instances = next;
        stateFile.setText(JSON.stringify(next, null, 4));
    }

    function rescan(): void {
        scanProc.running = true;
    }

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
                            needsCursor: m.needsCursor ?? false
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
