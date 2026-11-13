import QtQuick
import Caelestia.Config
import qs.components
import qs.services

// Left to right, filling out from the centre. It snaps to the centre, where
// the app plays as it is; double-click to go back there.
Item {
    id: root

    // -1 left .. 1 right
    property real value
    readonly property bool centred: Math.abs(value) < 0.05

    signal moved(value: real)

    function valueAt(x: real): real {
        const v = (x - track.x) / track.width * 2 - 1;
        return Math.abs(v) < 0.08 ? 0 : Math.max(-1, Math.min(1, v));
    }

    implicitHeight: 28

    StyledText {
        id: left

        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: "L"
        color: root.value < -0.05 ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.small
    }

    StyledText {
        id: right

        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: "R"
        color: root.value > 0.05 ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.small
    }

    StyledRect {
        id: track

        anchors.left: left.right
        anchors.right: right.left
        anchors.leftMargin: Tokens.spacing.small
        anchors.rightMargin: Tokens.spacing.small
        anchors.verticalCenter: parent.verticalCenter
        implicitHeight: 6
        radius: Tokens.rounding.full
        color: Colours.palette.m3secondaryContainer

        // From the centre to the handle
        StyledRect {
            readonly property real centre: track.width / 2
            readonly property real at: (root.value + 1) / 2 * track.width

            x: Math.min(centre, at)
            width: Math.abs(at - centre)
            height: parent.height
            radius: parent.radius
            color: Colours.palette.m3primary
        }

        // The centre mark
        StyledRect {
            anchors.centerIn: parent
            implicitWidth: 2
            implicitHeight: 12
            radius: 1
            color: Colours.palette.m3outline
        }

        StyledRect {
            x: (root.value + 1) / 2 * track.width - width / 2
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: 16
            implicitHeight: 16
            radius: Tokens.rounding.full
            color: root.centred ? Colours.palette.m3onSurfaceVariant : Colours.palette.m3primary

            Behavior on x {
                enabled: !drag.pressed

                Anim {}
            }
        }
    }

    MouseArea {
        id: drag

        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        preventStealing: true

        onPressed: event => root.moved(root.valueAt(event.x))
        onPositionChanged: event => {
            if (pressed)
                root.moved(root.valueAt(event.x));
        }
        onDoubleClicked: root.moved(0)
        onWheel: event => root.moved(Math.abs(root.value + (event.angleDelta.y > 0 ? 0.1 : -0.1)) < 0.05 ? 0 : root.value + (event.angleDelta.y > 0 ? 0.1 : -0.1))
    }
}
