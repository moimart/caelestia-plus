pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

// Panning an app's sound to the left or right.
//
// An app plays as it is (stereo, 5.1, 7.1) while centred. Panned, it plays
// into a one-channel virtual output of its own, which mixes it down to mono,
// and a loopback plays that on the real device's front left and right, at the
// pan's gains. Centred again, the app goes back to the device and the
// loopback goes away. The loopbacks are the shell's processes: if the shell
// quits, PipeWire puts their apps back on the default output.
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
            const device = Audio.streamDevice(stream);
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
        const out = node(`${prefix}${serial}.out`);
        if (!pans[serial] || !device?.name)
            return;
        update(serial, {
            pan: pans[serial].pan,
            device: device.name
        });
        const outSerial = out?.properties["object.serial"];
        if (outSerial)
            Quickshell.execDetached(["pactl", "move-sink-input", String(outSerial), device.name]);
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
            const out = nodes.find(n => n.name === `${prefix}${serial}.out`);
            const audio = out?.audio;
            if (audio && audio.channels.length === 2) {
                // Full on the side it's panned to, fading on the other
                const left = p.pan > 0 ? 1 - p.pan : 1;
                const right = p.pan < 0 ? 1 + p.pan : 1;
                if (Math.abs(audio.volumes[0] - left) > 0.001 || Math.abs(audio.volumes[1] - right) > 0.001)
                    audio.volumes = [left, right];
            }
        }
        syncing = false;
    }

    function ensureLoop(serial: string, device: string): void {
        for (let i = 0; i < loops.count; i++)
            if (loops.get(i).serial === serial)
                return;
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

    // One loopback per panned stream. A ListModel, so adding or removing one
    // leaves the others running
    ListModel {
        id: loops
    }

    Instantiator {
        model: loops

        Process {
            required property string serial
            required property string device
            readonly property string name: `${root.prefix}${serial}`

            running: true
            command: ["pw-loopback", "-n", name, "--capture-props", `media.class=Audio/Sink node.name=${name} node.description=Panning audio.channels=1 audio.position=[MONO] node.virtual=true`, "--playback-props", `node.name=${name}.out node.description=Panning audio.channels=2 audio.position=[FL FR] target.object=${device} stream.dont-remix=true`]
        }
    }
}
