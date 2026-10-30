pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config

// Home Assistant custom cards (HACS and the like), which only a browser can
// draw: assets/ha-cards/host.py draws them in one headless Chromium and hands
// back pictures. It starts with the first such card and stops a while after
// the last one goes. components/ha/HaWebCard shows one.
Singleton {
    id: root

    // id -> { path, seq } of the latest picture, { status, error }
    property var frames: ({})
    property var states: ({})
    // What's open, to open again if the helper restarts: id -> request
    property var open: ({})

    function send(req: var): void {
        if (!proc.running)
            proc.running = true;
        proc.write(JSON.stringify(req) + "\n");
    }

    // The colours cards draw with: HA's theme variables, from the scheme
    function theme(): var {
        const p = Colours.palette;
        return {
            "--primary-text-color": `${p.m3onSurface}`,
            "--secondary-text-color": `${p.m3onSurfaceVariant}`,
            "--disabled-text-color": `${p.m3outline}`,
            "--text-primary-color": `${p.m3onPrimary}`,
            "--primary-color": `${p.m3primary}`,
            "--accent-color": `${p.m3tertiary}`,
            "--divider-color": `${p.m3outlineVariant}`,
            "--primary-background-color": `${p.m3surface}`,
            "--secondary-background-color": `${p.m3surfaceContainer}`,
            "--state-icon-color": `${p.m3onSurfaceVariant}`,
            "--state-active-color": `${p.m3primary}`,
            "--error-color": `${p.m3error}`,
            "--paper-font-body1_-_font-family": `"${Tokens.font.body.medium.family}", sans-serif`
        };
    }

    function openCard(id: string, instanceId: string, card: var, width: real, height: real, scale: real, paused: bool, animate: bool): void {
        const inst = HomeAssistant.instances.find(i => i.id === (instanceId || HomeAssistant.defaultId));
        if (!inst)
            return;
        const req = {
            op: "open",
            id: id,
            instance: {
                id: inst.id,
                url: inst.url,
                tokenFile: inst.tokenFile
            },
            card: card,
            width: Math.round(width),
            height: Math.round(height),
            scale: scale,
            paused: paused,
            animate: animate,
            theme: theme()
        };
        const next = Object.assign({}, open);
        next[id] = req;
        open = next;
        idle.stop();
        send(req);
    }

    function resize(id: string, width: real, height: real, scale: real): void {
        if (!open[id])
            return;
        open[id].width = Math.round(width);
        open[id].height = Math.round(height);
        open[id].scale = scale;
        send({
            op: "resize",
            id: id,
            width: Math.round(width),
            height: Math.round(height),
            scale: scale
        });
    }

    function setPaused(id: string, paused: bool): void {
        if (!open[id])
            return;
        open[id].paused = paused;
        send({
            op: paused ? "pause" : "resume",
            id: id
        });
    }

    function closeCard(id: string): void {
        if (!open[id])
            return;
        const next = Object.assign({}, open);
        delete next[id];
        open = next;
        if (proc.running)
            send({
                op: "close",
                id: id
            });
        if (Object.keys(next).length === 0)
            idle.restart();
    }

    Process {
        id: proc

        command: ["python3", `${Quickshell.shellDir}/assets/ha-cards/host.py`]
        stdinEnabled: true

        stdout: SplitParser {
            onRead: line => {
                let msg;
                try {
                    msg = JSON.parse(line);
                } catch (e) {
                    return;
                }
                if (msg.frame) {
                    const next = Object.assign({}, root.frames);
                    next[msg.id] = {
                        path: msg.frame,
                        seq: msg.seq
                    };
                    root.frames = next;
                } else if (msg.status) {
                    const next = Object.assign({}, root.states);
                    next[msg.id] = {
                        status: msg.status,
                        error: msg.error ?? ""
                    };
                    root.states = next;
                }
            }
        }
        stderr: SplitParser {
            onRead: line => console.warn(line)
        }
        // It went away with cards still showing: again, with them
        onExited: code => {
            if (Object.keys(root.open).length > 0)
                restart.start();
        }
    }

    Timer {
        id: restart

        interval: 5000
        onTriggered: {
            for (const req of Object.values(root.open))
                root.send(req);
        }
    }

    // Chromium only runs while there are cards: gone a minute after the last
    Timer {
        id: idle

        interval: 60000
        onTriggered: if (Object.keys(root.open).length === 0)
            proc.running = false
    }
}
