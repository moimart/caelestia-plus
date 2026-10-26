pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.services

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
    readonly property real pad: Tokens.padding.extraLarge
    readonly property real factor: Math.min((width - pad * 2) / bounds.width, (height - pad * 2) / bounds.height)
    readonly property point origin: Qt.point((width - bounds.width * factor) / 2, (height - bounds.height * factor) / 2)

    signal picked(name: string)

    // Where a display dropped at (x, y), in desktop pixels, ends up: flush
    // against the nearest edge of another, overlapping it along that edge,
    // with edges and centres snapping into line when close
    function snap(name: string, x: real, y: real): point {
        const me = rects.find(r => r.name === name);
        const others = rects.filter(r => r.name !== name);
        if (!me || others.length === 0)
            return Qt.point(me?.x ?? 0, me?.y ?? 0);
        const w = me.width, h = me.height;
        const minOverlap = 40;
        const near = 0.08;
        const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
        // Line up starts, ends or centres along the shared edge when close
        const align = (v, start, length, size) => {
            for (const t of [start, start + length - size, start + (length - size) / 2])
                if (Math.abs(v - t) < Math.max(size, length) * near)
                    return t;
            return v;
        };
        const overlaps = (cx, cy) => others.some(o => cx < o.x + o.width && cx + w > o.x && cy < o.y + o.height && cy + h > o.y);

        let best = null;
        for (const o of others) {
            const vy = align(clamp(y, o.y - h + minOverlap, o.y + o.height - minOverlap), o.y, o.height, h);
            const vx = align(clamp(x, o.x - w + minOverlap, o.x + o.width - minOverlap), o.x, o.width, w);
            for (const c of [Qt.point(o.x + o.width, vy), Qt.point(o.x - w, vy), Qt.point(vx, o.y + o.height), Qt.point(vx, o.y - h)]) {
                const p = Qt.point(Math.round(c.x), Math.round(c.y));
                if (overlaps(p.x, p.y))
                    continue;
                const d = Math.hypot(p.x - x, p.y - y);
                if (!best || d < best.d)
                    best = {
                        p: p,
                        d: d
                    };
            }
        }
        return best ? best.p : Qt.point(me.x, me.y);
    }

    implicitHeight: 240

    Repeater {
        model: root.rects

        StyledRect {
            id: screenRect

            required property var modelData
            readonly property bool isSelected: root.selected === modelData.name
            readonly property real homeX: root.origin.x + (modelData.x - root.bounds.x) * root.factor
            readonly property real homeY: root.origin.y + (modelData.y - root.bounds.y) * root.factor

            x: homeX
            y: homeY
            width: Math.max(8, modelData.width * root.factor)
            height: Math.max(8, modelData.height * root.factor)
            z: mover.drag.active ? 2 : (isSelected ? 1 : 0)
            radius: Tokens.rounding.small
            color: isSelected ? Colours.palette.m3primaryContainer : Colours.palette.m3surfaceContainerHighest
            border.width: isSelected ? 2 : 0
            border.color: Colours.palette.m3primary

            Column {
                anchors.centerIn: parent
                width: parent.width - Tokens.padding.small * 2
                spacing: 0

                StyledText {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: screenRect.modelData.name
                    color: screenRect.isSelected ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurface
                    font: Tokens.font.label.large
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
                onPressed: root.picked(screenRect.modelData.name)
                onReleased: {
                    if (!mover.drag.active && Math.abs(screenRect.x - screenRect.homeX) < 1 && Math.abs(screenRect.y - screenRect.homeY) < 1)
                        return;
                    const x = root.bounds.x + (screenRect.x - root.origin.x) / root.factor;
                    const y = root.bounds.y + (screenRect.y - root.origin.y) / root.factor;
                    const p = root.snap(screenRect.modelData.name, x, y);
                    // Back to the bound position; the real one comes back from Hyprland
                    screenRect.x = Qt.binding(() => screenRect.homeX);
                    screenRect.y = Qt.binding(() => screenRect.homeY);
                    if (p.x !== screenRect.modelData.x || p.y !== screenRect.modelData.y)
                        Displays.change(screenRect.modelData.name, {
                            position: `${p.x}x${p.y}`
                        });
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
