pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Caelestia.Config
import qs.components.containers
import qs.components.misc
import qs.services

// Window cards: pair two windows into one and flip between them in 3D.
// The pairing itself is done in Hyprland by services/Cards.qml.
Scope {
    id: root

    // Choosing the back: an overlay on every monitor, keyboard on the focused one
    LazyLoader {
        active: Cards.picking

        Variants {
            model: Quickshell.screens

            StyledWindow {
                id: pickWin

                required property ShellScreen modelData
                readonly property bool focusedMon: Hypr.focusedMonitor?.name === modelData.name

                screen: modelData
                name: "cards-picker"
                WlrLayershell.exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: focusedMon ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

                anchors.top: true
                anchors.bottom: true
                anchors.left: true
                anchors.right: true

                Picker {
                    anchors.fill: parent
                    screen: pickWin.modelData
                    focus: pickWin.focusedMon
                }
            }
        }
    }

    // The flip: a click-through overlay on the card's monitor
    LazyLoader {
        active: Cards.flipping !== null

        StyledWindow {
            id: flipWin

            readonly property var card: Cards.flipping

            screen: Quickshell.screens.find(s => s.name === card?.front.monitor?.name) ?? Quickshell.screens[0]
            name: "cards"
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            mask: Region {}

            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            Flip {
                anchors.fill: parent
                card: flipWin.card
                monitor: flipWin.card ? flipWin.card.front.monitor : null
                onFinished: Cards.flipping = null
            }
        }
    }

    IpcHandler {
        // Pair the focused window with one you pick next
        function pair(): void {
            Cards.startPairing();
        }

        // Pair two windows by address (0x... from hyprctl clients); front shows first
        function pairWindows(front: string, back: string): void {
            const find = a => Hypr.toplevels.values.find(t => `0x${t.address}` === a || t.address === a) ?? null;
            Cards.pair(find(front), find(back));
        }

        function cancel(): void {
            Cards.cancelPairing();
        }

        function flip(): void {
            Cards.flip(null);
        }

        function unpair(): void {
            Cards.unpair(null);
        }

        // The cards as JSON: [{ front, back }] with class and title of each side
        function list(): string {
            const side = t => ({
                    address: `0x${t.address}`,
                    class: t.lastIpcObject.class,
                    title: t.title
                });
            return JSON.stringify(Cards.cards.map(c => ({
                        front: side(c.front),
                        back: side(c.back)
                    })));
        }

        target: "cards"
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "cardPair"
        description: "Pair the focused window with another into a card"
        onPressed: Cards.startPairing()
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "cardFlip"
        description: "Flip the focused card over"
        onPressed: Cards.flip(null)
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "cardUnpair"
        description: "Split the focused card back into two windows"
        onPressed: Cards.unpair(null)
    }
}
