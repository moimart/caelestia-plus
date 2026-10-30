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

    // Palette: the title and Done above the plugins, which wrap onto more rows
    // when the screen is too narrow for one (and more plugins never push it
    // off the screen)
    StyledRect {
        id: panel

        // The most it may take, and what one row of plugins wants
        readonly property real room: root.width - Tokens.padding.extraExtraLarge * 4
        readonly property real chipsWidth: {
            let w = 0;
            let n = 0;
            for (const c of chips.children) {
                if (c.visible && c.implicitWidth > 0) {
                    w += c.implicitWidth;
                    n++;
                }
            }
            return w + Math.max(0, n - 1) * chips.spacing;
        }

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Tokens.padding.extraExtraLarge * 1.5
        implicitWidth: Math.min(room, Math.max(header.implicitWidth, chipsWidth) + Tokens.padding.extraLarge * 2)
        implicitHeight: content.implicitHeight + Tokens.padding.large * 2
        radius: Tokens.rounding.extraLarge
        color: Colours.tPalette.m3surfaceContainer

        ColumnLayout {
            id: content

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Tokens.padding.extraLarge
            anchors.rightMargin: Tokens.padding.extraLarge
            spacing: Tokens.spacing.medium

            RowLayout {
                id: header

                Layout.fillWidth: true
                spacing: Tokens.spacing.large

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: Tr.tr("Desktop widgets")
                        font: Tokens.font.title.medium
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Tr.tr("Drag to move · corners to resize · Esc when done")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.medium
                        elide: Text.ElideRight
                    }
                }

                TextButton {
                    text: Tr.tr("Done")
                    type: TextButton.Filled
                    onClicked: Widgets.editing = false
                }
            }

            Flow {
                id: chips

                Layout.fillWidth: true
                spacing: Tokens.spacing.small

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
            }
        }
    }
}
