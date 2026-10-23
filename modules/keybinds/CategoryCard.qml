pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.keybinds
import qs.services

// A card of shortcuts under one heading from the config (a section banner
// comment, or the file the binds live in)
StyledRect {
    id: root

    required property string name
    required property string icon
    required property var binds
    property bool unbound

    implicitHeight: column.implicitHeight + Tokens.padding.large * 2
    radius: Tokens.rounding.large
    color: Colours.tPalette.m3surfaceContainer

    ColumnLayout {
        id: column

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Tokens.padding.large
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.small
            Layout.rightMargin: Tokens.padding.small
            Layout.bottomMargin: Tokens.spacing.small
            spacing: Tokens.spacing.small

            MaterialIcon {
                text: root.icon
                color: Colours.palette.m3primary
                fill: 1
                fontStyle: Tokens.font.icon.medium
            }

            StyledText {
                Layout.fillWidth: true
                text: root.name
                color: Colours.palette.m3onSurface
                font: Tokens.font.title.small
                elide: Text.ElideRight
            }

            StyledText {
                text: root.binds.length
                color: Colours.palette.m3outline
                font: Tokens.font.label.medium
            }
        }

        Repeater {
            model: root.binds

            BindRow {
                required property var modelData

                Layout.fillWidth: true
                bind: modelData
                unbound: root.unbound
            }
        }
    }
}
