pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import Quickshell.Hyprland
import Quickshell.Services.UPower
import Caelestia.Config
import qs.components
import qs.services

// A Home Assistant custom card, drawn by a headless browser (services/
// HaWebCards) at this item's size and the screen's scale. It freezes while the
// power profile is power saver, and on the desktop also while windows cover it.
Item {
    id: root

    property string instance
    property var card: ({})
    // On the desktop: frozen while that screen's workspace has tiled or
    // fullscreen windows over it
    property bool pauseWhenCovered
    // The card's own animations: most of what it costs. Without, it still
    // changes with its data
    property bool animate

    readonly property string uid: `webcard-${Math.random().toString(36).slice(2)}`
    readonly property real scale: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1
    readonly property HyprlandMonitor monitor: Hyprland.monitors.values.find(m => m.name === Screen.name) ?? null
    // A window over all of it (windows elsewhere on the workspace don't count)
    readonly property bool covered: {
        if (!pauseWhenCovered || !monitor || width <= 0)
            return false;
        const p = mapToItem(null, 0, 0);
        const x = (monitor.lastIpcObject?.x ?? 0) + p.x;
        const y = (monitor.lastIpcObject?.y ?? 0) + p.y;
        return (monitor.activeWorkspace?.toplevels?.values ?? []).some(t => {
            const o = t.lastIpcObject;
            if (!o?.at || !o?.size)
                return false;
            return o.at[0] <= x && o.at[1] <= y && o.at[0] + o.size[0] >= x + width && o.at[1] + o.size[1] >= y + height;
        });
    }
    readonly property bool paused: PowerProfiles.profile === PowerProfile.PowerSaver || covered || !visible
    readonly property var frame: HaWebCards.frames[uid] ?? null
    readonly property var cardState: HaWebCards.states[uid] ?? null
    property bool opened

    // Afresh, as a new config or animating or not needs
    function reopen(): void {
        if (opened)
            HaWebCards.closeCard(uid);
        opened = false;
        settle.restart();
    }

    implicitWidth: 320
    implicitHeight: 320

    onWidthChanged: settle.restart()
    onHeightChanged: settle.restart()
    onScaleChanged: settle.restart()
    onAnimateChanged: reopen()
    onCardChanged: reopen()
    onPausedChanged: if (opened)
        HaWebCards.setPaused(uid, paused)
    Component.onCompleted: settle.start()
    Component.onDestruction: HaWebCards.closeCard(uid)

    // Each new frame goes to the picture that isn't showing
    onFrameChanged: {
        if (!frame)
            return;
        const back = pictures.itemAt(1 - pictures.front);
        if (back) {
            back.seq = frame.seq;
            back.source = `file://${frame.path}?${frame.seq}`;
        }
    }

    // The size settles before it's opened, and resizes come in one go
    Timer {
        id: settle

        interval: 300
        onTriggered: {
            if (root.width < 8 || root.height < 8)
                return;
            if (!root.opened) {
                HaWebCards.openCard(root.uid, root.instance, root.card, root.width, root.height, root.scale, root.paused, root.animate);
                root.opened = true;
            } else {
                HaWebCards.resize(root.uid, root.width, root.height, root.scale);
            }
        }
    }

    // Two pictures, so a new one only shows once it's loaded: no flicker
    Repeater {
        id: pictures

        property int front

        model: 2

        Image {
            id: picture

            required property int index
            property int seq: -1

            anchors.fill: parent
            asynchronous: true
            cache: false
            smooth: true
            mipmap: true
            fillMode: Image.PreserveAspectFit
            visible: pictures.front === index && status === Image.Ready
            onStatusChanged: if (status === Image.Ready)
                pictures.front = index
        }
    }

    StyledText {
        anchors.centerIn: parent
        width: parent.width - Tokens.padding.large * 2
        visible: !root.frame
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: root.cardState?.status === "error" ? root.cardState.error : `${root.card?.type ?? ""}…`
        color: Colours.palette.m3outline
        font: Tokens.font.label.medium
    }
}
