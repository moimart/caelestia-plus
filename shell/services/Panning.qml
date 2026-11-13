pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

// Panning an app's sound to the left or right.
//
// An app plays as it is (stereo, 5.1, 7.1) while centred. Panned, it plays
// into a one-channel virtual output of its own, which mixes it down to mono.
// Two loopbacks play that mono on the real device: one on its front left,
// one on its front right, each at the pan's gain for that side. (One
// loopback can't: it copies channels by number, so a mono input only ever
// reaches the left.) Centred again, the app goes back to the device and the
// loopbacks go away. They're the shell's processes: if the shell quits,
// PipeWire puts their apps back on the default output.
Singleton {
    id: root

    // Panned streams by object serial: { pan (-1 left .. 1 right), device (node name) }
    property var pans: ({})
    readonly property var serials: Object.keys(pans)
    readonly property string prefix: "caelestia-pan-"
    property bool syncing

    function serialOf(stream: PwNode): string {
        return String(stream?.properties["object.serial"] ?? "");
    }

    function isPanned(stream: PwNode): bool {
        return serialOf(stream) in pans;
    }

    function panOf(stream: PwNode): real {
        return pans[serialOf(stream)]?.pan ?? 0;
    }

    // One of this service's own nodes, which the mixer doesn't list
    function isOwn(node: PwNode): bool {
        return (node?.name ?? "").startsWith(prefix);
    }

    function node(name: string): PwNode {
        return Pipewire.nodes.values.find(n => n.name === name) ?? null;
    }

    // Where a panned stream's loopback plays to
    function deviceOf(stream: PwNode): PwNode {
        const p = pans[serialOf(stream)];
        return p ? node(p.device) : null;
    }

    function setPan(stream: PwNode, pan: real): void {
        const serial = serialOf(stream);
        if (!serial)
            return;
        pan = Math.max(-1, Math.min(1, pan));
        const current = pans[serial];

        if (Math.abs(pan) < 0.05) {
            if (!current)
                return;
            // Back to the device first, so it doesn't fall to the default
            // output in the moment between the loopback going and the move
            Quickshell.execDetached(["pactl", "move-sink-input", serial, current.device]);
            unpanLater.serials.push(serial);
            unpanLater.restart();
            update(serial, {
                pan: 0,
                device: current.device
            });
            return;
        }

        if (current) {
            update(serial, {
                pan: pan,
                device: current.device
            });
        } else {
            // A paused app (Chrome between videos) may be linked to nothing:
            // pan it on the default output, where it'll play
            const device = Audio.streamDevice(stream) ?? Audio.sink;
            if (!device)
                return;
            update(serial, {
                pan: pan,
                device: device.name
            });
        }
        sync();
    }

    // Sends a panned stream's loopback to another device
    function moveTo(stream: PwNode, device: PwNode): void {
        const serial = serialOf(stream);
        if (!pans[serial] || !device?.name)
            return;
        update(serial, {
            pan: pans[serial].pan,
            device: device.name
        });
        for (const side of ["left", "right"]) {
            const outSerial = node(`${prefix}${serial}.${side}`)?.properties["object.serial"];
            if (outSerial)
                Quickshell.execDetached(["pactl", "move-sink-input", String(outSerial), device.name]);
        }
    }

    function update(serial: string, value: var): void {
        const next = Object.assign({}, pans);
        if (value)
            next[serial] = value;
        else
            delete next[serial];
        pans = next;
        if (value)
            ensureLoop(serial, value.device);
        else
            dropLoop(serial);
    }

    // Brings the graph in line: each panned stream in its virtual output, each
    // loopback at its gains; and forgets streams that have gone
    function sync(): void {
        // Forgetting a stream changes pans, which would call this again mid-loop
        if (syncing)
            return;
        syncing = true;
        const nodes = Pipewire.nodes.values;
        for (const serial of serials.slice()) {
            const stream = nodes.find(n => String(n.properties["object.serial"] ?? "") === serial);
            if (!stream) {
                update(serial, null);
                continue;
            }
            const p = pans[serial];
            if (!p || p.pan === 0)
                continue;
            const sink = nodes.find(n => n.name === `${prefix}${serial}`);
            if (sink && Audio.linkedTo(stream) !== sink)
                Quickshell.execDetached(["pactl", "move-sink-input", serial, sink.name]);
            // Full on the side it's panned to, fading on the other
            const gains = {
                left: p.pan > 0 ? 1 - p.pan : 1,
                right: p.pan < 0 ? 1 + p.pan : 1
            };
            for (const side of ["left", "right"]) {
                const audio = nodes.find(n => n.name === `${prefix}${serial}.${side}`)?.audio;
                if (audio && audio.volumes.length === 1 && Math.abs(audio.volumes[0] - gains[side]) > 0.001)
                    audio.volumes = [gains[side]];
            }
        }
        syncing = false;
    }

    function ensureLoop(serial: string, device: string): void {
        for (let i = 0; i < loops.count; i++)
            if (loops.get(i).serial === serial) {
                loops.setProperty(i, "device", device);
                return;
            }
        loops.append({
            serial: serial,
            device: device
        });
    }

    function dropLoop(serial: string): void {
        for (let i = 0; i < loops.count; i++)
            if (loops.get(i).serial === serial) {
                loops.remove(i);
                return;
            }
    }

    onPansChanged: sync()

    Connections {
        function onValuesChanged(): void {
            root.sync();
        }

        target: Pipewire.nodes
    }

    Connections {
        function onValuesChanged(): void {
            root.sync();
        }

        target: Pipewire.linkGroups
    }

    // The loopbacks' playback sides, to set their gains
    PwObjectTracker {
        objects: Pipewire.nodes.values.filter(n => root.isOwn(n))
    }

    Timer {
        id: unpanLater

        property list<string> serials

        interval: 400
        onTriggered: {
            for (const s of serials)
                if (root.pans[s]?.pan === 0)
                    root.update(s, null);
            serials = [];
        }
    }

    // The loopbacks of each panned stream. A ListModel, so adding or removing
    // one stream's leaves the others running
    ListModel {
        id: loops
    }

    Instantiator {
        model: loops

        QtObject {
            id: loop

            required property string serial
            required property string device
            readonly property string name: `${root.prefix}${serial}`
            // Not restored by WirePlumber: a remembered volume would undo the pan
            readonly property string common: "node.description=Panning state.restore-props=false"

            // The virtual output, and its left side
            readonly property Process left: Process {
                running: true
                command: ["pw-loopback", "-n", loop.name, "--capture-props", `media.class=Audio/Sink node.name=${loop.name} audio.channels=1 audio.position=[MONO] node.virtual=true ${loop.common}`, "--playback-props", `node.name=${loop.name}.left audio.channels=1 audio.position=[FL] target.object=${loop.device} stream.dont-remix=true ${loop.common}`]
            }

            // The right side, from the virtual output's monitor once it's there
            readonly property Process right: Process {
                running: Pipewire.nodes.values.some(n => n.name === loop.name)
                command: ["pw-loopback", "-n", `${loop.name}-right`, "--capture-props", `node.name=${loop.name}.rin audio.channels=1 audio.position=[MONO] stream.capture.sink=true target.object=${loop.name} ${loop.common}`, "--playback-props", `node.name=${loop.name}.right audio.channels=1 audio.position=[FR] target.object=${loop.device} stream.dont-remix=true ${loop.common}`]
            }
        }
    }
}
