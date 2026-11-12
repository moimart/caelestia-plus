pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.utils

// One channel of the mixer: an app (or the default output or microphone), its
// volume as a tall fader, and the device it's routed to
StyledRect {
    id: root

    // An app's stream, or a device for the master channels
    required property PwNode node
    // A master channel: the default output or input itself, not an app
    property bool master
    property string masterTitle

    readonly property bool recording: master ? !node?.isSink : Audio.isRecording(node)
    readonly property real volume: node?.audio?.volume ?? 0
    readonly property bool muted: !!node?.audio?.muted
    // Where it plays to (or records from): the device at the other end of its links
    readonly property PwNode device: {
        if (master)
            return node;
        for (const g of Pipewire.linkGroups.values) {
            if (g.source !== node && g.target !== node)
                continue;
            const other = g.source === node ? g.target : g.source;
            if (other && !other.isStream)
                return other;
        }
        return null;
    }
    readonly property string title: master ? masterTitle : Audio.getStreamName(node)
    // What it's playing: a tab's or a track's title, when it says
    readonly property string subtitle: {
        if (master)
            return "";
        const media = node?.properties["media.name"] ?? "";
        return media && media !== title ? media : "";
    }
    readonly property alias chip: chip

    signal pickDevice

    implicitWidth: 168
    radius: Tokens.rounding.large
    color: master ? Colours.layer(Colours.palette.m3surfaceContainerHigh, 2) : Colours.layer(Colours.palette.m3surfaceContainer, 2)

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.padding.medium
        spacing: Tokens.spacing.small

        Item {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: 44
            implicitHeight: 44

            StyledRect {
                anchors.fill: parent
                visible: root.master
                radius: Tokens.rounding.full
                color: Colours.palette.m3primaryContainer

                MaterialIcon {
                    anchors.centerIn: parent
                    text: root.recording ? "mic" : "speaker"
                    color: Colours.palette.m3onPrimaryContainer
                    font: Tokens.font.icon.large
                    fill: 1
                }
            }

            StreamIcon {
                anchors.fill: parent
                visible: !root.master
                implicitSize: 44
                stream: root.master ? null : root.node
                opacity: root.muted ? 0.5 : 1
            }

            // Recording, not playing
            StyledRect {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: -2
                visible: !root.master && root.recording
                implicitWidth: 20
                implicitHeight: 20
                radius: Tokens.rounding.full
                color: Colours.palette.m3error

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "mic"
                    color: Colours.palette.m3onError
                    font: Tokens.font.icon.small
                    fill: 1
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: root.title
            elide: Text.ElideRight
            font: Tokens.font.label.large
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: -Tokens.spacing.small
            horizontalAlignment: Text.AlignHCenter
            text: root.subtitle || (root.master ? Tr.tr("Default") : " ")
            elide: Text.ElideRight
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.small
        }

        CustomMouseArea {
            function onWheel(event: WheelEvent): void {
                const step = GlobalConfig.services.audioIncrement;
                Audio.setStreamVolume(root.node, root.volume + (event.angleDelta.y > 0 ? step : -step));
            }

            Layout.alignment: Qt.AlignHCenter
            Layout.fillHeight: true
            Layout.topMargin: Tokens.spacing.small
            implicitWidth: 56

            FilledSlider {
                anchors.fill: parent
                opacity: root.muted ? 0.5 : 1
                icon: root.recording ? (root.muted ? "mic_off" : "mic") : Icons.getVolumeIcon(value, root.muted)
                value: root.volume
                to: GlobalConfig.services.maxVolume
                onMoved: Audio.setStreamVolume(root.node, value)
            }
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: root.muted ? Tr.tr("Muted") : `${Math.round(root.volume * 100)}%`
            color: root.muted ? Colours.palette.m3error : Colours.palette.m3onSurface
            font: Tokens.font.title.small
        }

        IconButton {
            Layout.alignment: Qt.AlignHCenter
            type: IconButton.Tonal
            isToggle: true
            checked: root.muted
            icon: root.recording ? (root.muted ? "mic_off" : "mic") : (root.muted ? "volume_off" : "volume_up")
            onClicked: Audio.setStreamMuted(root.node, !root.muted)
        }

        // The device it goes to; click to send it elsewhere
        StyledRect {
            id: chip

            Layout.fillWidth: true
            implicitHeight: chipRow.implicitHeight + Tokens.padding.small * 2
            radius: Tokens.rounding.large
            color: Colours.palette.m3secondaryContainer

            StateLayer {
                radius: parent.radius
                color: Colours.palette.m3onSecondaryContainer
                onClicked: root.pickDevice()
            }

            RowLayout {
                id: chipRow

                anchors.fill: parent
                anchors.leftMargin: Tokens.padding.small + 2
                anchors.rightMargin: Tokens.padding.small + 2
                spacing: Tokens.spacing.extraSmall

                MaterialIcon {
                    text: Audio.deviceIcon(root.device)
                    color: Colours.palette.m3onSecondaryContainer
                    font: Tokens.font.icon.small
                }

                // Two lines: device names run long ("Fractal Scape Dongle")
                StyledText {
                    Layout.fillWidth: true
                    text: Audio.deviceName(root.device)
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    color: Colours.palette.m3onSecondaryContainer
                    font: Tokens.font.label.small
                }
            }
        }
    }
}
