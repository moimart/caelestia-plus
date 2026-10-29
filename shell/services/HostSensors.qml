pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.I18n
import Caelestia.Services
import qs.utils

// Temperatures from another machine, for when the shell runs where there are
// none: a virtual machine shows its host's CPU temperature instead of 0.
//
// ~/.config/caelestia/host-sensors.json: { "ssh": "user@host", "key": path }
// (key defaults to ~/.ssh/caelestia-host-sensors). One ssh connection stays
// open and the host prints /sys/class/hwmon every few seconds
// (assets/host-sensors-loop.sh); assets/host-sensors-setup.sh installs a key
// there that can do nothing else. Settings → Services sets it up.
Singleton {
    id: root

    readonly property string path: `${Paths.config}/host-sensors.json`
    property var config: ({})
    readonly property string target: config.ssh ?? ""
    readonly property string key: Paths.absolutePath(config.key ?? "~/.ssh/caelestia-host-sensors")
    readonly property bool enabled: target !== ""

    property bool connected
    property string error
    // The latest readings: [{ chip, label, value (°C) }]
    property var readings: []
    // The host's CPU: Package id N or Tdie, else Tctl, as for local sensors
    readonly property var cpu: readings.find(r => /^Package id /.test(r.label) || r.label === "Tdie") ?? readings.find(r => r.label === "Tctl") ?? readings.find(r => ["coretemp", "k10temp", "zenpower", "cpu_thermal"].includes(r.chip)) ?? null

    // What the shell shows: this machine's own when it has one, else the
    // host's, else 0 (as before)
    readonly property bool fromHost: Cpu.temperature <= 0 && cpu !== null
    readonly property real cpuTemperature: Cpu.temperature > 0 ? Cpu.temperature : (cpu?.value ?? 0)

    property string loop
    property var pending: []

    function save(next: var): void {
        config = next;
        file.setText(JSON.stringify(next, null, 4) + "\n");
    }

    function restart(): void {
        proc.running = false;
        readings = [];
        connected = false;
        error = "";
        if (enabled && loop)
            retry.restart();
    }

    // Once the bindings that depend on them have caught up too
    onTargetChanged: Qt.callLater(restart)
    onKeyChanged: Qt.callLater(restart)
    onLoopChanged: Qt.callLater(restart)

    FileView {
        id: file

        path: root.path
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root.config = JSON.parse(text());
            } catch (e) {
                console.warn(`HostSensors: bad host-sensors.json: ${e}`);
            }
        }
        onLoadFailed: root.config = {}
    }

    FileView {
        path: `${Quickshell.shellDir}/assets/host-sensors-loop.sh`
        printErrors: false
        onLoaded: root.loop = text().trim()
    }

    Process {
        id: proc

        property var errors: []

        // With the key's forced command on the host, what's asked here is
        // ignored and the same loop runs anyway
        command: ["ssh", "-T", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=2", "-o", "StrictHostKeyChecking=accept-new", "-o", "IdentitiesOnly=yes", "-i", root.key, root.target, root.loop]

        stdout: SplitParser {
            onRead: line => {
                if (line === ".") {
                    root.readings = root.pending;
                    root.pending = [];
                    root.connected = true;
                    root.error = "";
                    return;
                }
                const [chip, label, milli] = line.split("|");
                const v = parseInt(milli) / 1000;
                if (chip && !isNaN(v) && v > 0 && v < 150)
                    root.pending.push({
                        chip: chip,
                        label: label.trim(),
                        value: v
                    });
            }
        }
        stderr: SplitParser {
            onRead: line => {
                if (line.trim())
                    proc.errors.push(line.trim());
            }
        }
        onStarted: errors = []
        onExited: code => {
            root.connected = false;
            root.readings = [];
            const last = errors.filter(e => !e.startsWith("Warning:")).slice(-1)[0] ?? "";
            if (last.includes("Permission denied"))
                root.error = Tr.tr("The host doesn't take the key yet: set up access");
            else if (/timed out|No route|Connection refused|Could not resolve/.test(last))
                root.error = Tr.tr("Can't reach %1").arg(root.target);
            else
                root.error = last || Tr.tr("ssh stopped (%1)").arg(code);
            if (root.enabled)
                retry.restart();
        }
    }

    // Connects, and reconnects a while after it drops
    Timer {
        id: retry

        interval: proc.errors.length > 0 ? 30000 : 1000
        onTriggered: if (root.enabled && root.loop && !proc.running)
            proc.running = true
    }

    // qs ipc call hostSensors status
    IpcHandler {
        function status(): string {
            return JSON.stringify({
                target: root.target,
                connected: root.connected,
                error: root.error,
                cpu: root.cpu,
                local: Cpu.temperature,
                shown: root.cpuTemperature,
                readings: root.readings
            });
        }

        target: "hostSensors"
    }
}
