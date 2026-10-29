pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config
import Caelestia.I18n

// System updates through the distribution's own package manager: a check that
// needs no root, then the upgrade as root through pkexec, so the password goes
// to the desktop's polkit agent and never through the shell. Settings → Updates
// is the front end.
//
// One backend per family of distributions, picked from /etc/os-release (ID and
// ID_LIKE). Only Arch's is tested, on a real machine. The others are reference
// implementations, written from each package manager's documentation and
// never run here: corrections from people on those distributions are welcome.
//
// A backend is:
//   name       the package manager, as shown
//   tested     whether it has been run for real
//   check      a command listing pending updates, without root
//   okExits    the check's exit codes that aren't errors
//   parse      one line of the check's output → { name, from, to }, or null
//   upgrade    the upgrade, run under pkexec; it must not ask anything
//   terminal   the same upgrade for a terminal, where it may ask
//   steps      one line of the upgrade's output → { label, done, total }, or null
//   reboot     package names that call for a restart afterwards
Singleton {
    id: root

    readonly property var backends: ({
            // Arch and derivatives (CachyOS, EndeavourOS, Manjaro...). Tested.
            // checkupdates (pacman-contrib) syncs a copy of the databases, so
            // checking never leaves the system half-synced; the upgrade itself
            // is a plain pacman -Syu.
            arch: {
                name: "pacman",
                tested: true,
                check: ["checkupdates"],
                // checkupdates: 0 updates, 2 none, 1 failed
                okExits: [0, 2],
                parse: line => {
                    const m = line.match(/^(\S+) (\S+) -> (\S+)/);
                    return m ? {
                        name: m[1],
                        from: m[2],
                        to: m[3]
                    } : null;
                },
                upgrade: ["pacman", "-Syu", "--noconfirm", "--color", "never"],
                terminal: "sudo pacman -Syu",
                steps: line => {
                    if (line.startsWith(":: Synchronizing"))
                        return {
                            label: Tr.tr("Syncing the package databases")
                        };
                    if (line.startsWith(":: Retrieving packages"))
                        return {
                            label: Tr.tr("Downloading")
                        };
                    if (line.startsWith(":: Running post-transaction hooks"))
                        return {
                            label: Tr.tr("Finishing up")
                        };
                    // "( 3/64) upgrading foo", "(1/12) Arming ConditionNeedsUpdate..."
                    const m = line.match(/^\(\s*(\d+)\/(\d+)\)\s+(.+)$/);
                    if (!m)
                        return null;
                    const what = m[3].replace(/\.\.\.$/, "");
                    const verbs = {
                        "checking keys in keyring": Tr.tr("Checking keys"),
                        "checking package integrity": Tr.tr("Checking packages"),
                        "loading package files": Tr.tr("Loading packages"),
                        "checking for file conflicts": Tr.tr("Checking for conflicts"),
                        "checking available disk space": Tr.tr("Checking disk space")
                    };
                    const install = what.match(/^(upgrading|installing|reinstalling|removing|downgrading) (.+)$/);
                    return {
                        label: verbs[what] ?? (install ? `${install[1][0].toUpperCase()}${install[1].slice(1)} ${install[2]}` : what),
                        done: parseInt(m[1]),
                        total: parseInt(m[2])
                    };
                },
                reboot: /^(linux(-[\w-]+)?|nvidia(-[\w-]+)?|systemd|glibc|mesa|amd-ucode|intel-ucode)$/
            },

            // Debian, Ubuntu, Mint, Pop!_OS... Reference implementation,
            // untested. apt list --upgradable reads the package lists as they
            // were last updated (by the system's own timer, or the last
            // upgrade); the upgrade refreshes them first.
            debian: {
                name: "apt",
                tested: false,
                check: ["apt", "list", "--upgradable"],
                okExits: [0],
                // "foo/stable 1.2-1 amd64 [upgradable from: 1.1-1]"
                parse: line => {
                    const m = line.match(/^([^\/\s]+)\/\S+\s+(\S+)\s+\S+\s+\[upgradable from: ([^\]]+)\]/);
                    return m ? {
                        name: m[1],
                        from: m[3],
                        to: m[2]
                    } : null;
                },
                upgrade: ["sh", "-c", "apt-get update && DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::=--force-confold full-upgrade"],
                terminal: "sudo apt update && sudo apt full-upgrade",
                steps: line => {
                    if (/^(Hit|Get|Ign):/.test(line))
                        return {
                            label: Tr.tr("Refreshing the package lists")
                        };
                    const m = line.match(/^(Unpacking|Setting up) (\S+)/);
                    return m ? {
                        label: `${m[1] === "Unpacking" ? Tr.tr("Unpacking") : Tr.tr("Setting up")} ${m[2]}`
                    } : null;
                },
                reboot: /^(linux-image-.*|nvidia-.*|systemd|libc6)$/
            },

            // Fedora, RHEL, CentOS Stream, Rocky, Alma... Reference
            // implementation, untested. dnf check-update exits 100 when there
            // are updates.
            fedora: {
                name: "dnf",
                tested: false,
                check: ["dnf", "check-update", "-q"],
                okExits: [0, 100],
                // "foo.x86_64   1.2-1.fc41   updates" (no installed version)
                parse: line => {
                    const m = line.match(/^(\S+)\.(\w+)\s+(\S+)\s+(\S+)\s*$/);
                    return m ? {
                        name: m[1],
                        from: "",
                        to: m[3]
                    } : null;
                },
                upgrade: ["dnf", "-y", "upgrade"],
                terminal: "sudo dnf upgrade",
                steps: line => {
                    const m = line.match(/^\s*(Upgrading|Installing|Cleanup|Verifying)\s*:\s*(\S+)\s+(\d+)\/(\d+)/);
                    return m ? {
                        label: `${m[1]} ${m[2]}`,
                        done: parseInt(m[3]),
                        total: parseInt(m[4])
                    } : null;
                },
                reboot: /^(kernel(-core)?|nvidia-.*|akmod-nvidia|systemd|glibc)$/
            },

            // openSUSE Leap, SLE. Reference implementation, untested.
            // Tumbleweed (rolling) upgrades with dup instead; see below.
            suse: {
                name: "zypper",
                tested: false,
                check: ["zypper", "-q", "list-updates"],
                okExits: [0],
                // "v | repo | foo | 1.1-1 | 1.2-1 | x86_64"
                parse: line => {
                    const cols = line.split("|").map(c => c.trim());
                    return cols.length >= 6 && cols[0] === "v" ? {
                        name: cols[2],
                        from: cols[3],
                        to: cols[4]
                    } : null;
                },
                upgrade: ["zypper", "-n", "update"],
                terminal: "sudo zypper update",
                steps: line => {
                    const m = line.match(/^\(\s*(\d+)\/(\d+)\)\s+(Installing|Retrieving):\s+(\S+)/);
                    return m ? {
                        label: `${m[3]} ${m[4]}`,
                        done: parseInt(m[1]),
                        total: parseInt(m[2])
                    } : null;
                },
                reboot: /^(kernel-default|nvidia-.*|systemd|glibc)$/
            }
        })

    // Which backend: from /etc/os-release
    property var osRelease: ({})
    readonly property string family: {
        const ids = [osRelease.ID ?? "", ...(osRelease.ID_LIKE ?? "").split(/\s+/)];
        if (ids.some(i => ["arch", "cachyos", "endeavouros", "manjaro"].includes(i)))
            return "arch";
        if (ids.some(i => ["debian", "ubuntu"].includes(i)))
            return "debian";
        if (ids.some(i => ["fedora", "rhel", "centos"].includes(i)))
            return "fedora";
        if (ids.some(i => i.startsWith("opensuse") || ["suse", "sles"].includes(i)))
            return "suse";
        return "";
    }
    readonly property var backend: {
        const b = backends[family] ?? null;
        // Tumbleweed is rolling: a distribution upgrade every time
        if (b && osRelease.ID === "opensuse-tumbleweed")
            return Object.assign({}, b, {
                upgrade: ["zypper", "-n", "dup"],
                terminal: "sudo zypper dup"
            });
        return b;
    }
    readonly property string distroName: osRelease.PRETTY_NAME ?? osRelease.NAME ?? ""

    // "idle", "checking" or "upgrading"
    property string state: "idle"
    readonly property bool busy: state !== "idle"
    property var updates: []
    property date lastChecked
    property bool everChecked
    property string checkError

    // The upgrade, as it runs
    property list<string> log
    property string step
    property int stepDone
    property int stepTotal
    // "", "done", "failed" or "cancelled"
    property string result
    property string resultMessage
    property bool rebootSuggested

    property var pendingUpgrade: []

    function check(): void {
        if (!backend || busy)
            return;
        state = "checking";
        checkError = "";
        checkProc.found = [];
        checkProc.errors = [];
        checkProc.command = backend.check;
        checkProc.running = true;
    }

    function upgrade(): void {
        if (!backend || busy)
            return;
        state = "upgrading";
        log = [];
        step = Tr.tr("Waiting for your password");
        stepDone = 0;
        stepTotal = 0;
        result = "";
        resultMessage = "";
        pendingUpgrade = updates.map(u => u.name);
        upgradeProc.command = ["pkexec", ...backend.upgrade];
        upgradeProc.running = true;
    }

    // For when it needs answers (a conflict, a replaced package): the same
    // upgrade in a terminal
    function upgradeInTerminal(): void {
        if (!backend)
            return;
        Quickshell.execDetached([...GlobalConfig.general.apps.terminal, "sh", "-c", `${backend.terminal}; echo; printf '%s' '${Tr.tr("Press Enter to close").replace(/'/g, "")}'; read _`]);
    }

    function addLog(line: string): void {
        if (!line.trim())
            return;
        const next = log.length >= 800 ? log.slice(-600) : log.slice();
        next.push(line);
        log = next;
        const s = backend?.steps(line);
        if (s) {
            step = s.label;
            stepDone = s.done ?? 0;
            stepTotal = s.total ?? 0;
        }
    }

    function finishUpgrade(code: int): void {
        state = "idle";
        // pkexec: 126 the dialog was dismissed, 127 not authorised
        if (code === 126 || code === 127) {
            result = "cancelled";
            resultMessage = code === 126 ? Tr.tr("The password dialog was closed") : Tr.tr("Not authorised");
        } else if (code === 0) {
            result = "done";
            rebootSuggested = rebootSuggested || pendingUpgrade.some(n => backend.reboot.test(n));
            resultMessage = pendingUpgrade.length === 1 ? Tr.tr("1 package updated") : Tr.tr("%1 packages updated").arg(pendingUpgrade.length);
            Toaster.toast(Tr.tr("System updated"), rebootSuggested ? Tr.tr("%1. Restart to use the new kernel and system libraries").arg(resultMessage) : resultMessage, "system_update", Toast.Success);
        } else {
            result = "failed";
            const lock = log.some(l => /unable to lock database|Could not get lock|System management is locked/.test(l));
            const err = [...log].reverse().find(l => /^(error|E:|Error)/i.test(l)) ?? "";
            resultMessage = lock ? Tr.tr("Another package manager is running") : err || Tr.tr("It stopped with code %1").arg(code);
            Toaster.toast(Tr.tr("System update failed"), resultMessage, "error", Toast.Error);
        }
        check();
    }

    function status(): var {
        return {
            distro: distroName,
            packageManager: backend?.name ?? "",
            tested: backend?.tested ?? false,
            state: state,
            updates: updates,
            lastChecked: everChecked ? lastChecked.toISOString() : "",
            checkError: checkError,
            result: result,
            resultMessage: resultMessage,
            step: step,
            rebootSuggested: rebootSuggested
        };
    }

    FileView {
        path: "/etc/os-release"
        printErrors: false
        onLoaded: {
            const out = {};
            for (const line of text().split("\n")) {
                const m = line.match(/^([A-Z_]+)=(.*)$/);
                if (m)
                    out[m[1]] = m[2].replace(/^"(.*)"$/, "$1");
            }
            root.osRelease = out;
        }
    }

    Process {
        id: checkProc

        property var found: []
        property var errors: []

        stdout: SplitParser {
            onRead: line => {
                const u = root.backend?.parse(line);
                if (u)
                    checkProc.found.push(u);
            }
        }
        stderr: SplitParser {
            onRead: line => checkProc.errors.push(line)
        }
        onExited: code => {
            root.state = "idle";
            if (!root.backend.okExits.includes(code)) {
                root.checkError = checkProc.errors.filter(e => e.trim()).slice(-1)[0] ?? Tr.tr("The check stopped with code %1").arg(code);
                return;
            }
            root.updates = checkProc.found.sort((a, b) => a.name.localeCompare(b.name));
            root.lastChecked = new Date();
            root.everChecked = true;
        }
    }

    Process {
        id: upgradeProc

        stdout: SplitParser {
            onRead: line => root.addLog(line)
        }
        stderr: SplitParser {
            onRead: line => root.addLog(line)
        }
        onExited: code => root.finishUpgrade(code)
    }

    // A check a minute after starting, then every six hours
    Timer {
        running: !!root.backend
        interval: root.everChecked ? 6 * 60 * 60 * 1000 : 60 * 1000
        repeat: true
        onTriggered: root.check()
    }

    // qs ipc call systemUpdates status | check | upgrade
    IpcHandler {
        function status(): string {
            return JSON.stringify(root.status());
        }

        function check(): void {
            root.check();
        }

        // Asks for the password through polkit, as the button does
        function upgrade(): void {
            root.upgrade();
        }

        target: "systemUpdates"
    }
}
