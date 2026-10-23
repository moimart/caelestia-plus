import QtQuick
import Caelestia.Config
import qs.components
import qs.services

// A whole shortcut as keycaps joined by thin plus signs
Row {
    id: root

    required property var caps
    property bool compact

    spacing: Tokens.spacing.extraSmall

    Repeater {
        model: root.caps

        Row {
            id: capItem

            required property var modelData
            required property int index

            spacing: root.spacing

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                visible: capItem.index > 0
                text: "+"
                color: Colours.palette.m3outline
                font: Tokens.font.label.small
            }

            KeyCap {
                cap: capItem.modelData
                compact: root.compact
            }
        }
    }
}
