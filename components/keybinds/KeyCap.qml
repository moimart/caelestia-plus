import QtQuick
import Caelestia.Config
import qs.components
import qs.services

// One key of a shortcut, drawn as a keycap: modifiers are neutral, the key
// itself is tinted. `cap` is { label, icon?, mod? } from hyprbinds.py.
StyledRect {
    id: root

    required property var cap
    property bool compact

    readonly property bool isMod: cap.mod ?? false
    readonly property color face: isMod ? Colours.palette.m3surfaceContainerHighest : Colours.palette.m3secondaryContainer
    readonly property color ink: isMod ? Colours.palette.m3onSurfaceVariant : Colours.palette.m3onSecondaryContainer

    implicitHeight: Math.round(Tokens.font.label.medium.pointSize * (compact ? 2.1 : 2.4))
    implicitWidth: Math.max(implicitHeight, row.implicitWidth + Tokens.padding.small * 2)
    radius: Tokens.rounding.small
    color: Qt.darker(face, Colours.light ? 1.12 : 1.35)

    // The keycap's face sits slightly raised over its darker edge
    StyledRect {
        anchors.fill: parent
        anchors.bottomMargin: 2
        radius: parent.radius
        color: root.face

        Row {
            id: row

            anchors.centerIn: parent
            spacing: Tokens.spacing.extraSmall

            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                visible: !!root.cap.icon
                text: root.cap.icon ?? ""
                color: root.ink
                fill: 1
                fontStyle: Tokens.font.icon.small
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                visible: !root.cap.icon || !root.compact
                text: root.cap.label
                color: root.ink
                font: root.isMod ? Tokens.font.label.small : Tokens.font.label.medium
            }
        }
    }
}
