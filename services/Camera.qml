pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.utils

// The webcam, through caelestia-camerad (extras/camerad): who's using it, its
// controls, and one-off presence/light/snapshot readings and gestures. The
// daemon reads frames through PipeWire only while something here needs them.
Singleton {
    id: root

    readonly property string daemonPath: GlobalConfig.camera.daemon || `${Paths.libdir}/caelestia-camerad`
    readonly property bool running: proc.running && ready
    property bool ready
    property string error

    // [{ pid, name, via: "pipewire" | "direct", self, shell }]
    property var users: []
    // Apps other than our own daemon using the camera right now
    readonly property var others: users.filter(u => !u.self)
    readonly property bool inUse: others.length > 0
    readonly property bool capturing: users.some(u => u.self)

    property var controls: []
    // [{ name, values: { control key: value } }], kept in camera-presets.json
    property var presets: []
    property string gesturesState: "off" // off, running or paused (another app has the camera)
    property var lastLight: null
    // The gesture tutorial: while it runs, gestures stream with live hand feedback
    property bool tutorial
    property bool tutorialDone
    // The camera panel's mirror needs the device to itself: gestures pause meanwhile
    property bool mirror
    // { pose: open | thumbs_up | thumbs_down | other, x, y } or null, during the tutorial
    property var hand: null
    property var lastPresence: null

    property var _waiting: ({
            presence: [],
            light: [],
            snapshot: []
        })

    signal gesture(name: string)
    // Something (the bar popout, Nexus) wants the camera panel open
    signal openPanelRequested
    signal tutorialRequested
    signal steppedAside(seconds: int)

    function send(obj: var): void {
        if (proc.running)
            proc.write(JSON.stringify(obj) + "\n");
    }

    // Each calls back with the daemon's reply: { ok, reason?, ... }
    function presence(cb: var): void {
        _queue("presence", cb);
        send({
            cmd: "presence"
        });
    }

    function light(cb: var): void {
        _queue("light", cb);
        send({
            cmd: "light"
        });
    }

    function snapshot(path: string, cb: var): void {
        _queue("snapshot", cb);
        send({
            cmd: "snapshot",
            path: path
        });
    }

    // Gestures run while enabled or while the tutorial is open (with feedback)
    function syncGestures(): void {
        send({
            cmd: "gestures",
            on: (GlobalConfig.camera.gestures.enabled || tutorial) && !mirror,
            feedback: tutorial
        });
    }

    // Turning gestures on the first time goes through the tutorial instead
    function setGesturesEnabled(on: bool): void {
        if (on && !tutorialDone)
            tutorial = true;
        else
            GlobalConfig.camera.gestures.enabled = on;
    }

    function finishTutorial(): void {
        tutorial = false;
        tutorialDone = true;
        stateFile.setText(JSON.stringify({
            tutorialDone: true
        }));
    }

    function refreshControls(): void {
        send({
            cmd: "controls"
        });
    }

    function setControl(key: string, value: var): void {
        send({
            cmd: "set",
            name: key,
            value: value
        });
    }

    // Saves the camera's current settings under a name (replacing one of that name)
    function savePreset(name: string): void {
        const values = {};
        for (const c of controls)
            if ((c.type === "int" || c.type === "bool" || c.type === "menu") && c.value !== null && !c.inactive)
                values[c.key] = c.value;
        _savePresets([...presets.filter(p => p.name !== name),
            {
                name: name,
                values: values
            }
        ]);
    }

    function applyPreset(name: string): bool {
        const p = presets.find(p => p.name === name);
        if (!p)
            return false;
        // Automatic modes first, so the manual values they unlock can be set
        const keys = Object.keys(p.values).sort((a, b) => (b.includes("automatic") ? 1 : 0) - (a.includes("automatic") ? 1 : 0));
        for (const k of keys)
            setControl(k, p.values[k]);
        return true;
    }

    function deletePreset(name: string): void {
        _savePresets(presets.filter(p => p.name !== name));
    }

    function _savePresets(next: var): void {
        presets = next;
        presetsFile.setText(JSON.stringify(next, null, 4));
    }

    function _queue(kind: string, cb: var): void {
        if (!proc.running) {
            cb?.({
                ok: false,
                reason: "camera daemon not running"
            });
            return;
        }
        _waiting[kind].push(cb ?? null);
    }

    function _reply(kind: string, msg: var): void {
        const cb = _waiting[kind].shift();
        cb?.(msg);
    }

    function _handle(line: string): void {
        let msg;
        try {
            msg = JSON.parse(line);
        } catch (e) {
            return;
        }
        switch (msg.event) {
        case "ready":
            ready = true;
            error = "";
            syncGestures();
            break;
        case "users":
            users = msg.users ?? [];
            break;
        case "status":
            gesturesState = msg.gestures;
            break;
        case "controls":
            controls = msg.controls ?? [];
            break;
        case "set":
            refreshControls();
            break;
        case "presence":
            if (msg.ok)
                lastPresence = msg;
            _reply("presence", msg);
            break;
        case "light":
            if (msg.ok)
                lastLight = msg;
            _reply("light", msg);
            break;
        case "snapshot":
            _reply("snapshot", msg);
            break;
        case "gesture":
            gesture(msg.name);
            break;
        case "hand":
            hand = msg.hand;
            break;
        case "stepped_aside":
            steppedAside(msg.seconds);
            break;
        case "error":
            error = msg.message;
            console.warn("camerad:", msg.message);
            break;
        }
    }

    onTutorialChanged: {
        hand = null;
        syncGestures();
    }
    onMirrorChanged: syncGestures()

    Process {
        id: proc

        running: GlobalConfig.camera.enabled
        command: [root.daemonPath, "--device", GlobalConfig.camera.device]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => root._handle(line)
        }
        stderr: SplitParser {
            onRead: line => console.warn("camerad:", line)
        }
        onExited: code => {
            root.ready = false;
            root.users = [];
            for (const kind of ["presence", "light", "snapshot"])
                while (root._waiting[kind].length > 0)
                    root._reply(kind, {
                        ok: false,
                        reason: "camera daemon exited"
                    });
            if (GlobalConfig.camera.enabled) {
                root.error = `caelestia-camerad exited (${code})`;
                restart.restart();
            }
        }
    }

    FileView {
        id: stateFile

        path: `${Paths.state}/camera-state.json`
        printErrors: false
        onLoaded: {
            try {
                root.tutorialDone = JSON.parse(text()).tutorialDone ?? false;
            } catch (e) {}
        }
    }

    FileView {
        id: presetsFile

        path: `${Paths.state}/camera-presets.json`
        printErrors: false
        onLoaded: {
            try {
                root.presets = JSON.parse(text());
            } catch (e) {
                root.presets = [];
            }
        }
    }

    // Try again after a crash or a missing ONNX Runtime, without spinning
    Timer {
        id: restart

        interval: 15000
        onTriggered: proc.running = GlobalConfig.camera.enabled
    }

    Connections {
        function onEnabledChanged(): void {
            root.syncGestures();
        }

        target: GlobalConfig.camera.gestures
    }
}
