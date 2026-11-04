pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

// The Microsoft Surface Dial (services/SurfaceDial.qml): whether the shell
// uses it, which modes a press cycles through, and how far a step goes. The
// Home Assistant player it can turn is picked in Home Assistant's page.
PageBase {
    id: root

    readonly property var cfg: GlobalConfig.surfaceDial

    // Turns a mode on or off, keeping the modes in their usual order
    function setMode(mode: string, on: bool): void {
        const modes = SurfaceDial.allModes.filter(m => m === mode ? on : cfg.modes.includes(m));
        cfg.modes = modes;
    }

    title: Tr.tr("Surface Dial")

    // Home Assistant modes are named after their entities
    Component.onCompleted: SurfaceDial.viewers++
    Component.onDestruction: SurfaceDial.viewers--

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
                    radius: implicitWidth / 2
                    color: SurfaceDial.connected ? Colours.palette.m3primaryContainer : Colours.palette.m3surfaceContainerHighest

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: SurfaceDial.connected && SurfaceDial.mode ? SurfaceDial.info(SurfaceDial.mode).icon : "adjust"
                        color: SurfaceDial.connected ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant
                        fill: 1
                        fontStyle: Tokens.font.icon.large
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.extraSmall

                    StyledText {
                        Layout.fillWidth: true
                        text: !root.cfg.enabled ? Tr.tr("Off") : SurfaceDial.connected ? Tr.tr("Connected · %1").arg(SurfaceDial.mode ? SurfaceDial.info(SurfaceDial.mode).name : Tr.tr("no modes")) : SurfaceDial.paired ? Tr.tr("Asleep") : Tr.tr("No Surface Dial paired")
                        font: Tokens.font.title.medium
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: {
                            if (SurfaceDial.error)
                                return SurfaceDial.error;
                            if (SurfaceDial.connected)
                                return Tr.tr("Press the dial to change mode, turn it to act.");
                            if (SurfaceDial.paired)
                                return Tr.tr("It sleeps when it's not used: turn it or press it to wake it.");
                            if (!SurfaceDial.bluetoothOn)
                                return Tr.tr("Bluetooth is off. Turn it on, then pair the dial in Bluetooth settings.");
                            return Tr.tr("Pair it in Bluetooth settings: hold the button by its battery until the light blinks.");
                        }
                        color: SurfaceDial.error ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.small
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }

        SectionHeader {
            text: Tr.tr("General")
        }

        ToggleRow {
            first: true
            text: Tr.trCtx("Enabled", "toggle label")
            subtext: Tr.tr("The shell reads the dial, and nothing else gets it")
            checked: root.cfg.enabled
            onToggled: root.cfg.enabled = checked
        }

        ToggleRow {
            last: true
            text: Tr.tr("Toasts")
            subtext: Tr.tr("Show the mode when it changes, and when the dial connects or sleeps")
            checked: root.cfg.toasts
            onToggled: root.cfg.toasts = checked
        }

        SectionHeader {
            text: Tr.tr("Modes")
        }

        Repeater {
            model: SurfaceDial.allModes

            ToggleRow {
                required property string modelData
                required property int index
                readonly property var info: SurfaceDial.info(modelData)

                first: index === 0
                text: info.name
                subtext: info.description
                checked: root.cfg.modes.includes(modelData)
                onToggled: root.setMode(modelData, checked)
            }
        }

        InfoRow {
            last: true
            icon: "home_iot_device"
            label: Tr.tr("Home Assistant")
            subtext: Tr.tr("Any light, player, cover, fan, thermostat or number can be a mode: add them in Home Assistant's settings")
        }

        SectionHeader {
            text: Tr.tr("Steps")
        }

        StepperRow {
            first: true
            label: Tr.tr("Volume")
            subtext: Tr.tr("Percent per step")
            value: root.cfg.volumeStep
            from: 1
            to: 20
            onMoved: v => root.cfg.volumeStep = v
        }

        StepperRow {
            label: Tr.tr("Zoom")
            subtext: Tr.tr("Zoom factor per step")
            value: root.cfg.zoomStep
            from: 0.1
            to: 2
            stepSize: 0.1
            onMoved: v => root.cfg.zoomStep = Math.round(v * 10) / 10
        }

        StepperRow {
            label: Tr.tr("Scroll")
            subtext: Tr.tr("Wheel notches per step")
            value: root.cfg.scrollSpeed
            from: 1
            to: 10
            onMoved: v => root.cfg.scrollSpeed = v
        }

        StepperRow {
            last: true
            label: Tr.tr("Columns")
            subtext: root.cfg.layoutPixels > 0 ? Tr.tr("Pixels per step") : Tr.tr("A whole column per step; raise it to move by pixels")
            value: root.cfg.layoutPixels
            from: 0
            to: 1000
            stepSize: 50
            onMoved: v => root.cfg.layoutPixels = v
        }
    }
}
