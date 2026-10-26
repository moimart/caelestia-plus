import QtQuick
import Caelestia.Config
import qs.components
import qs.services

// A minimal widget plugin. The root item fills the space the widget is given;
// the properties below are optional and filled in by the shell if declared.
Item {
    id: root

    property bool editing // true while you place it (Super+Ctrl+W)
    property var settings: ({}) // this widget's settings from widgets.json

    StyledText {
        anchors.fill: parent
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: Time.format(root.settings.format ?? "hh:mm")
        color: Colours.palette.m3onSurface
        font: Tokens.font.clock.size(Math.max(8, root.height * 0.45)).build()
    }
}
