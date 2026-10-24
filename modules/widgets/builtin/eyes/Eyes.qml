pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs.services

// Two eyes that follow the pointer, abstract and drawn in the scheme's text
// colour. settings.style picks the drawing:
//   "orbit"  a hairline circle with a solid disc drifting inside (default)
//   "almond" a fine almond outline with a small ringed pupil
//   "dots"   just two dots that glance about
// They blink by narrowing, and settle half-closed when the pointer rests.
Item {
    id: root

    // From the widget host
    property point cursor: Qt.point(width / 2, height / 2)
    property bool editing
    property var settings: ({})

    readonly property string style: settings.style ?? "orbit"
    readonly property color ink: Colours.palette.m3onSurface
    readonly property real stroke: Math.max(1, Math.min(width / 2, height) * 0.03)
    readonly property real gap: Math.min(width, height) * 0.22
    property real blink
    property real drowse

    onCursorChanged: {
        if (drowse > 0)
            wake.restart();
        idle.restart();
    }

    Row {
        anchors.fill: parent
        spacing: root.gap

        Eye {
            width: (root.width - root.gap) / 2
            height: root.height
        }

        Eye {
            width: (root.width - root.gap) / 2
            height: root.height
        }
    }

    Timer {
        running: true
        interval: 4000
        onTriggered: {
            blinkAnim.loops = Math.random() < 0.15 ? 2 : 1;
            blinkAnim.restart();
            interval = 4000 + Math.random() * 6000;
            restart();
        }
    }

    SequentialAnimation {
        id: blinkAnim

        NumberAnimation {
            target: root
            property: "blink"
            to: 1
            duration: 90
            easing.type: Easing.InCubic
        }
        NumberAnimation {
            target: root
            property: "blink"
            to: 0
            duration: 160
            easing.type: Easing.OutCubic
        }
    }

    Timer {
        id: idle

        running: true
        interval: 30000
        onTriggered: doze.start()
    }

    NumberAnimation {
        id: doze

        target: root
        property: "drowse"
        to: 0.6
        duration: 3000
        easing.type: Easing.InOutSine
    }

    NumberAnimation {
        id: wake

        target: root
        property: "drowse"
        to: 0
        duration: 220
        easing.type: Easing.OutCubic
        onStarted: doze.stop()
    }

    component Eye: Item {
        id: eye

        readonly property real closed: Math.max(root.blink, root.drowse)
        readonly property real unit: Math.min(width, height)
        // Almond's half-height: wide and low, like an eye, whatever the box
        readonly property real almondHalf: Math.min(height / 2 - root.stroke, width * 0.24)
        // Size of what moves, and how far it may go from the centre
        readonly property real dot: root.style === "orbit" ? unit * 0.42 : root.style === "dots" ? unit * 0.34 : almondHalf * 0.5
        readonly property real travelX: Math.max(0, root.style === "almond" ? width * 0.22 : width / 2 - dot / 2 - root.stroke * (root.style === "orbit" ? 2.5 : 0))
        readonly property real travelY: Math.max(0, root.style === "almond" ? almondHalf * 0.22 : height / 2 - dot / 2 - root.stroke * (root.style === "orbit" ? 2.5 : 0))
        readonly property point look: {
            const dx = root.cursor.x - (x + width / 2);
            const dy = root.cursor.y - (y + height / 2);
            const k = (travelX > 0 ? (dx / travelX) ** 2 : 0) + (travelY > 0 ? (dy / travelY) ** 2 : 0);
            const s = k > 1 ? 1 / Math.sqrt(k) : 1;
            return Qt.point(dx * s, dy * s);
        }

        transform: Scale {
            origin.y: eye.height / 2
            yScale: 1 - eye.closed * (root.style === "dots" ? 0.8 : 0.96)
        }

        // Almond: two arcs meeting at sharp corners
        Shape {
            anchors.fill: parent
            visible: root.style === "almond"
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: Qt.alpha(root.ink, 0.7)
                strokeWidth: root.stroke
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                startX: root.stroke
                startY: eye.height / 2

                // Control points at twice the half-height, so the curve's
                // extremes land on the almond's edges
                PathQuad {
                    x: eye.width - root.stroke
                    y: eye.height / 2
                    controlX: eye.width / 2
                    controlY: eye.height / 2 - eye.almondHalf * 2
                }
                PathQuad {
                    x: root.stroke
                    y: eye.height / 2
                    controlX: eye.width / 2
                    controlY: eye.height / 2 + eye.almondHalf * 2
                }
            }
        }

        // Orbit: a hairline circle
        Shape {
            anchors.fill: parent
            visible: root.style === "orbit"
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: Qt.alpha(root.ink, 0.5)
                strokeWidth: root.stroke
                fillColor: "transparent"

                PathAngleArc {
                    centerX: eye.width / 2
                    centerY: eye.height / 2
                    radiusX: eye.width / 2 - root.stroke
                    radiusY: eye.height / 2 - root.stroke
                    startAngle: 0
                    sweepAngle: 360
                }
            }
        }

        // What follows the pointer
        Item {
            width: eye.dot
            height: width
            x: (eye.width - width) / 2 + eye.look.x
            y: (eye.height - height) / 2 + eye.look.y

            Behavior on x {
                SmoothedAnimation {
                    velocity: eye.width * 8
                }
            }

            Behavior on y {
                SmoothedAnimation {
                    velocity: eye.height * 8
                }
            }

            // Almond's iris: a fine ring around the pupil
            Rectangle {
                anchors.centerIn: parent
                visible: root.style === "almond"
                width: parent.width * 2.1
                height: width
                radius: width / 2
                color: "transparent"
                border.width: root.stroke
                border.color: Qt.alpha(root.ink, 0.45)
            }

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: Qt.alpha(root.ink, root.style === "orbit" ? 0.8 : 0.9)
            }
        }
    }
}
