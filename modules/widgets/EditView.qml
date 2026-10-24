pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services

// The editor on one screen: the widgets over a dimmed desktop, with a palette
// to add more. Esc or Done to finish.
Item {
    id: root

    required property ShellScreen screen

    focus: true
    Keys.onEscapePressed: Widgets.editing = false
    Keys.onReturnPressed: Widgets.editing = false

    StyledRect {
        anchors.fill: parent
        color: Qt.alpha(Colours.palette.m3scrim, 0.5)
    }

    Repeater {
        model: ScriptModel {
            values: Widgets.instancesOn(root.screen.name).map(i => i.uid)
        }

        EditFrame {
            required property string modelData

            uid: modelData
            screen: root.screen
        }
    }

    // Palette
    StyledRect {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Tokens.padding.extraExtraLarge * 1.5
        implicitWidth: palette.implicitWidth + Tokens.padding.extraLarge * 2
        implicitHeight: palette.implicitHeight + Tokens.padding.large * 2
        radius: Tokens.rounding.extraLarge
        color: Colours.tPalette.m3surfaceContainer

        RowLayout {
            id: palette

            anchors.centerIn: parent
            spacing: Tokens.spacing.large

            ColumnLayout {
                spacing: 0

                StyledText {
                    text: Tr.tr("Desktop widgets")
                    font: Tokens.font.title.medium
                }

                StyledText {
                    text: Tr.tr("Drag to move · corners to resize · Esc when done")
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.medium
                }
            }

            Rectangle {
                Layout.fillHeight: true
                implicitWidth: 1
                color: Colours.palette.m3outlineVariant
            }

            Repeater {
                model: Widgets.plugins

                IconTextButton {
                    required property var modelData

                    icon: modelData.icon
                    text: modelData.name
                    type: TextButton.Tonal
                    onClicked: Widgets.add(modelData.id, root.screen)
                }
            }

            StyledText {
                visible: Widgets.plugins.length === 0
                text: Tr.tr("No widget plugins found")
                color: Colours.palette.m3outline
            }

            TextButton {
                text: Tr.tr("Done")
                type: TextButton.Filled
                onClicked: Widgets.editing = false
            }
        }
    }
}
