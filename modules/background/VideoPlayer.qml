pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config

// Plays a video wallpaper on one screen with mpvpaper, on the background layer
// beneath this shell's background surface (which turns transparent while a
// video shows). mpv is driven over its IPC socket: `playing` turns true once
// frames are actually on screen, and `paused` is applied live.
Scope {
    id: root

    required property string screenName
    property string video
    property real startTime
    property bool paused

    readonly property bool active: proc.running
    property bool playing

    // A fresh socket per start, so a still-exiting (or killed) mpv's socket is
    // never mistaken for the new one, even across shell reloads.
    property string generation
    readonly property string socketPath: `${Quickshell.env("XDG_RUNTIME_DIR")}/caelestia/mpvpaper-${screenName}-${generation}.sock`
    property bool restartPending
    // Socket.connected stays true after a failed connect, so a reply from mpv
    // is the only proof the IPC link is up.
    property bool linked
    property bool startPaused // captured per start so pause changes don't touch the command

    function send(command: var): void {
        socket.write(JSON.stringify({
            command
        }) + "\n");
        socket.flush();
    }

    function start(): void {
        restartPending = false;
        if (!video)
            return;
        generation = Date.now().toString(36);
        startPaused = paused;
        proc.running = true;
        connectTimer.restart();
    }

    onVideoChanged: {
        playing = false;
        linked = false;
        socket.connected = false;
        if (proc.running) {
            restartPending = true; // start() runs once the old mpvpaper has exited
            proc.signal(9); // mpvpaper catches SIGTERM without exiting (seen while paused)
        } else {
            start();
        }
    }

    Component.onCompleted: start()

    onPausedChanged: send(["set_property", "pause", paused])

    Process {
        id: proc

        command: {
            const cfg = GlobalConfig.forScreen(root.screenName).background.video;
            const opts = ["no-audio", "loop", "panscan=1.0", "vd-lavc-dr=yes", `hwdec=${cfg.hwdec}`, `start=${root.startTime}`, `input-ipc-server=${root.socketPath}`, `pause=${root.startPaused ? "yes" : "no"}`];
            if (cfg.mpvOptions)
                opts.push(cfg.mpvOptions);
            // $1 socket, $2 mpv options, $3 screen, $4 video. Stop any mpvpaper this
            // shell left on the screen (matched by our socket name, so other apps'
            // mpvpaper is untouched), and tie the new one to the shell's lifetime
            // with a parent-death signal so a killed or crashed shell can't orphan it.
            // SIGKILL throughout: mpvpaper catches SIGTERM and can carry on running.
            return ["sh", "-c", `mkdir -p "$(dirname "$1")"
for p in $(pgrep -x mpvpaper); do
    tr '\\0' '\\n' < /proc/$p/cmdline 2>/dev/null | grep -q -- "/caelestia/mpvpaper-$3-" && kill -KILL "$p"
done
shift
exec setpriv --pdeathsig KILL mpvpaper -o "$@"`, "sh", root.socketPath, opts.join(" "), root.screenName, root.video];
        }

        onExited: (code, status) => {
            root.playing = false;
            root.linked = false;
            socket.connected = false;
            if (root.restartPending)
                root.start();
            else if (root.video)
                console.warn(`VideoPlayer: mpvpaper on ${root.screenName} exited (${code})`);
        }
    }

    // mpv creates the socket shortly after starting; retry until it's there.
    Timer {
        id: connectTimer

        interval: 500
        repeat: true
        running: false
        onTriggered: {
            if (!proc.running || root.linked) {
                stop();
                return;
            }
            socket.connected = false;
            socket.connected = true;
            root.send(["observe_property", 1, "playback-time"]);
            root.send(["set_property", "pause", root.paused]);
        }
    }

    Socket {
        id: socket

        path: root.socketPath

        parser: SplitParser {
            onRead: line => {
                let msg;
                try {
                    msg = JSON.parse(line);
                } catch (e) {
                    return;
                }
                root.linked = true;
                if (msg.event === "property-change" && msg.name === "playback-time" && msg.data !== null && msg.data !== undefined)
                    root.playing = true;
            }
        }
    }
}
