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
// ~/.config/caelestia/host-sensors.json, with "source":
// - "vsock" (and "port", default 7770): the VM's own channel to its host, no
//   network and no keys. The host serves the readings
//   (assets/host-sensors-vsock-setup.sh, run there once) and
//   assets/host-sensors-vsock.py reads them.
// - "ssh" (with "ssh": "user@host" and "key", default
//   ~/.ssh/caelestia-host-sensors): any machine, over ssh with a key that can
//   only print the readings (assets/host-sensors-setup.sh).
// Either way one connection stays open and the host prints /sys/class/hwmon
// every few seconds (assets/host-sensors-loop.sh). Settings → Services.
Singleton {
    id: root

    readonly property string path: `${Paths.config}/host-sensors.json`
    property var config: ({})
    // "vsock", "ssh" or "" (off); older files only had "ssh"
    readonly property string source: config.source ?? (config.ssh ? "ssh" : "")
    readonly property int port: config.port ?? 7770
    readonly property string target: config.ssh ?? ""
    readonly property string key: Paths.absolutePath(config.key ?? "~/.ssh/caelestia-host-sensors")
    readonly property bool enabled: source === "vsock" || (source === "ssh" && target !== "")
    // Over ssh, only with the key: without it there's no point knocking (sshd
    // turns away an address after too many failed logins)
    readonly property bool ready: enabled && (source === "vsock" || hasKey)

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
    property bool hasKey
    property bool authFailed
    property int failures

    function save(next: var): void {
        config = next;
        file.setText(JSON.stringify(next, null, 4) + "\n");
    }

    function restart(): void {
        proc.running = false;
        readings = [];
        connected = false;
        authFailed = false;
        failures = 0;
        error = enabled && !ready ? Tr.tr("No key yet: set up access") : "";
        if (ready && loop)
            retry.restart();
    }

    // Once the bindings that depend on them have caught up too
    onSourceChanged: Qt.callLater(restart)
    onPortChanged: Qt.callLater(restart)
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

    // The key's public half: set up access makes it, and that's the cue to
    // try again
    FileView {
        path: root.source === "ssh" ? `${root.key}.pub` : ""
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            root.hasKey = true;
            Qt.callLater(root.restart);
        }
        onLoadFailed: {
            root.hasKey = false;
            Qt.callLater(root.restart);
        }
    }

    FileView {
        path: `${Quickshell.shellDir}/assets/host-sensors-loop.sh`
        printErrors: false
        onLoaded: root.loop = text().trim()
    }

    Process {
        id: proc

        property var errors: []

        // Over ssh, with the key's forced command on the host what's asked
        // here is ignored and the same loop runs anyway
        command: root.source === "vsock" ? ["python3", `${Quickshell.shellDir}/assets/host-sensors-vsock.py`, String(root.port)] : ["ssh", "-T", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=2", "-o", "StrictHostKeyChecking=accept-new", "-o", "IdentitiesOnly=yes", "-i", root.key, root.target, root.loop]

        stdout: SplitParser {
            onRead: line => {
                if (line === ".") {
                    root.readings = root.pending;
                    root.pending = [];
                    root.connected = true;
                    root.error = "";
                    root.failures = 0;
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
            root.failures++;
            // A refused key stays refused: no retrying until it's set up again
            root.authFailed = root.source === "ssh" && last.includes("Permission denied");
            if (root.authFailed)
                root.error = Tr.tr("The host doesn't take the key yet: set up access");
            else
            // vsock: no device in this VM yet (it takes a stop and start), or
            // nothing listening on the host
            if (root.source === "vsock")
                root.error = Tr.tr("No answer from the host: set it up, then stop and start the VM");
            else if (/timed out|No route|Connection refused|Could not resolve/.test(last))
                root.error = Tr.tr("Can't reach %1").arg(root.target);
            else
                root.error = last || Tr.tr("ssh stopped (%1)").arg(code);
            if (root.enabled && !root.authFailed)
                retry.restart();
        }
    }

    // Connects, and reconnects a while after it drops
    Timer {
        id: retry

        // 15 s after the first failure, doubling up to 10 min
        interval: root.failures === 0 ? 1000 : Math.min(600000, 15000 * Math.pow(2, root.failures - 1))
        onTriggered: if (root.ready && root.loop && !proc.running)
            proc.running = true
    }

    // qs ipc call hostSensors status
    IpcHandler {
        function status(): string {
            return JSON.stringify({
                source: root.source,
                target: root.source === "vsock" ? `vsock:2:${root.port}` : root.target,
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
