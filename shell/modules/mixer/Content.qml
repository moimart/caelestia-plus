pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.containers
import qs.components.controls
import qs.components.effects
import qs.services

// The mixer's sheet: the default output and microphone, then a channel per app
Item {
    id: root

    required property bool shown

    // Apps playing, then apps recording; not the shell's own visualiser, which
    // listens to the output
    readonly property var apps: {
        const real = Audio.streams.filter(s => s.properties["stream.capture.sink"] !== "true" && s.properties["application.process.binary"] !== "qs" && s.properties["application.process.binary"] !== "quickshell");
        return [...real.filter(s => !Audio.isRecording(s)), ...real.filter(s => Audio.isRecording(s))];
    }

    // The channel whose device list is open, or null
    property ChannelStrip picking: null

    signal closeRequested
    signal hidden

    onShownChanged: {
        picking = null;
        if (shown)
            keys.forceActiveFocus();
    }

    // Clicking anywhere else closes it
    MouseArea {
        anchors.fill: parent
        onClicked: root.closeRequested()
    }

    Item {
        id: keys

        focus: true
        Keys.onEscapePressed: {
            if (root.picking)
                root.picking = null;
            else
                root.closeRequested();
        }
    }

    Elevation {
        anchors.fill: sheet
        radius: sheet.radius
        opacity: sheet.opacity
        scale: sheet.scale
        level: 3
    }

    StyledRect {
        id: sheet

        readonly property real margin: Tokens.padding.large
        readonly property int channels: 2 + root.apps.length

        anchors.centerIn: parent
        width: Math.min(root.width - margin * 2, Tokens.padding.large * 2 + channels * 168 + (channels - 1) * Tokens.spacing.medium + Tokens.spacing.large * 2 + 1)
        height: Math.min(root.height - margin * 2, 520)
        radius: Tokens.rounding.extraLarge
        color: Colours.tPalette.m3surfaceContainerLow

        opacity: root.shown ? 1 : 0
        scale: root.shown ? 1 : 0.94

        onOpacityChanged: {
            if (opacity === 0 && !root.shown)
                root.hidden();
        }

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }

        Behavior on scale {
            Anim {
                type: Anim.DefaultSpatial
            }
        }

        // Swallow clicks so they don't close the mixer
        MouseArea {
            anchors.fill: parent
            onClicked: root.picking = null
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Tokens.padding.large
            spacing: Tokens.spacing.medium

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.medium

                MaterialIcon {
                    text: "tune"
                    color: Colours.palette.m3primary
                    font: Tokens.font.icon.large
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        text: Tr.tr("Mixer")
                        font: Tokens.font.title.medium
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.apps.length === 0 ? Tr.tr("No apps are using sound") : (root.apps.length === 1 ? Tr.tr("1 app is using sound") : Tr.tr("%1 apps are using sound").arg(root.apps.length))
                        elide: Text.ElideRight
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.small
                    }
                }

                IconButton {
                    type: IconButton.Text
                    icon: "close"
                    onClicked: root.closeRequested()
                }
            }

            Flickable {
                id: flick

                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: strips.implicitWidth
                contentHeight: height
                flickableDirection: Flickable.HorizontalFlick
                boundsBehavior: Flickable.StopAtBounds
                clip: true

                RowLayout {
                    id: strips

                    height: flick.height
                    spacing: Tokens.spacing.medium

                    ChannelStrip {
                        Layout.fillHeight: true
                        node: Audio.sink
                        master: true
                        masterTitle: Tr.tr("Output")
                        onPickDevice: root.picking = root.picking === this ? null : this
                    }

                    ChannelStrip {
                        Layout.fillHeight: true
                        node: Audio.source
                        master: true
                        masterTitle: Tr.tr("Microphone")
                        onPickDevice: root.picking = root.picking === this ? null : this
                    }

                    StyledRect {
                        Layout.fillHeight: true
                        Layout.leftMargin: Tokens.spacing.large - Tokens.spacing.medium
                        Layout.rightMargin: Tokens.spacing.large - Tokens.spacing.medium
                        implicitWidth: 1
                        color: Colours.palette.m3outlineVariant
                    }

                    Repeater {
                        model: root.apps

                        ChannelStrip {
                            id: strip

                            required property PwNode modelData

                            Layout.fillHeight: true
                            node: modelData
                            onPickDevice: root.picking = root.picking === strip ? null : strip
                        }
                    }
                }
            }
        }

        // Where the picked channel can go: outputs, or microphones for one that records
        Elevation {
            id: picker

            readonly property ChannelStrip strip: root.picking
            readonly property var devices: strip ? (strip.recording ? Audio.sources : Audio.sinks) : []
            readonly property point at: {
                if (!strip)
                    return Qt.point(0, 0);
                flick.contentX; // reposition when scrolled
                const p = strip.chip.mapToItem(sheet, 0, 0);
                return Qt.point(p.x, p.y);
            }

            visible: opacity > 0
            opacity: strip ? 1 : 0
            level: 2
            radius: Tokens.rounding.large
            width: Math.max(240, list.implicitWidth + Tokens.padding.extraSmall * 2)
            height: list.implicitHeight + Tokens.padding.extraSmall * 2
            x: Math.max(Tokens.padding.small, Math.min(sheet.width - width - Tokens.padding.small, at.x))
            // Above the chip: it sits at the bottom of the channel
            y: Math.max(Tokens.padding.small, at.y - height - Tokens.spacing.small)

            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
            }

            StyledRect {
                anchors.fill: parent
                radius: parent.radius
                color: Colours.palette.m3surfaceContainerHigh

                ColumnLayout {
                    id: list

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.extraSmall
                    spacing: 0

                    Repeater {
                        model: picker.devices

                        StyledRect {
                            id: option

                            required property PwNode modelData
                            readonly property bool current: modelData === picker.strip?.device

                            Layout.fillWidth: true
                            implicitWidth: optionRow.implicitWidth + Tokens.padding.medium * 2
                            implicitHeight: optionRow.implicitHeight + Tokens.padding.medium * 2
                            radius: Tokens.rounding.medium
                            color: Qt.alpha(Colours.palette.m3tertiaryContainer, current ? 1 : 0)

                            StateLayer {
                                radius: parent.radius
                                color: option.current ? Colours.palette.m3onTertiaryContainer : Colours.palette.m3onSurface
                                onClicked: {
                                    const strip = picker.strip;
                                    if (strip.master) {
                                        if (strip.recording)
                                            Audio.setAudioSource(option.modelData);
                                        else
                                            Audio.setAudioSink(option.modelData);
                                    } else {
                                        Audio.moveStream(strip.node, option.modelData);
                                    }
                                    root.picking = null;
                                }
                            }

                            RowLayout {
                                id: optionRow

                                anchors.fill: parent
                                anchors.margins: Tokens.padding.medium
                                spacing: Tokens.spacing.small

                                MaterialIcon {
                                    text: Audio.deviceIcon(option.modelData)
                                    color: option.current ? Colours.palette.m3onTertiaryContainer : Colours.palette.m3onSurfaceVariant
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: Audio.deviceName(option.modelData)
                                        color: option.current ? Colours.palette.m3onTertiaryContainer : Colours.palette.m3onSurface
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        Layout.maximumWidth: 320
                                        visible: text !== "" && text !== Audio.deviceName(option.modelData)
                                        text: option.modelData.description
                                        elide: Text.ElideRight
                                        color: option.current ? Colours.palette.m3onTertiaryContainer : Colours.palette.m3onSurfaceVariant
                                        font: Tokens.font.body.small
                                    }
                                }

                                MaterialIcon {
                                    visible: option.current
                                    text: "check"
                                    color: Colours.palette.m3onTertiaryContainer
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
