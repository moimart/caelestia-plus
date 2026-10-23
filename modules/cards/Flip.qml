pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Caelestia.Config
import qs.components
import qs.services

// One flip of a card. Both windows are captured, the real ones made invisible,
// and a card with the captures on its faces turns over in 3D in their place;
// when it lands, the window that was behind is shown again, live.
//   capture front -> switch the group to the back -> capture back -> hide it
//   -> turn -> show the back window -> fade the card out
Item {
    id: root

    required property var card
    required property HyprlandMonitor monitor

    readonly property HyprlandToplevel front: card ? card.front : null
    readonly property HyprlandToplevel back: card ? card.back : null
    readonly property rect area: {
        const ipc = front?.lastIpcObject;
        if (!ipc?.at || !monitor)
            return Qt.rect(0, 0, 0, 0);
        return Qt.rect(ipc.at[0] - monitor.lastIpcObject.x, ipc.at[1] - monitor.lastIpcObject.y, ipc.size[0], ipc.size[1]);
    }
    readonly property real rounding: Hypr.options["decoration:rounding"] ?? 0
    readonly property int sign: GlobalConfig.cards.direction === "left" ? -1 : 1

    property int phase // 0 capture front, 1 capture back, 2 turning, 3 landing
    property real angle

    signal finished

    function captureBack(): void {
        phase = 1;
        Cards.showOther(card);
        backDelay.start();
    }

    function turn(): void {
        if (phase !== 1)
            return;
        backTimeout.stop();
        phase = 2;
        backView.live = false;
        Cards.hide(back);
        turnAnim.start();
    }

    function land(): void {
        phase = 3;
        Cards.show(back);
        Cards.show(front); // hidden behind the back now, but untagged for next time
        landTimer.start();
    }

    // Shadow under the card, narrowing as it turns edge-on
    RectangularShadow {
        x: root.area.x + root.area.width * (1 - Math.abs(Math.cos(root.angle * Math.PI / 180)) * cardItem.scale) / 2
        y: root.area.y + root.area.height * (1 - cardItem.scale) / 2 + 10
        width: root.area.width * Math.abs(Math.cos(root.angle * Math.PI / 180)) * cardItem.scale
        height: root.area.height * cardItem.scale
        radius: root.rounding
        visible: root.phase === 2
        color: Qt.alpha(Colours.palette.m3shadow, 0.55)
        blur: 40 + 60 * Math.sin(root.angle * Math.PI / 180) ** 2
        spread: 0
    }

    Flipable {
        id: cardItem

        x: root.area.x
        y: root.area.y
        width: root.area.width
        height: root.area.height
        opacity: frontView.hasContent ? 1 : 0

        front: Face {
            ScreencopyView {
                id: frontView

                anchors.fill: parent
                captureSource: root.front?.wayland ?? null
                live: root.phase === 0
                onHasContentChanged: {
                    if (hasContent && root.phase === 0)
                        root.captureBack();
                }
            }
        }

        back: Face {
            ScreencopyView {
                id: backView

                anchors.fill: parent
                captureSource: root.phase >= 1 && !backDelay.running ? (root.back?.wayland ?? null) : null
                live: true
                onHasContentChanged: {
                    if (hasContent)
                        root.turn();
                }
            }
        }

        transform: Rotation {
            origin.x: cardItem.width / 2
            origin.y: cardItem.height / 2
            axis.x: 0
            axis.y: 1
            axis.z: 0
            angle: root.angle
            distanceToPlane: Math.max(cardItem.width, cardItem.height) * GlobalConfig.cards.perspective
        }

        Behavior on opacity {
            enabled: root.phase === 3

            Anim {
                type: Anim.FastEffects
            }
        }
    }

    ParallelAnimation {
        id: turnAnim

        onFinished: root.land()

        NumberAnimation {
            target: root
            property: "angle"
            from: 0
            to: 180 * root.sign
            duration: GlobalConfig.cards.duration
            easing.type: Easing.InOutCubic
        }

        SequentialAnimation {
            NumberAnimation {
                target: cardItem
                property: "scale"
                from: 1
                to: 1 - GlobalConfig.cards.lift
                duration: GlobalConfig.cards.duration / 2
                easing.type: Easing.OutQuad
            }
            NumberAnimation {
                target: cardItem
                property: "scale"
                to: 1
                duration: GlobalConfig.cards.duration / 2
                easing.type: Easing.InQuad
            }
        }
    }

    // Give Hyprland a moment to switch the group before capturing the back
    Timer {
        id: backDelay

        interval: 40
        onTriggered: backTimeout.start()
    }

    Timer {
        id: backTimeout

        interval: 400
        onTriggered: root.turn()
    }

    // Let the real window fade back in under the card, then drop the card
    Timer {
        id: landTimer

        interval: 50
        onTriggered: {
            cardItem.opacity = 0;
            fadeOut.start();
        }
    }

    Timer {
        id: fadeOut

        interval: 120
        onTriggered: root.finished()
    }

    // Never leave windows invisible if something goes wrong
    Timer {
        running: true
        interval: GlobalConfig.cards.duration + 3000
        onTriggered: {
            Cards.show(root.front);
            Cards.show(root.back);
            root.finished();
        }
    }

    component Face: ClipRect {
        width: cardItem.width
        height: cardItem.height
        radius: root.rounding
    }
}
