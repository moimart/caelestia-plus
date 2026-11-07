pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services

Item {
    id: root

    required property PopoutState popouts

    implicitWidth: Tokens.sizes.bar.audioWidth
    implicitHeight: layout.implicitHeight + Tokens.padding.medium * 2

    ButtonGroup {
        id: sinks
    }

    ButtonGroup {
        id: sources
    }

    ColumnLayout {
        id: layout

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Tokens.spacing.medium

        StyledText {
            text: Tr.trCtx("Output device", "audio output device")
            font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
        }

        Repeater {
            model: Audio.sinks

            StyledRadioButton {
                id: control

                required property PwNode modelData

                Layout.fillWidth: true
                ButtonGroup.group: sinks
                checked: Audio.sink?.id === modelData.id
                onClicked: Audio.setAudioSink(modelData)
                text: modelData.description
            }
        }

        StyledText {
            Layout.topMargin: Tokens.spacing.medium
            text: Tr.trCtx("Input device", "audio input device")
            font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
        }

        Repeater {
            model: Audio.sources

            StyledRadioButton {
                required property PwNode modelData

                Layout.fillWidth: true
                ButtonGroup.group: sources
                checked: Audio.source?.id === modelData.id
                onClicked: Audio.setAudioSource(modelData)
                text: modelData.description
            }
        }

        StyledText {
            Layout.topMargin: Tokens.spacing.medium
            text: Audio.muted ? Tr.tr("Volume (muted)") : Tr.tr("Volume (%1%)").arg(Math.round(Audio.volume * 100))
            font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
        }

        CustomMouseArea {
            Layout.fillWidth: true
            implicitHeight: Tokens.padding.medium * 3

            onWheel: event => {
                if (event.angleDelta.y > 0)
                    Audio.incrementVolume();
                else if (event.angleDelta.y < 0)
                    Audio.decrementVolume();
            }

            StyledSlider {
                anchors.left: parent.left
                anchors.right: parent.right
                implicitHeight: parent.implicitHeight

                value: Audio.volume
                onInteraction: value => Audio.setVolume(value)
            }
        }

        // Each app's own volume, folded away until asked for (remembered)
        Item {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.small
            implicitHeight: appsHeader.implicitHeight + Tokens.padding.small * 2

            StateLayer {
                radius: Tokens.rounding.full
                color: Colours.palette.m3onSurface
                onClicked: Audio.popoutAppsExpanded = !Audio.popoutAppsExpanded
            }

            RowLayout {
                id: appsHeader

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: Tokens.padding.small
                anchors.rightMargin: Tokens.padding.small
                anchors.verticalCenter: parent.verticalCenter
                spacing: Tokens.spacing.small

                MaterialIcon {
                    text: "apps"
                    color: Colours.palette.m3onSurfaceVariant
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Audio.streams.length > 0 ? Tr.tr("App volumes (%1)").arg(Audio.streams.length) : Tr.tr("App volumes")
                    font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
                }

                MaterialIcon {
                    text: "expand_more"
                    color: Colours.palette.m3onSurfaceVariant
                    rotation: Audio.popoutAppsExpanded ? 180 : 0

                    Behavior on rotation {
                        Anim {}
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: Audio.popoutAppsExpanded
            spacing: Tokens.spacing.small

            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: Tokens.padding.small
                visible: Audio.streams.length === 0
                text: Tr.tr("No apps playing audio")
                color: Colours.palette.m3outline
                font: Tokens.font.body.small
            }

            Repeater {
                model: ScriptModel {
                    values: [...Audio.streams]
                }

                RowLayout {
                    id: app

                    required property PwNode modelData
                    readonly property bool muted: Audio.getStreamMuted(modelData)
                    readonly property real volume: Audio.getStreamVolume(modelData)

                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    AppIcon {
                        Layout.alignment: Qt.AlignVCenter
                        implicitSize: Math.round(Tokens.font.icon.large.pointSize * 1.4)
                        entry: DesktopEntries.heuristicLookup(app.modelData?.properties["application.process.binary"] || Audio.getStreamName(app.modelData))
                        opacity: app.muted ? 0.5 : 1
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        // Room for the slider's handle, taller than its track
                        spacing: Tokens.spacing.small

                        RowLayout {
                            Layout.fillWidth: true

                            StyledText {
                                Layout.fillWidth: true
                                text: Audio.getStreamName(app.modelData)
                                elide: Text.ElideRight
                                font: Tokens.font.body.small
                            }

                            StyledText {
                                text: app.muted ? Tr.tr("Muted") : `${Math.round(app.volume * 100)}%`
                                color: Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.label.small
                            }
                        }

                        CustomMouseArea {
                            Layout.fillWidth: true
                            implicitHeight: Tokens.padding.medium * 2

                            onWheel: event => {
                                const step = GlobalConfig.services.audioIncrement;
                                if (event.angleDelta.y > 0)
                                    Audio.setStreamVolume(app.modelData, app.volume + step);
                                else if (event.angleDelta.y < 0)
                                    Audio.setStreamVolume(app.modelData, app.volume - step);
                            }

                            StyledSlider {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                implicitHeight: parent.implicitHeight
                                opacity: app.muted ? 0.5 : 1

                                value: app.volume
                                onInteraction: value => Audio.setStreamVolume(app.modelData, value)
                            }
                        }
                    }

                    IconButton {
                        Layout.alignment: Qt.AlignVCenter
                        type: IconButton.Text
                        icon: app.muted ? "volume_off" : "volume_up"
                        onClicked: Audio.setStreamMuted(app.modelData, !app.muted)
                    }
                }
            }
        }

        IconTextButton {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.medium
            inactiveColour: Colours.palette.m3primaryContainer
            inactiveOnColour: Colours.palette.m3onPrimaryContainer
            verticalPadding: Tokens.padding.extraSmall
            text: Tr.tr("Open settings")
            icon: "settings"

            onClicked: root.popouts.detachRequested("audio")
        }
    }
}
