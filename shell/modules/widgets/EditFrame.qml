pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.services

// One widget in the editor: drag it to move, drag a corner to resize; its
// settings and remove buttons above it
Item {
    id: root

    required property string uid
    required property ShellScreen screen

    readonly property var instance: Widgets.instances.find(i => i.uid === uid) ?? null
    readonly property var plugin: Widgets.pluginFor(instance?.type ?? "")
    readonly property int grid: Math.max(1, GlobalConfig.widgets.gridSize)
    readonly property real aspect: instance ? instance.width / Math.max(1, instance.height) : 1
    property bool busy // moving or resizing

    function snap(v: real): real {
        return Math.round(v / grid) * grid;
    }

    function commit(): void {
        busy = false;
        Widgets.update(uid, {
            x: Math.round(x),
            y: Math.round(y),
            width: Math.round(width),
            height: Math.round(height)
        });
    }

    x: instance?.x ?? 0
    y: instance?.y ?? 0
    width: instance?.width ?? 0
    height: instance?.height ?? 0

    WidgetHost {
        anchors.fill: parent
        active: root.instance !== null
        instance: root.instance ?? ({})
        screen: root.screen
        editing: true
        screenX: root.x
        screenY: root.y
    }

    StyledRect {
        anchors.fill: parent
        anchors.margins: -Tokens.padding.small
        radius: Tokens.rounding.large
        color: Qt.alpha(Colours.palette.m3primary, move.containsMouse || root.busy ? 0.1 : 0.03)
        border.width: 2
        border.color: move.containsMouse || root.busy ? Colours.palette.m3primary : Qt.alpha(Colours.palette.m3primary, 0.45)
    }

    MouseArea {
        id: move

        property point start

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        onPressed: e => {
            start = Qt.point(e.x, e.y);
            root.busy = true;
        }
        onPositionChanged: e => {
            if (!pressed)
                return;
            root.x = Math.max(0, Math.min(root.screen.width - root.width, root.snap(root.x + e.x - start.x)));
            root.y = Math.max(0, Math.min(root.screen.height - root.height, root.snap(root.y + e.y - start.y)));
        }
        onReleased: root.commit()
    }

    // Name and size, top-left
    StyledRect {
        anchors.left: parent.left
        anchors.bottom: parent.top
        anchors.bottomMargin: Tokens.padding.small + Tokens.spacing.small
        implicitWidth: tag.implicitWidth + Tokens.padding.medium * 2
        implicitHeight: tag.implicitHeight + Tokens.padding.small * 2
        radius: Tokens.rounding.full
        color: Colours.palette.m3primaryContainer

        StyledText {
            id: tag

            anchors.centerIn: parent
            text: `${root.plugin?.name ?? root.instance?.type ?? ""}  ·  ${Math.round(root.width)} × ${Math.round(root.height)}`
            color: Colours.palette.m3onPrimaryContainer
            font: Tokens.font.label.medium
        }
    }

    // Its settings, for widgets that have some: straight to its page in
    // Settings (the editor closes, or it would cover the window)
    StyledRect {
        anchors.right: removeButton.left
        anchors.rightMargin: Tokens.spacing.small
        anchors.bottom: parent.top
        anchors.bottomMargin: Tokens.padding.small + Tokens.spacing.small
        visible: (root.plugin?.schema?.length ?? 0) > 0
        implicitWidth: Tokens.padding.large * 2
        implicitHeight: implicitWidth
        radius: implicitWidth / 2
        color: settingsArea.containsMouse ? Colours.palette.m3primary : Colours.palette.m3secondaryContainer

        MaterialIcon {
            anchors.centerIn: parent
            text: "tune"
            color: settingsArea.containsMouse ? Colours.palette.m3onPrimary : Colours.palette.m3onSecondaryContainer
            fontStyle: Tokens.font.icon.small
        }

        MouseArea {
            id: settingsArea

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Widgets.openSettings(root.uid)
        }
    }

    StyledRect {
        id: removeButton

        anchors.right: parent.right
        anchors.bottom: parent.top
        anchors.bottomMargin: Tokens.padding.small + Tokens.spacing.small
        implicitWidth: Tokens.padding.large * 2
        implicitHeight: implicitWidth
        radius: implicitWidth / 2
        color: removeArea.containsMouse ? Colours.palette.m3error : Colours.palette.m3errorContainer

        MaterialIcon {
            anchors.centerIn: parent
            text: "close"
            color: removeArea.containsMouse ? Colours.palette.m3onError : Colours.palette.m3onErrorContainer
            fontStyle: Tokens.font.icon.small
        }

        MouseArea {
            id: removeArea

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Widgets.remove(root.uid)
        }
    }

    Repeater {
        // Corners: which edges each one moves
        model: [[-1, -1], [1, -1], [-1, 1], [1, 1]]

        Rectangle {
            id: handle

            required property var modelData
            readonly property int sx: modelData[0]
            readonly property int sy: modelData[1]

            x: (sx < 0 ? 0 : root.width) - width / 2 + sx * Tokens.padding.small
            y: (sy < 0 ? 0 : root.height) - height / 2 + sy * Tokens.padding.small
            width: Tokens.padding.large * 1.4
            height: width
            radius: width / 2
            color: Colours.palette.m3primary
            border.width: 3
            border.color: Colours.palette.m3onPrimary
            scale: drag.containsMouse || drag.pressed ? 1.25 : 1

            Behavior on scale {
                Anim {
                    type: Anim.FastSpatial
                }
            }

            MouseArea {
                id: drag

                property rect start
                property point press

                anchors.fill: parent
                anchors.margins: -Tokens.padding.small
                hoverEnabled: true
                cursorShape: handle.sx === handle.sy ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor
                onPressed: e => {
                    start = Qt.rect(root.x, root.y, root.width, root.height);
                    press = mapToItem(root.parent, e.x, e.y);
                    root.busy = true;
                }
                onPositionChanged: e => {
                    if (!pressed)
                        return;
                    const p = mapToItem(root.parent, e.x, e.y);
                    const min = root.plugin?.minSize ?? [48, 48];
                    let w = Math.max(min[0], root.snap(start.width + handle.sx * (p.x - press.x)));
                    let h = Math.max(min[1], root.snap(start.height + handle.sy * (p.y - press.y)));
                    if (root.plugin?.keepAspect) {
                        h = Math.max(min[1], Math.round(w / root.aspect));
                        w = Math.round(h * root.aspect);
                    }
                    root.width = w;
                    root.height = h;
                    root.x = handle.sx < 0 ? start.x + start.width - w : start.x;
                    root.y = handle.sy < 0 ? start.y + start.height - h : start.y;
                }
                onReleased: root.commit()
            }
        }
    }
}
