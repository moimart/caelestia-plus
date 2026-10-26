pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.services
import "arrange.js" as Arrange

// The displays as they sit on the desktop, scaled down. Click one to select
// it; drag one to move it: it snaps against the edge of another, so the
// pointer can always cross between them, like macOS's arrangement.
Item {
    id: root

    property string selected

    // Displays that take part in the layout: on, and not mirroring another
    readonly property var placed: Displays.monitors.filter(m => !m.disabled && (!m.mirrorOf || m.mirrorOf === "none"))
    readonly property var rects: placed.map(m => {
        const size = Displays.logicalSize(m);
        return {
            name: m.name,
            x: m.x,
            y: m.y,
            width: size.width,
            height: size.height,
            m: m
        };
    })
    readonly property rect bounds: {
        if (rects.length === 0)
            return Qt.rect(0, 0, 1, 1);
        const x0 = Math.min(...rects.map(r => r.x)), y0 = Math.min(...rects.map(r => r.y));
        const x1 = Math.max(...rects.map(r => r.x + r.width)), y1 = Math.max(...rects.map(r => r.y + r.height));
        return Qt.rect(x0, y0, x1 - x0, y1 - y0);
    }
    // The layout with room around it to drag a display to any side
    readonly property real room: Math.max(bounds.width, bounds.height) * 0.15
    readonly property rect view: Qt.rect(bounds.x - room, bounds.y - room, bounds.width + room * 2, bounds.height + room * 2)
    readonly property real pad: Tokens.padding.large
    readonly property real factor: Math.min((width - pad * 2) / view.width, (height - pad * 2) / view.height)
    readonly property point origin: Qt.point((width - view.width * factor) / 2, (height - view.height * factor) / 2)

    // Displays the pointer can't get to from the one you're on
    readonly property var isolated: Arrange.unreachable(rects, Hypr.focusedMonitor?.name ?? "")

    // While dragging: the display, and where it would land (desktop pixels)
    property string dragging
    property point landing

    signal picked(name: string)

    function toCanvas(x: real, y: real): point {
        return Qt.point(origin.x + (x - view.x) * factor, origin.y + (y - view.y) * factor);
    }

    function toDesktop(x: real, y: real): point {
        return Qt.point(view.x + (x - origin.x) / factor, view.y + (y - origin.y) / factor);
    }

    // Where a display dropped at (x, y), in desktop pixels, ends up
    // (arrange.js): flush against an edge within 24 px on screen, lined up
    // within 10; further away, where you dropped it
    function snap(name: string, x: real, y: real): point {
        const p = Arrange.snap(rects, name, x, y, 24 / factor, 10 / factor);
        return Qt.point(p.x, p.y);
    }

    // As tall as the layout's shape needs (stacked displays get more room),
    // within reason; more displays just get smaller
    implicitHeight: Math.max(200, Math.min(440, (width - pad * 2) * view.height / view.width + pad * 2))

    // Where the dragged display will land
    StyledRect {
        readonly property var me: root.rects.find(r => r.name === root.dragging) ?? null
        readonly property point at: root.toCanvas(root.landing.x, root.landing.y)

        visible: !!me
        x: at.x
        y: at.y
        width: (me?.width ?? 0) * root.factor
        height: (me?.height ?? 0) * root.factor
        radius: Tokens.rounding.small
        color: "transparent"
        border.width: 2
        border.color: Colours.palette.m3primary
        opacity: 0.8
    }

    Repeater {
        model: root.rects

        StyledRect {
            id: screenRect

            required property var modelData
            readonly property bool isSelected: root.selected === modelData.name
            readonly property point home: root.toCanvas(modelData.x, modelData.y)

            function landingFor(): point {
                const d = root.toDesktop(x, y);
                return root.snap(modelData.name, d.x, d.y);
            }

            x: home.x
            y: home.y
            width: Math.max(8, modelData.width * root.factor)
            height: Math.max(8, modelData.height * root.factor)
            z: mover.drag.active ? 2 : (isSelected ? 1 : 0)
            radius: Tokens.rounding.small
            color: isSelected ? Colours.palette.m3primaryContainer : Colours.palette.m3surfaceContainerHighest
            border.width: isSelected ? 2 : 0
            border.color: Colours.palette.m3primary
            opacity: mover.drag.active ? 0.85 : 1

            onXChanged: {
                if (mover.drag.active)
                    root.landing = landingFor();
            }
            onYChanged: {
                if (mover.drag.active)
                    root.landing = landingFor();
            }

            Column {
                anchors.centerIn: parent
                width: parent.width - Tokens.padding.small * 2
                spacing: 0

                StyledText {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: screenRect.modelData.name
                    color: screenRect.isSelected ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurface
                    font: screenRect.height > 36 ? Tokens.font.label.large : Tokens.font.label.small
                    elide: Text.ElideRight
                }

                StyledText {
                    width: parent.width
                    visible: screenRect.height > 48
                    horizontalAlignment: Text.AlignHCenter
                    text: `${screenRect.modelData.m.width} × ${screenRect.modelData.m.height}`
                    color: screenRect.isSelected ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.small
                    elide: Text.ElideRight
                }
            }

            MouseArea {
                id: mover

                anchors.fill: parent
                cursorShape: root.rects.length > 1 ? (pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor) : Qt.PointingHandCursor
                drag.target: root.rects.length > 1 ? screenRect : null
                drag.threshold: 4
                // Kept inside the canvas
                drag.minimumX: 0
                drag.minimumY: 0
                drag.maximumX: root.width - screenRect.width
                drag.maximumY: root.height - screenRect.height
                drag.onActiveChanged: {
                    if (drag.active) {
                        root.landing = screenRect.landingFor();
                        root.dragging = screenRect.modelData.name;
                    }
                }
                onPressed: root.picked(screenRect.modelData.name)
                onReleased: {
                    if (root.dragging !== screenRect.modelData.name)
                        return;
                    const p = screenRect.landingFor();
                    root.dragging = "";
                    if (p.x === screenRect.modelData.x && p.y === screenRect.modelData.y) {
                        screenRect.x = Qt.binding(() => screenRect.home.x);
                        screenRect.y = Qt.binding(() => screenRect.home.y);
                        return;
                    }
                    // Sit where it lands until Hyprland reports the new layout
                    const at = root.toCanvas(p.x, p.y);
                    screenRect.x = at.x;
                    screenRect.y = at.y;
                    Displays.arrange(screenRect.modelData.name, `${p.x}x${p.y}`);
                }
            }
        }
    }

    StyledText {
        anchors.centerIn: parent
        visible: root.rects.length === 0
        text: Tr.tr("No displays")
        color: Colours.palette.m3onSurfaceVariant
    }
}
