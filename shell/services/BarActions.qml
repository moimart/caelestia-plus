pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config
import Caelestia.I18n
import qs.services
import qs.utils

// Actions for the right bar's buttons: built-in ones, and action plugins.
// An action plugin is a folder in ~/.config/caelestia/plugins/actions/ with an
// action.json: { "id", "name", "icon" (a Material Symbols name), optional
// "description", and what it runs: "command" (a list, run in the plugin's
// folder), "shell" (a line for sh -c) or "ipc" (["target", "function", args...],
// the shell's own IPC) }. PLUGINS.md has examples.
Singleton {
    id: root

    readonly property string userDir: `${Paths.config}/plugins/actions`

    // { id, name, icon, description, builtin, run(), active? (the button lights up) }
    readonly property list<var> builtins: [
        {
            id: "screenshot",
            name: Tr.tr("Screenshot"),
            icon: "screenshot_region",
            description: Tr.tr("Pick an area, then edit or save it"),
            run: () => root.ipc("picker", "open")
        },
        {
            id: "screenshotClip",
            name: Tr.tr("Copy a screenshot"),
            icon: "content_paste",
            description: Tr.tr("Pick an area; it goes to the clipboard"),
            run: () => root.ipc("picker", "openClip")
        },
        {
            id: "recordRegion",
            name: Tr.tr("Record an area"),
            icon: "screen_record",
            description: Tr.tr("Pick an area to record; press again to stop"),
            recorder: true,
            run: () => Recorder.running ? Recorder.stop() : Recorder.start(["-r"])
        },
        {
            id: "recordScreen",
            name: Tr.tr("Record the screen"),
            icon: "videocam",
            description: Tr.tr("Record the whole screen; press again to stop"),
            recorder: true,
            run: () => Recorder.running ? Recorder.stop() : Recorder.start()
        },
        {
            id: "recordWithSound",
            name: Tr.tr("Record with sound"),
            icon: "mic",
            description: Tr.tr("Record the screen and its sound; press again to stop"),
            recorder: true,
            run: () => Recorder.running ? Recorder.stop() : Recorder.start(["-s"])
        },
        {
            id: "colourPicker",
            name: Tr.tr("Colour picker"),
            icon: "colorize",
            description: Tr.tr("Pick a colour on screen; its hex goes to the clipboard"),
            run: () => Quickshell.execDetached(["hyprpicker", "-a"])
        },
        {
            id: "launchpad",
            name: Tr.tr("Launchpad"),
            icon: "apps",
            description: Tr.tr("Every app in a grid"),
            run: () => root.ipc("launchpad", "toggle")
        },
        {
            id: "emoji",
            name: Tr.tr("Emoji"),
            icon: "mood",
            description: Tr.tr("The emoji picker"),
            run: () => root.ipc("emoji", "toggle")
        },
        {
            id: "keybinds",
            name: Tr.tr("Keyboard shortcuts"),
            icon: "keyboard",
            description: Tr.tr("The shortcuts panel"),
            run: () => root.ipc("keybinds", "toggle")
        },
        {
            id: "camera",
            name: Tr.tr("Camera"),
            icon: "photo_camera_front",
            description: Tr.tr("The camera panel"),
            run: () => root.ipc("camera", "open")
        },
        {
            id: "lock",
            name: Tr.tr("Lock"),
            icon: "lock",
            description: Tr.tr("Lock the screen"),
            run: () => root.ipc("lock", "lock")
        }
    ]

    // From action plugins, in the same shape
    property list<var> plugins: []

    // Home Assistant shortcuts (Settings → Panels → Right bar): tap the entity
    readonly property list<var> haActions: HomeAssistant.shortcuts.map(sc => {
        const entity = HomeAssistant.entity(sc.instance, sc.entity);
        return {
            id: sc.id,
            name: sc.name || entity?.attributes?.friendly_name || sc.entity,
            icon: sc.icon || HaIcons.iconFor(sc.entity, entity),
            description: Tr.tr("Home Assistant: %1").arg(sc.entity),
            ha: sc,
            run: () => HomeAssistant.activate(sc.instance, sc.entity)
        };
    })

    readonly property list<var> all: [...builtins, ...plugins, ...haActions]

    function find(id: string): var {
        return all.find(a => a.id === id) ?? null;
    }

    function run(id: string): void {
        find(id)?.run();
    }

    // Whether a button should show as on (a recording is running)
    function isActive(action: var): bool {
        if (action?.ha)
            return HaIcons.isOn(HomeAssistant.entity(action.ha.instance, action.ha.entity)?.state ?? "");
        return !!action?.recorder && Recorder.running;
    }

    // The shortcuts' entities, kept live
    function watchShortcuts(): void {
        const byInstance = {};
        for (const sc of HomeAssistant.shortcuts) {
            if (!byInstance[sc.instance])
                byInstance[sc.instance] = [];
            byInstance[sc.instance].push(sc.entity);
        }
        for (const inst of HomeAssistant.instances)
            HomeAssistant.watch("bar-actions", inst.id, byInstance[inst.id] ?? []);
    }

    function ipc(target: string, fn: string, ...args): void {
        Quickshell.execDetached(["qs", "-c", "caelestia", "ipc", "call", target, fn, ...args]);
    }

    function rescan(): void {
        scanProc.running = true;
    }

    IpcHandler {
        // The actions as JSON: [{ id, name, icon, description, plugin, onBar }]
        function list(): string {
            const onBar = GlobalConfig.rightBar.actions;
            return JSON.stringify(root.all.map(a => ({
                        id: a.id,
                        name: a.name,
                        icon: a.icon,
                        description: a.description,
                        plugin: !!a.plugin,
                        onBar: onBar.includes(a.id)
                    })));
        }

        // Runs one, as its button does
        function run(id: string): string {
            const action = root.find(id);
            if (!action)
                return `no action ${id}`;
            action.run();
            return "ok";
        }

        target: "barActions"
    }

    Connections {
        function onShortcutsChanged(): void {
            root.watchShortcuts();
        }

        function onInstancesChanged(): void {
            root.watchShortcuts();
        }

        target: HomeAssistant
    }

    // Every action plugin folder with an action.json, one "dir<TAB>json" line each
    Process {
        id: scanProc

        running: true
        command: ["sh", "-c", `for d in "$1"/*/; do [ -f "$d/action.json" ] && printf '%s\\t%s\\n' "$d" "$(tr -d '\\n' < "$d/action.json")"; done; true`, "sh", root.userDir]
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
                        if (!m.id || root.builtins.some(b => b.id === m.id) || found.some(p => p.id === m.id))
                            continue;
                        let run = null;
                        if (Array.isArray(m.command) && m.command.length > 0)
                            run = () => Quickshell.execDetached({
                                    command: m.command,
                                    workingDirectory: dir
                                });
                        else if (typeof m.shell === "string" && m.shell)
                            run = () => Quickshell.execDetached({
                                    command: ["sh", "-c", m.shell],
                                    workingDirectory: dir
                                });
                        else if (Array.isArray(m.ipc) && m.ipc.length >= 2)
                            run = () => root.ipc(...m.ipc.map(String));
                        if (!run)
                            continue;
                        found.push({
                            id: m.id,
                            name: m.name ?? m.id,
                            icon: m.icon ?? "bolt",
                            description: m.description ?? "",
                            dir: dir,
                            plugin: true,
                            run: run
                        });
                    } catch (e) {
                        console.warn(`BarActions: bad action.json in ${dir}: ${e}`);
                    }
                }
                root.plugins = found;
            }
        }
    }
}
