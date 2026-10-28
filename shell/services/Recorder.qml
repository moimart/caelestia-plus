pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

Singleton {
    id: root

    readonly property alias running: props.running
    readonly property alias paused: props.paused
    readonly property alias elapsed: props.elapsed
    property int refCount: 0
    property bool needsStart
    property list<string> startArgs
    property bool needsStop
    property bool needsPause

    function start(extraArgs = []): void {
        needsStart = true;
        startArgs = extraArgs;
        checkProc.running = true;
    }

    function stop(): void {
        needsStop = true;
        checkProc.running = true;
    }

    // `caelestia record`, with its output (and the recorder's, which it starts
    // and leaves running) going nowhere. Left on a pipe, gpu-screen-recorder
    // dies of SIGPIPE about a second in, once the shell stops reading it: it
    // logs a line every second.
    function cli(args: list<string>): list<string> {
        return ["sh", "-c", "exec caelestia record \"$@\" > /dev/null 2>&1", "sh", ...args];
    }

    function togglePause(): void {
        needsPause = true;
        checkProc.running = true;
    }

    PersistentProperties {
        id: props

        property bool running: false
        property bool paused: false
        property real elapsed: 0 // Might get too large for int

        reloadableId: "recorder"
    }

    Process {
        id: checkProc

        running: true
        command: ["pidof", "gpu-screen-recorder"]
        onExited: code => {
            const running = code === 0;

            if (running && root.needsStop) {
                commandProc.exec(root.cli([]));
                props.running = false;
                props.paused = false;
            } else if (running && root.needsPause) {
                commandProc.exec(root.cli(["-p"]));
                props.paused = !props.paused;
            } else if (!running && root.needsStart) {
                commandProc.exec(root.cli(root.startArgs));
                props.running = true;
                props.paused = false;
                props.elapsed = 0;
            } else if (running !== props.running && !commandProc.running) {
                // The recording was started/stopped outside the shell (e.g. via
                // keybind), or our command finished without reaching the optimistic state
                props.running = running;
                props.paused = false;
                props.elapsed = 0;
            }

            root.needsStart = false;
            root.needsStop = false;
            root.needsPause = false;
        }
    }

    Process {
        id: commandProc

        // The command owns the transition: `caelestia record` blocks on slurp for
        // region captures, and waits for the recorder to finalise the file when
        // stopping. Reconcile once it has actually finished.
        onExited: checkProc.running = true
    }

    // Only poll while something is showing the state, i.e. the utilities drawer is open
    Timer {
        interval: 1000
        running: root.refCount > 0
        repeat: true
        triggeredOnStart: true

        onTriggered: checkProc.running = true
    }

    Connections {
        function onSecondsChanged(): void {
            props.elapsed++;
        }

        enabled: props.running && !props.paused
        target: Time
    }
}
