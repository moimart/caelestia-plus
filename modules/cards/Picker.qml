pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.services

// Choosing the back of a new card: every other window on this monitor is
// outlined; click one (or Tab to it and press Enter). Esc cancels.
Item {
    id: root

    required property ShellScreen screen

    readonly property HyprlandMonitor monitor: Hypr.monitorFor(screen)
    readonly property HyprlandToplevel front: Cards.pickFront
    readonly property var visibleWs: {
        const ids = [monitor?.activeWorkspace?.id];
        const special = monitor?.lastIpcObject.specialWorkspace?.id;
        if (special)
            ids.push(special);
        return ids;
    }
    // Floating windows last, so they sit on top of tiled ones
    readonly property var candidates: Hypr.toplevels.values.filter(t => {
        const ipc = t.lastIpcObject;
        return t !== front && ipc?.mapped && ipc.visible !== false && visibleWs.includes(ipc.workspace?.id) && !Cards.isGrouped(t);
    }).sort((a, b) => a.lastIpcObject.floating - b.lastIpcObject.floating)
    property int current: -1

    function rectFor(t: HyprlandToplevel): rect {
        const ipc = t?.lastIpcObject;
        if (!ipc?.at || !monitor)
            return Qt.rect(0, 0, 0, 0);
        return Qt.rect(ipc.at[0] - monitor.lastIpcObject.x, ipc.at[1] - monitor.lastIpcObject.y, ipc.size[0], ipc.size[1]);
    }

    function chooseCurrent(): void {
        if (candidates[current])
            choose(candidates[current]);
    }

    function choose(t: HyprlandToplevel): void {
        Cards.pair(Cards.pickFront, t);
    }

    focus: true
    Keys.onEscapePressed: Cards.cancelPairing()
    Keys.onTabPressed: current = (current + 1) % Math.max(1, candidates.length)
    Keys.onBacktabPressed: current = (current - 1 + candidates.length) % Math.max(1, candidates.length)
    Keys.onRightPressed: current = (current + 1) % Math.max(1, candidates.length)
    Keys.onLeftPressed: current = (current - 1 + candidates.length) % Math.max(1, candidates.length)
    Keys.onReturnPressed: chooseCurrent()
    Keys.onEnterPressed: chooseCurrent()

    StyledRect {
        anchors.fill: parent
        color: Qt.alpha(Colours.palette.m3scrim, 0.4)

        MouseArea {
            anchors.fill: parent
            onClicked: Cards.cancelPairing()
        }
    }

    // The front: shown, but not choosable
    Outline {
        readonly property rect r: root.rectFor(root.front)

        visible: root.front?.lastIpcObject.workspace?.id !== undefined && root.visibleWs.includes(root.front?.lastIpcObject.workspace?.id)
        x: r.x
        y: r.y
        width: r.width
        height: r.height
        label: Tr.tr("Front")
        icon: "flip_to_front"
        chosen: true
    }

    Repeater {
        model: root.candidates

        Outline {
            id: outline

            required property HyprlandToplevel modelData
            required property int index
            readonly property rect r: root.rectFor(modelData)

            x: r.x
            y: r.y
            width: r.width
            height: r.height
            label: Tr.tr("Make this the back")
            icon: "flip_to_back"
            hot: mouse.containsMouse || root.current === index

            MouseArea {
                id: mouse

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.choose(outline.modelData)
            }
        }
    }

    StyledRect {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Tokens.padding.extraExtraLarge * 2
        implicitWidth: hint.implicitWidth + Tokens.padding.extraLarge * 2
        implicitHeight: hint.implicitHeight + Tokens.padding.large * 2
        radius: Tokens.rounding.full
        color: Colours.palette.m3inverseSurface

        Row {
            id: hint

            anchors.centerIn: parent
            spacing: Tokens.spacing.small

            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                text: "flip"
                color: Colours.palette.m3inverseOnSurface
                fontStyle: Tokens.font.icon.medium
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: root.candidates.length > 0 ? Tr.tr("Choose the window for the back of the card · Tab to cycle · Esc to cancel") : Tr.tr("No other windows on this monitor · Esc to cancel")
                color: Colours.palette.m3inverseOnSurface
                font: Tokens.font.body.medium
            }
        }
    }

    component Outline: StyledRect {
        id: box

        property string label
        property string icon
        property bool hot
        property bool chosen

        radius: Hypr.options["decoration:rounding"] ?? Tokens.rounding.large
        color: Qt.alpha(Colours.palette.m3primary, hot ? 0.22 : chosen ? 0.1 : 0.04)
        border.width: hot || chosen ? 4 : 2
        border.color: chosen ? Colours.palette.m3tertiary : hot ? Colours.palette.m3primary : Qt.alpha(Colours.palette.m3primary, 0.5)

        Behavior on color {
            CAnim {}
        }

        StyledRect {
            anchors.centerIn: parent
            visible: box.hot || box.chosen
            implicitWidth: badge.implicitWidth + Tokens.padding.large * 2
            implicitHeight: badge.implicitHeight + Tokens.padding.medium * 2
            radius: Tokens.rounding.full
            color: box.chosen ? Colours.palette.m3tertiaryContainer : Colours.palette.m3primaryContainer

            Row {
                id: badge

                anchors.centerIn: parent
                spacing: Tokens.spacing.small

                MaterialIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    text: box.icon
                    color: box.chosen ? Colours.palette.m3onTertiaryContainer : Colours.palette.m3onPrimaryContainer
                    fill: 1
                    fontStyle: Tokens.font.icon.medium
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: box.label
                    color: box.chosen ? Colours.palette.m3onTertiaryContainer : Colours.palette.m3onPrimaryContainer
                    font: Tokens.font.title.small
                }
            }
        }
    }
}
