pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import Caelestia.Config
import Caelestia.I18n
import Caelestia.State
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

// Keep awake, what the shell does when you're away (general.idle.timeouts:
// steps these rows don't know are left alone), and a look at what else could
// put the computer to sleep, which the shell can't change (assets/power-check.py).
PageBase {
    id: root

    readonly property var idle: GlobalConfig.general.idle
    readonly property var steps: idle.timeouts.values
    // What power-check.py found, once it has
    property var system: null

    readonly property bool canHibernate: ["yes", "challenge"].includes(system?.canHibernate ?? "")
    readonly property string sleepKind: {
        const step = steps.find(s => kindOf(s) === "sleep" && s.enabled);
        const command = step ? commandOf(step) : "";
        if (command.endsWith("suspendthenhibernate"))
            return "suspendThenHibernate";
        return command.endsWith("hibernate") ? "hibernate" : "suspend";
    }
    readonly property bool sleeps: secondsFor("sleep") > 0

    readonly property var durations: [0, 60, 120, 180, 300, 600, 900, 1200, 1800, 2700, 3600, 7200, 10800]

    readonly property bool idleSleeps: !!system && !["", "ignore", "lock"].includes(system.idleAction)
    readonly property bool hypridleSleeps: !!system && system.hypridleRunning && system.hypridleSleeps.length > 0

    function commandOf(step: var): string {
        const action = step.idleAction;
        const words = typeof action === "string" ? [action] : Array.from(action ?? []);
        return words.join(" ").toLowerCase().replace(/[-_]/g, "");
    }

    // Which row a step belongs to; "" for anything else
    function kindOf(step: var): string {
        const command = commandOf(step);
        if (command === "lock" || command.endsWith("locksession") || command.endsWith("shell lock lock"))
            return "lock";
        if (command.endsWith("dpms off"))
            return "screen";
        if (command.endsWith("brightness set 0"))
            return "dim";
        return /(^| )(suspend|suspendthenhibernate|hibernate)$/.test(command) ? "sleep" : "";
    }

    function secondsFor(kind: string): int {
        return steps.find(s => kindOf(s) === kind && s.enabled)?.timeout ?? 0;
    }

    function hasStep(kind: string): bool {
        return steps.some(s => kindOf(s) === kind);
    }

    // Sets how long until a step (0: never), adding it if there isn't one.
    // Turned off rather than removed, so a custom step keeps its command.
    function setStep(kind: string, seconds: int): void {
        const list = idle.timeouts;
        let done = false;
        for (let i = 0; i < list.count; i++) {
            const step = list.at(i);
            if (kindOf(step) !== kind)
                continue;
            if (seconds > 0 && !done) {
                step.timeout = seconds;
                step.enabled = true;
                done = true;
            } else {
                step.enabled = false;
            }
        }
        if (seconds > 0 && !done)
            list.insert(Object.assign({
                timeout: seconds
            }, actionsFor(kind)));
    }

    function actionsFor(kind: string): var {
        if (kind === "lock")
            return {
                idleAction: "lock"
            };
        if (kind === "screen")
            return {
                idleAction: "dpms off",
                returnAction: "dpms on"
            };
        return {
            idleAction: [canHibernate ? "suspendThenHibernate" : "suspend"]
        };
    }

    function setSleepKind(kind: string): void {
        const list = idle.timeouts;
        for (let i = 0; i < list.count; i++)
            if (kindOf(list.at(i)) === "sleep")
                list.at(i).idleAction = [kind];
    }

    function formatTime(seconds: int): string {
        if (seconds <= 0)
            return Tr.tr("Never");
        if (seconds < 3600)
            return seconds % 60 === 0 ? Tr.tr("%1 min").arg(seconds / 60) : Tr.tr("%1 s").arg(seconds);
        const hours = seconds / 3600;
        return hours === 1 ? Tr.tr("1 hour") : Tr.tr("%1 hours").arg(Math.round(hours * 10) / 10);
    }

    function actionName(action: string): string {
        return ({
                suspend: Tr.tr("Suspends"),
                hibernate: Tr.tr("Hibernates"),
                "hybrid-sleep": Tr.tr("Suspends and hibernates"),
                "suspend-then-hibernate": Tr.tr("Suspends, then hibernates"),
                poweroff: Tr.tr("Shuts down"),
                reboot: Tr.tr("Restarts")
            })[action] ?? action;
    }

    title: Tr.tr("Power")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        Process {
            running: true
            command: ["python3", "-I", `${Quickshell.shellDir}/assets/power-check.py`]

            stdout: StdioCollector {
                onStreamFinished: {
                    try {
                        root.system = JSON.parse(text);
                    } catch (e) {
                        root.system = null;
                    }
                }
            }
        }

        ToggleRow {
            first: true
            last: true
            text: Tr.trCtx("Keep awake", "idle inhibitor")
            subtext: Tr.tr("Until you turn it off: no locking, no screen off, no sleep when idle")
            checked: RuntimeState.inhibitIdle
            onToggled: RuntimeState.inhibitIdle = checked
        }

        SectionHeader {
            text: Tr.tr("When you're away")
        }

        StepRow {
            first: true
            kind: "lock"
            label: Tr.tr("Lock the screen")
        }

        StepRow {
            kind: "dim"
            visible: root.hasStep("dim")
            label: Tr.tr("Dim the screen")
        }

        StepRow {
            kind: "screen"
            label: Tr.tr("Turn the screen off")
        }

        StepRow {
            kind: "sleep"
            last: !root.sleeps
            label: Tr.tr("Put the computer to sleep")
            subtext: Tr.tr("Leave on Never to stay on all the time")
        }

        SelectRow {
            visible: root.sleeps
            last: true
            label: Tr.tr("How it sleeps")
            subtext: Tr.tr("Hibernating needs swap the size of your memory")
            menuItems: root.canHibernate ? [suspendItem, thenItem, hibernateItem] : [suspendItem]
            active: [suspendItem, thenItem, hibernateItem].find(i => i.value === root.sleepKind) ?? suspendItem
            onSelected: item => root.setSleepKind(item.value)

            MenuItem {
                id: suspendItem

                text: Tr.tr("Suspend")
                icon: "bedtime"
                value: "suspend"
            }

            MenuItem {
                id: thenItem

                text: Tr.tr("Suspend, then hibernate")
                icon: "bedtime_off"
                value: "suspendThenHibernate"
            }

            MenuItem {
                id: hibernateItem

                text: Tr.tr("Hibernate")
                icon: "downloading"
                value: "hibernate"
            }
        }

        SectionHeader {
            text: Tr.tr("Exceptions")
        }

        ToggleRow {
            first: true
            text: Tr.tr("Not while media is playing")
            subtext: Tr.tr("None of the above while a player is playing")
            checked: root.idle.inhibitWhenAudio
            onToggled: root.idle.inhibitWhenAudio = checked
        }

        ToggleRow {
            visible: UPower.displayDevice.isLaptopBattery
            text: Tr.tr("Not while plugged in")
            subtext: Tr.tr("None of the above while on the charger")
            checked: root.idle.inhibitWhenCharging
            onToggled: root.idle.inhibitWhenCharging = checked
        }

        ToggleRow {
            last: true
            text: Tr.tr("Lock before sleeping")
            subtext: Tr.tr("However the computer goes to sleep")
            checked: root.idle.lockBeforeSleep
            onToggled: root.idle.lockBeforeSleep = checked
        }

        SectionHeader {
            text: Tr.tr("Outside the shell")
        }

        StatusRow {
            first: true
            warn: root.idleSleeps
            label: Tr.tr("System idle action")
            subtext: root.idleSleeps ? Tr.tr("Set by IdleAction in logind.conf. Keep awake holds it off") : Tr.tr("logind doesn't act on idle")
            value: !root.system ? "…" : root.idleSleeps ? Tr.tr("%1 after %2").arg(root.actionName(root.system.idleAction)).arg(root.formatTime(root.system.idleSeconds)) : Tr.tr("Nothing")
        }

        StatusRow {
            warn: root.hypridleSleeps
            label: "hypridle"
            subtext: root.hypridleSleeps ? root.system.hypridleSleeps[0].command : Tr.tr("~/.config/hypr/hypridle.conf")
            value: !root.system ? "…" : root.hypridleSleeps ? Tr.tr("Sleeps after %1").arg(root.formatTime(root.system.hypridleSleeps[0].timeout)) : Tr.tr("Doesn't sleep")
        }

        StatusRow {
            last: !UPower.displayDevice.isLaptopBattery
            warn: (root.system?.others.length ?? 0) > 0
            label: Tr.tr("Other power managers")
            subtext: Tr.tr("They have their own idle settings")
            value: !root.system ? "…" : root.system.others.join(", ") || Tr.tr("None running")
        }

        StatusRow {
            visible: UPower.displayDevice.isLaptopBattery
            last: true
            label: Tr.tr("Closing the lid")
            subtext: Tr.tr("Set by HandleLidSwitch in logind.conf. Keep awake doesn't change it")
            value: !root.system ? "…" : root.system.lid === "ignore" ? Tr.tr("Nothing") : root.actionName(root.system.lid)
        }
    }

    component StepRow: SelectRow {
        id: row

        required property string kind
        readonly property int seconds: root.secondsFor(kind)

        menuItems: items.instances
        active: items.instances.find(i => i.value === seconds) ?? null
        fallbackText: root.formatTime(seconds)
        onSelected: item => root.setStep(kind, item.value)

        Variants {
            id: items

            model: root.durations

            MenuItem {
                required property int modelData

                text: root.formatTime(modelData)
                value: modelData
            }
        }
    }

    component StatusRow: InfoRow {
        property bool warn

        icon: warn ? "warning" : "check_circle"
        iconColour: warn ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
    }
}
