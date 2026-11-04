pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.utils

// The editor on one screen: the widgets over a dimmed desktop, with a palette
// to add more. Esc or Done to finish.
//
// Along the edges, where the bars are, are their docks: drag a widget that can
// be in a bar (the performance dials) onto one to put it in that bar, drag it
// back out onto the desktop to take it out again.
Item {
    id: root

    required property ShellScreen screen

    readonly property bool leftBar: !Strings.testRegexList(GlobalConfig.forScreen(screen.name).bar.excludedScreens, screen.name)
    readonly property bool rightBar: GlobalConfig.forScreen(screen.name).rightBar.enabled
    readonly property bool anyDockable: Widgets.plugins.some(p => p.bar)
    // While a widget is dragged: the bar it would go into on release, if any
    property string dropSide
    // A docked widget being dragged out, and where the pointer is
    property string dragUid
    property point dragPos

    // The bar under a point (in this item), for a widget of this type
    function dockAt(type: string, p: point): string {
        if (!Widgets.canDock(type))
            return "";
        if (leftBar && p.x <= leftDock.x + leftDock.width + Tokens.padding.large)
            return "left";
        if (rightBar && p.x >= rightDock.x - Tokens.padding.large)
            return "right";
        return "";
    }

    // Where among a bar's widgets a drop at y goes
    function dockIndexAt(side: string, y: real): int {
        const dock = side === "left" ? leftDock : rightDock;
        return dock.indexAt(mapToItem(dock.list, 0, y).y);
    }

    focus: true
    Keys.onEscapePressed: Widgets.editing = false
    Keys.onReturnPressed: Widgets.editing = false

    StyledRect {
        anchors.fill: parent
        color: Qt.alpha(Colours.palette.m3scrim, 0.5)
    }

    Repeater {
        model: ScriptModel {
            values: Widgets.instancesOn(root.screen.name).map(i => i.uid)
        }

        EditFrame {
            required property string modelData

            uid: modelData
            screen: root.screen
            view: root
        }
    }

    Dock {
        id: leftDock

        side: "left"
        visible: root.leftBar && (root.anyDockable || uids.length > 0)
        anchors.left: parent.left
    }

    Dock {
        id: rightDock

        side: "right"
        visible: root.rightBar && (root.anyDockable || uids.length > 0)
        anchors.right: parent.right
    }

    // A docked widget on its way out: its icon follows the pointer
    StyledRect {
        readonly property var plugin: Widgets.pluginFor(Widgets.instances.find(i => i.uid === root.dragUid)?.type ?? "")

        visible: root.dragUid !== ""
        z: 20
        x: root.dragPos.x - width / 2
        y: root.dragPos.y - height / 2
        implicitWidth: Tokens.sizes.bar.innerWidth + Tokens.padding.medium * 2
        implicitHeight: implicitWidth
        radius: implicitWidth / 2
        color: root.dropSide ? Colours.palette.m3primaryContainer : Colours.palette.m3tertiaryContainer

        MaterialIcon {
            anchors.centerIn: parent
            text: parent.plugin?.icon ?? "widgets"
            color: root.dropSide ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onTertiaryContainer
            fontStyle: Tokens.font.icon.medium
        }
    }

    // Palette: the title and Done above the plugins, which wrap onto more rows
    // when the screen is too narrow for one (and more plugins never push it
    // off the screen)
    StyledRect {
        id: panel

        // The most it may take, and what one row of plugins wants
        readonly property real room: root.width - Tokens.padding.extraExtraLarge * 4
        readonly property real chipsWidth: {
            let w = 0;
            let n = 0;
            for (const c of chips.children) {
                if (c.visible && c.implicitWidth > 0) {
                    w += c.implicitWidth;
                    n++;
                }
            }
            return w + Math.max(0, n - 1) * chips.spacing;
        }

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Tokens.padding.extraExtraLarge * 1.5
        implicitWidth: Math.min(room, Math.max(header.implicitWidth, chipsWidth) + Tokens.padding.extraLarge * 2)
        implicitHeight: content.implicitHeight + Tokens.padding.large * 2
        radius: Tokens.rounding.extraLarge
        color: Colours.tPalette.m3surfaceContainer

        ColumnLayout {
            id: content

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Tokens.padding.extraLarge
            anchors.rightMargin: Tokens.padding.extraLarge
            spacing: Tokens.spacing.medium

            RowLayout {
                id: header

                Layout.fillWidth: true
                spacing: Tokens.spacing.large

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: Tr.tr("Desktop widgets")
                        font: Tokens.font.title.medium
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.anyDockable ? Tr.tr("Drag to move · corners to resize · dials onto a bar · Esc when done") : Tr.tr("Drag to move · corners to resize · Esc when done")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.medium
                        elide: Text.ElideRight
                    }
                }

                TextButton {
                    text: Tr.tr("Done")
                    type: TextButton.Filled
                    onClicked: Widgets.editing = false
                }
            }

            Flow {
                id: chips

                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                Repeater {
                    model: Widgets.plugins

                    IconTextButton {
                        required property var modelData

                        icon: modelData.icon
                        text: modelData.name
                        type: TextButton.Tonal
                        // One that shows nothing until it's set up (a Home
                        // Assistant camera, say) opens its settings at once
                        onClicked: {
                            const uid = Widgets.add(modelData.id, root.screen, "");
                            if (uid && Widgets.needsSetup(modelData.id))
                                Widgets.openSettings(uid);
                        }
                    }
                }

                StyledText {
                    visible: Widgets.plugins.length === 0
                    text: Tr.tr("No widget plugins found")
                    color: Colours.palette.m3outline
                }
            }
        }
    }

    // A bar's dock, at the screen's edge where the bar is: the widgets in it,
    // top to bottom; it lights up while a widget is dragged onto it
    component Dock: StyledRect {
        id: dock

        required property string side
        readonly property list<string> uids: Widgets.dockedOn(root.screen.name, side).map(i => i.uid)
        readonly property bool targeted: root.dropSide === side
        property alias list: column

        // The index a drop at y (in the column) goes before
        function indexAt(y: real): int {
            let i = 0;
            for (const c of column.children) {
                // Not the one being dragged: it leaves its place
                if (c.objectName !== "dockItem" || c.modelData === root.dragUid)
                    continue;
                if (y < c.y + c.height / 2)
                    return i;
                i++;
            }
            return i;
        }

        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: Tokens.padding.medium
        implicitWidth: Tokens.sizes.bar.innerWidth + Tokens.padding.medium * 2
        radius: Tokens.rounding.extraLarge
        // Opaque: it covers the bar under it, so its widgets don't show twice
        color: targeted ? Qt.tint(Colours.palette.m3surfaceContainer, Qt.alpha(Colours.palette.m3primary, 0.25)) : Colours.palette.m3surfaceContainerLow
        border.width: 2
        border.color: targeted ? Colours.palette.m3primary : Qt.alpha(Colours.palette.m3primary, 0.35)

        Behavior on color {
            CAnim {}
        }

        Column {
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.topMargin: Tokens.padding.large
            spacing: Tokens.spacing.extraSmall

            MaterialIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                text: dock.side === "left" ? "dock_to_left" : "dock_to_right"
                color: Colours.palette.m3primary
                fontStyle: Tokens.font.icon.medium
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Tr.tr("Bar")
                color: Colours.palette.m3primary
                font: Tokens.font.label.small
            }
        }

        Column {
            id: column

            anchors.centerIn: parent
            spacing: Tokens.spacing.medium

            Repeater {
                model: ScriptModel {
                    values: dock.uids
                }

                DockItem {
                    side: dock.side
                }
            }
        }
    }

    // A docked widget in the editor: drag it to another place in the bar,
    // into the other bar or out onto the desktop; click for its settings
    component DockItem: Item {
        id: item

        required property string modelData
        required property string side
        readonly property var inst: Widgets.instances.find(i => i.uid === modelData) ?? null
        readonly property var plugin: Widgets.pluginFor(inst?.type ?? "")

        objectName: "dockItem"
        implicitWidth: Tokens.sizes.bar.innerWidth
        implicitHeight: Math.max(Tokens.sizes.bar.innerWidth, host.height)
        opacity: root.dragUid === modelData ? 0.35 : 1

        WidgetHost {
            id: host

            active: item.inst !== null
            instance: item.inst ?? ({})
            screen: root.screen
            bar: item.side
            editing: true
            width: Tokens.sizes.bar.innerWidth
        }

        StyledRect {
            anchors.fill: parent
            anchors.margins: -Tokens.padding.extraSmall
            radius: Tokens.rounding.medium
            color: "transparent"
            border.width: 2
            border.color: area.containsMouse ? Colours.palette.m3primary : "transparent"
        }

        MouseArea {
            id: area

            property point press
            property bool dragging

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            onPressed: e => {
                press = Qt.point(e.x, e.y);
                dragging = false;
            }
            onPositionChanged: e => {
                if (!pressed)
                    return;
                if (!dragging && Math.hypot(e.x - press.x, e.y - press.y) < 6)
                    return;
                dragging = true;
                const p = mapToItem(root, e.x, e.y);
                root.dragUid = item.modelData;
                root.dragPos = p;
                root.dropSide = root.dockAt(item.inst?.type ?? "", p);
            }
            onReleased: e => {
                if (!dragging) {
                    if ((item.plugin?.schema?.length ?? 0) > 0)
                        Widgets.openSettings(item.modelData);
                    return;
                }
                const p = mapToItem(root, e.x, e.y);
                const side = root.dropSide;
                const uid = item.modelData;
                // Before it's let go of, as where it goes skips its own place
                const index = side ? root.dockIndexAt(side, p.y) : -1;
                root.dragUid = "";
                root.dropSide = "";
                dragging = false;
                if (side) {
                    Widgets.dock(uid, side, index);
                } else {
                    const w = item.inst?.width ?? 200, h = item.inst?.height ?? 200;
                    Widgets.undock(uid, Math.max(0, Math.min(root.width - w, p.x - w / 2)), Math.max(0, Math.min(root.height - h, p.y - h / 2)));
                }
            }
            onCanceled: {
                root.dragUid = "";
                root.dropSide = "";
                dragging = false;
            }
        }

        // Out of the bar and off the desktop altogether
        StyledRect {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.rightMargin: -Tokens.padding.small
            anchors.topMargin: -Tokens.padding.small
            visible: area.containsMouse || removeArea.containsMouse
            implicitWidth: Tokens.padding.large * 1.6
            implicitHeight: implicitWidth
            radius: implicitWidth / 2
            color: removeArea.containsMouse ? Colours.palette.m3error : Colours.palette.m3errorContainer

            MaterialIcon {
                anchors.centerIn: parent
                text: "close"
                color: removeArea.containsMouse ? Colours.palette.m3onError : Colours.palette.m3onErrorContainer
                fontStyle: Tokens.font.icon.builders.small.scale(0.8).build()
            }

            MouseArea {
                id: removeArea

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Widgets.remove(item.modelData)
            }
        }
    }
}
