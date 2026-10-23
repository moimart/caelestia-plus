pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config

// The active Hyprland keybinds, read from the user's Hyprland config by
// assets/hyprbinds.py (which also pairs them with `hyprctl binds`). Loaded on
// first use and re-read whenever Hyprland reloads its config.
Singleton {
    id: root

    property var binds: []
    property var unbound: []
    property var categoryList: []
    property string configFile
    property var files: []
    property bool live
    property string error
    property bool loaded
    property bool pending
    // Whether the shortcuts panel is open (modules/keybinds shows it)
    property bool panelOpen
    readonly property bool loading: proc.running

    readonly property var visibleBinds: {
        const showInternal = GlobalConfig.keybinds.showInternal;
        return binds.filter(b => showInternal || !b.internal);
    }

    // [{ name, icon, binds }] in the order the config defines them
    readonly property var categories: {
        const byName = {};
        for (const b of visibleBinds) {
            if (!byName[b.category])
                byName[b.category] = [];
            byName[b.category].push(b);
        }
        return categoryList.filter(c => byName[c.name]).map(c => ({
                    name: c.name,
                    icon: c.icon,
                    binds: byName[c.name]
                }));
    }

    // The bind that opens the shortcuts panel, if there is one
    readonly property var panelBind: binds.find(b => /caelestia:keybinds|keybinds toggle/.test(b.detail)) ?? null

    function reload(): void {
        if (proc.running)
            pending = true;
        else
            proc.running = true;
    }

    function ensureLoaded(): void {
        if (!loaded && !proc.running)
            reload();
    }

    function filter(query: string, owner: string): var {
        const words = query.toLowerCase().split(/\s+/).filter(w => w);
        return categories.map(c => ({
                    name: c.name,
                    icon: c.icon,
                    binds: c.binds.filter(b => (!owner || b.owner === owner) && words.every(w => b.search.includes(w)))
                })).filter(c => c.binds.length > 0);
    }

    function parse(text: string): void {
        let data;
        try {
            data = JSON.parse(text);
        } catch (e) {
            error = `Couldn't read the keybinds (${e})`;
            return;
        }
        error = data.error ?? "";
        binds = data.binds ?? [];
        unbound = data.unbound ?? [];
        categoryList = data.categories ?? [];
        configFile = data.config ?? "";
        files = data.files ?? [];
        live = data.live ?? false;
        loaded = true;
    }

    Process {
        id: proc

        command: {
            const cmd = ["python3", "-I", Quickshell.shellPath("assets/hyprbinds.py")];
            const path = GlobalConfig.keybinds.configPath;
            return path ? [...cmd, "--config", path] : cmd;
        }
        stdout: StdioCollector {
            onStreamFinished: root.parse(text)
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim())
                    console.warn("hyprbinds.py:", text.trim());
            }
        }
        onExited: code => {
            if (code !== 0)
                root.error = `hyprbinds.py exited with code ${code}`;
            if (root.pending) {
                root.pending = false;
                running = true;
            }
        }
    }

    Connections {
        function onConfigReloaded(): void {
            if (root.loaded)
                root.reload();
        }

        target: Hypr
    }

    Connections {
        function onConfigPathChanged(): void {
            if (root.loaded)
                root.reload();
        }

        target: GlobalConfig.keybinds
    }
}
