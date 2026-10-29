pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

// System updates (services/SystemUpdates): what's pending, and the upgrade as
// it runs, with its output.
PageBase {
    id: root

    readonly property var backend: SystemUpdates.backend
    readonly property int count: SystemUpdates.updates.length
    property bool showAll
    property bool showLog
    // Refreshes "checked 5 min ago"
    property date now: new Date()

    readonly property string heroIcon: {
        if (!backend)
            return "help";
        if (SystemUpdates.state === "checking")
            return "sync";
        if (SystemUpdates.state === "upgrading")
            return "downloading";
        if (SystemUpdates.checkError)
            return "error";
        return count > 0 ? "system_update" : "check_circle";
    }
    readonly property string heroTitle: {
        if (!backend)
            return Tr.tr("No supported package manager");
        if (SystemUpdates.state === "upgrading")
            return Tr.tr("Updating…");
        if (SystemUpdates.state === "checking" && !SystemUpdates.everChecked)
            return Tr.tr("Checking for updates…");
        if (SystemUpdates.checkError && !SystemUpdates.everChecked)
            return Tr.tr("Couldn't check for updates");
        if (count === 0)
            return Tr.tr("Up to date");
        return count === 1 ? Tr.tr("1 update") : Tr.tr("%1 updates").arg(count);
    }
    readonly property string heroSubtext: {
        const parts = [SystemUpdates.distroName, backend?.name ?? ""];
        if (SystemUpdates.state === "checking")
            parts.push(Tr.tr("checking…"));
        else if (SystemUpdates.everChecked)
            parts.push(Tr.tr("checked %1").arg(ago(SystemUpdates.lastChecked)));
        return parts.filter(p => p).join(" · ");
    }

    function ago(d: date): string {
        const mins = Math.round((now - d) / 60000);
        if (mins < 1)
            return Tr.tr("just now");
        if (mins < 60)
            return Tr.tr("%1 min ago").arg(mins);
        const hours = Math.round(mins / 60);
        return hours === 1 ? Tr.tr("an hour ago") : Tr.tr("%1 hours ago").arg(hours);
    }

    title: Tr.tr("Updates")

    Component.onCompleted: {
        // Fresh when you come to look, unless it just checked
        if (!SystemUpdates.everChecked || new Date() - SystemUpdates.lastChecked > 10 * 60000)
            SystemUpdates.check();
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        ConnectedRect {
            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: hero.implicitHeight + Tokens.padding.extraLarge * 2

            RowLayout {
                id: hero

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Tokens.padding.extraLarge
                spacing: Tokens.spacing.large

                StyledRect {
                    implicitWidth: Math.round(Tokens.font.icon.large.pointSize * 2.6)
                    implicitHeight: implicitWidth
                    radius: Tokens.rounding.large
                    color: root.count > 0 || SystemUpdates.busy ? Colours.palette.m3primaryContainer : Colours.palette.m3secondaryContainer

                    MaterialIcon {
                        id: heroSymbol

                        anchors.centerIn: parent
                        text: root.heroIcon
                        color: root.count > 0 || SystemUpdates.busy ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSecondaryContainer
                        fill: 1
                        fontStyle: Tokens.font.icon.large

                        // Spins while it checks, and comes back upright
                        NumberAnimation on rotation {
                            running: SystemUpdates.state === "checking"
                            from: 360
                            to: 0
                            duration: 1200
                            loops: Animation.Infinite
                            onStopped: heroSymbol.rotation = 0
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.extraSmall

                    StyledText {
                        Layout.fillWidth: true
                        text: root.heroTitle
                        font: Tokens.font.title.medium
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.heroSubtext
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.small
                        wrapMode: Text.WordWrap
                    }
                }

                TextButton {
                    visible: !!root.backend
                    text: Tr.tr("Check")
                    type: TextButton.Text
                    disabled: SystemUpdates.busy
                    onClicked: SystemUpdates.check()
                }

                TextButton {
                    visible: root.count > 0 && SystemUpdates.state !== "upgrading"
                    text: Tr.tr("Update now")
                    type: TextButton.Filled
                    disabled: SystemUpdates.busy
                    onClicked: SystemUpdates.upgrade()
                }
            }
        }

        // The upgrade, running or just finished
        SectionHeader {
            visible: SystemUpdates.state === "upgrading" || SystemUpdates.result !== ""
            text: Tr.tr("Progress")
        }

        ConnectedRect {
            Layout.fillWidth: true
            visible: SystemUpdates.state === "upgrading"
            first: true
            implicitHeight: progress.implicitHeight + Tokens.padding.large * 2

            ColumnLayout {
                id: progress

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.small

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.medium

                    StyledText {
                        Layout.fillWidth: true
                        text: SystemUpdates.step
                        font: Tokens.font.body.medium
                        elide: Text.ElideMiddle
                    }

                    StyledText {
                        visible: SystemUpdates.stepTotal > 0
                        text: Tr.tr("%1 of %2").arg(SystemUpdates.stepDone).arg(SystemUpdates.stepTotal)
                        color: Colours.palette.m3outline
                        font: Tokens.font.label.medium
                    }
                }

                StyledProgressBar {
                    Layout.fillWidth: true
                    implicitHeight: Tokens.padding.small
                    indeterminate: SystemUpdates.stepTotal === 0
                    value: SystemUpdates.stepTotal > 0 ? SystemUpdates.stepDone / SystemUpdates.stepTotal : 0
                    wavy: true
                }
            }
        }

        InfoRow {
            visible: SystemUpdates.state !== "upgrading" && SystemUpdates.result !== ""
            first: true
            icon: ({
                    done: "check_circle",
                    failed: "error",
                    cancelled: "block"
                })[SystemUpdates.result] ?? ""
            iconColour: SystemUpdates.result === "failed" ? Colours.palette.m3error : Colours.palette.m3primary
            label: ({
                    done: Tr.tr("Updated"),
                    failed: Tr.tr("The update failed"),
                    cancelled: Tr.tr("Not updated")
                })[SystemUpdates.result] ?? ""
            subtext: SystemUpdates.resultMessage
        }

        RowButton {
            Layout.fillWidth: true
            visible: SystemUpdates.result === "done" && SystemUpdates.rebootSuggested && !SystemUpdates.busy
            icon: "restart_alt"
            text: Tr.tr("Restart now")
            subtext: Tr.tr("A new kernel or core system libraries were installed")
            onClicked: Quickshell.execDetached(["systemctl", "reboot"])
        }

        RowButton {
            Layout.fillWidth: true
            visible: SystemUpdates.result === "failed" && !SystemUpdates.busy
            icon: "terminal"
            text: Tr.tr("Update in a terminal")
            subtext: Tr.tr("Where it can ask about conflicts and replaced packages: %1").arg(root.backend?.terminal ?? "")
            onClicked: SystemUpdates.upgradeInTerminal()
        }

        RowButton {
            Layout.fillWidth: true
            visible: SystemUpdates.log.length > 0
            last: !root.showLog
            icon: "receipt_long"
            text: root.showLog ? Tr.tr("Hide the output") : Tr.tr("Show the output")
            subtext: SystemUpdates.log.length === 1 ? Tr.tr("1 line") : Tr.tr("%1 lines").arg(SystemUpdates.log.length)
            trailingIcon: root.showLog ? "expand_less" : "expand_more"
            onClicked: root.showLog = !root.showLog
        }

        ConnectedRect {
            Layout.fillWidth: true
            visible: root.showLog && SystemUpdates.log.length > 0
            last: true
            implicitHeight: 320

            ListView {
                id: logView

                // Follows the end while it's there
                property bool follow: true

                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                clip: true
                model: SystemUpdates.log

                onCountChanged: if (follow)
                    positionViewAtEnd()
                onMovementEnded: follow = atYEnd

                delegate: StyledText {
                    required property string modelData

                    width: logView.width
                    text: modelData
                    color: /^(error|E:|warning|W:)/i.test(modelData) ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.mono.small
                    wrapMode: Text.WrapAnywhere
                }

                StyledScrollBar.vertical: StyledScrollBar {
                    flickable: logView
                }
            }
        }

        InfoRow {
            visible: !!SystemUpdates.checkError
            Layout.topMargin: Tokens.spacing.medium
            first: true
            last: true
            icon: "wifi_off"
            iconColour: Colours.palette.m3error
            label: Tr.tr("The last check failed")
            subtext: SystemUpdates.checkError
        }

        // What's pending
        SectionHeader {
            visible: root.count > 0
            text: Tr.tr("Pending")
        }

        Repeater {
            model: root.showAll ? SystemUpdates.updates : SystemUpdates.updates.slice(0, 25)

            InfoRow {
                required property var modelData
                required property int index
                readonly property bool reboot: root.backend?.reboot.test(modelData.name) ?? false

                first: index === 0
                last: index === root.count - 1
                icon: reboot ? "restart_alt" : "deployed_code"
                iconColour: reboot ? Colours.palette.m3tertiary : Colours.palette.m3onSurfaceVariant
                label: modelData.name
                subtext: reboot ? Tr.tr("Needs a restart afterwards") : ""
                value: modelData.from ? `${modelData.from} → ${modelData.to}` : modelData.to
            }
        }

        RowButton {
            Layout.fillWidth: true
            visible: root.count > 25 && !root.showAll
            last: true
            icon: "expand_more"
            text: Tr.tr("Show all %1").arg(root.count)
            onClicked: root.showAll = true
        }

        // How it works
        SectionHeader {
            text: Tr.tr("How it works")
        }

        InfoRow {
            first: true
            icon: "key"
            label: Tr.tr("Updating asks for your password in the system's dialog")
            subtext: Tr.tr("Through polkit (pkexec): the shell never sees it")
        }

        InfoRow {
            icon: "schedule"
            label: Tr.tr("Checks every six hours, and when you open this page")
            subtext: root.backend ? Tr.tr("With %1, which needs no password").arg(root.backend.check.join(" ")) : ""
        }

        InfoRow {
            visible: !!root.backend && !root.backend.tested
            icon: "science"
            iconColour: Colours.palette.m3tertiary
            label: Tr.tr("Untested on %1").arg(SystemUpdates.distroName)
            subtext: Tr.tr("The %1 support is a reference implementation, written from its documentation. If something's off, update in a terminal").arg(root.backend?.name ?? "")
        }

        RowButton {
            Layout.fillWidth: true
            visible: !!root.backend
            last: true
            icon: "terminal"
            text: Tr.tr("Update in a terminal instead")
            subtext: root.backend?.terminal ?? ""
            disabled: SystemUpdates.busy
            onClicked: SystemUpdates.upgradeInTerminal()
        }

        // Refreshes "checked 5 min ago"
        Timer {
            running: true
            repeat: true
            interval: 30000
            onTriggered: root.now = new Date()
        }
    }
}
