import QtQuick
import Caelestia.Config
import qs.components
import qs.services

// A widget's tooltip (its root's "tooltip": the first line is the title, the
// rest under it), after a moment's hover. It's drawn in the widget's window,
// out of the way: beside the bar for a widget in a bar (on whichever side has
// the room), above the widget on the desktop (below it near the top).
StyledRect {
    id: root

    // The widget's host (WidgetHost)
    required property Item host
    required property string text
    property bool hovered

    readonly property list<string> lines: text.split("\n")
    readonly property bool shown: hovered && delay.done && text !== ""

    // Puts it beside or above the host, kept on screen
    function place(): void {
        const area = parent;
        if (!area)
            return;
        const p = host.mapToItem(area, 0, 0);
        const gap = Tokens.spacing.medium;
        let tx, ty;
        if (host.bar) {
            // Clear of the bar's own padding, on the side with the room
            const clear = Tokens.padding.large + gap;
            const rightward = p.x + host.width / 2 < area.width / 2;
            tx = rightward ? p.x + host.width + clear : p.x - width - clear;
            ty = p.y + host.height / 2 - height / 2;
        } else {
            tx = p.x + host.width / 2 - width / 2;
            ty = p.y - height - gap;
            if (ty < gap)
                ty = p.y + host.height + gap;
        }
        x = Math.max(gap, Math.min(area.width - width - gap, tx));
        y = Math.max(gap, Math.min(area.height - height - gap, ty));
    }

    parent: host.Window.window?.contentItem ?? host
    z: 1000
    implicitWidth: column.implicitWidth + Tokens.padding.large * 2
    implicitHeight: column.implicitHeight + Tokens.padding.small * 2
    radius: Tokens.rounding.large
    color: Colours.palette.m3inverseSurface
    opacity: shown ? 1 : 0
    visible: opacity > 0

    onHoveredChanged: if (!hovered)
        delay.done = false
    onShownChanged: if (shown)
        place()
    onImplicitWidthChanged: if (shown)
        place()
    onImplicitHeightChanged: if (shown)
        place()

    Behavior on opacity {
        Anim {
            type: Anim.FastEffects
        }
    }

    Column {
        id: column

        anchors.centerIn: parent
        spacing: 0

        StyledText {
            text: root.lines[0] ?? ""
            color: Colours.palette.m3inverseOnSurface
            font: Tokens.font.label.large
        }

        Repeater {
            model: root.lines.slice(1)

            StyledText {
                required property string modelData

                text: modelData
                color: Qt.alpha(Colours.palette.m3inverseOnSurface, 0.75)
                font: Tokens.font.label.medium
            }
        }
    }

    // A moment's hover first, not on every pass of the pointer
    Timer {
        id: delay

        property bool done

        interval: 500
        running: root.hovered && !done
        onTriggered: done = true
    }
}
