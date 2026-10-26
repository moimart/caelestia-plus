pragma ComponentBehavior: Bound

import QtQuick

// The daruma from ~/.config/caelestia/assets/daruma-source.svg, winking as
// ever, with its painted eye following the pointer. It winks that eye too now
// and then, and rests with both shut while the pointer is still.
// The images come from make-art.py; the eye geometry below matches it.
Item {
    id: root

    // From the widget host
    property point cursor: Qt.point(width / 2, height / 2)

    // The painted eye, as fractions of the image (712, 392 in a 1024 render)
    readonly property real eyeX: width * 0.6953
    readonly property real eyeY: height * 0.3828
    readonly property real pupilR: width * 0.049
    readonly property real travel: width * 0.036
    readonly property point look: {
        const dx = cursor.x - eyeX;
        const dy = cursor.y - eyeY;
        const d = Math.sqrt(dx * dx + dy * dy);
        const s = d > travel ? travel / d : 1;
        return Qt.point(dx * s, dy * s);
    }

    property real wink // 0 open, 1 shut
    property bool resting
    // Resting shut eases closed slowly and opens quickly
    property real rest: resting ? 1 : 0
    readonly property real closed: Math.max(wink, rest)

    onCursorChanged: {
        resting = false;
        idle.restart();
    }

    Behavior on rest {
        NumberAnimation {
            duration: root.resting ? 900 : 150
            easing.type: Easing.InOutSine
        }
    }

    Image {
        anchors.fill: parent
        source: "daruma-open.png"
        sourceSize: Qt.size(640, 640)
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
    }

    Rectangle {
        width: root.pupilR * 2
        height: width
        radius: width / 2
        x: root.eyeX - root.pupilR + root.look.x
        y: root.eyeY - root.pupilR + root.look.y
        color: "#1d1517"
        opacity: 1 - root.closed

        Behavior on x {
            SmoothedAnimation {
                velocity: root.width * 0.5
            }
        }

        Behavior on y {
            SmoothedAnimation {
                velocity: root.width * 0.5
            }
        }
    }

    // Both eyes shut, faded in over the open one
    Image {
        anchors.fill: parent
        source: "daruma-closed.png"
        sourceSize: Qt.size(640, 640)
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
        opacity: root.closed
    }

    // An occasional wink
    Timer {
        running: true
        interval: 9000
        onTriggered: {
            if (!root.resting)
                winkAnim.restart();
            interval = 8000 + Math.random() * 9000;
            restart();
        }
    }

    SequentialAnimation {
        id: winkAnim

        NumberAnimation {
            target: root
            property: "wink"
            to: 1
            duration: 90
            easing.type: Easing.InCubic
        }
        PauseAnimation {
            duration: 160
        }
        NumberAnimation {
            target: root
            property: "wink"
            to: 0
            duration: 160
            easing.type: Easing.OutCubic
        }
    }

    // Pointer still for a while: rest with both eyes shut until it moves
    Timer {
        id: idle

        running: true
        interval: 20000
        onTriggered: root.resting = true
    }
}
