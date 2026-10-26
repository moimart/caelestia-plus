pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.containers
import qs.components.controls
import qs.components.effects
import qs.services

// "Keep these display settings?" on every screen while a display change waits
// to be kept, so it can be answered from whichever screen still works. It
// undoes the change by itself when the countdown runs out.
Variants {
    model: Quickshell.screens

    LazyLoader {
        id: loader

        required property ShellScreen modelData

        active: Displays.pending !== null

        StyledWindow {
            screen: loader.modelData
            name: "display-confirm"
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

            anchors.top: true
            margins.top: Math.round(loader.modelData.height / 3)
            implicitWidth: card.implicitWidth + 40
            implicitHeight: card.implicitHeight + 40

            Elevation {
                anchors.fill: card
                radius: card.radius
                level: 3
            }

            StyledRect {
                id: card

                anchors.centerIn: parent
                implicitWidth: Math.max(380, content.implicitWidth + Tokens.padding.extraLarge * 2)
                implicitHeight: content.implicitHeight + Tokens.padding.extraLarge * 2
                radius: Tokens.rounding.extraLarge
                color: Colours.palette.m3surfaceContainerHigh

                ColumnLayout {
                    id: content

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.extraLarge
                    spacing: Tokens.spacing.medium

                    RowLayout {
                        spacing: Tokens.spacing.medium

                        MaterialIcon {
                            text: "monitor"
                            color: Colours.palette.m3primary
                            fontStyle: Tokens.font.icon.large
                        }

                        ColumnLayout {
                            spacing: 0

                            StyledText {
                                text: Tr.tr("Keep these display settings?")
                                font: Tokens.font.title.medium
                            }

                            StyledText {
                                text: Tr.tr("Reverting in %1 s").arg(Displays.countdown)
                                color: Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.body.small
                            }
                        }
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignRight
                        spacing: Tokens.spacing.small

                        TextButton {
                            text: Tr.tr("Revert")
                            type: TextButton.Text
                            onClicked: Displays.revert()
                        }

                        TextButton {
                            text: Tr.tr("Keep")
                            type: TextButton.Filled
                            onClicked: Displays.keep()
                        }
                    }
                }
            }
        }
    }
}
