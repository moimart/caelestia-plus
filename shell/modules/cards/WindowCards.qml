pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
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

    // The flip: a click-through overlay on the card's monitor. It's there
    // (empty) whenever a card shows on that monitor, not made when a flip
    // starts: a new window reaches the screen a few frames late, after the
    // back has already moved in, which flashed it. (Not while the card is
    // fullscreen, to keep games on the direct path to the display.)
    Variants {
        model: Quickshell.screens

        Scope {
            id: screenScope

            required property ShellScreen modelData
            readonly property HyprlandMonitor monitor: Hyprland.monitors.values.find(m => m.name === modelData.name) ?? null
            readonly property var flipHere: {
                const f = Cards.flipping;
                if (!f)
                    return null;
                return f.monitor === modelData.name || (!f.monitor && modelData === Quickshell.screens[0]) ? f : null;
            }
            readonly property bool cardShowing: Cards.cards.some(c => c.front.monitor?.name === modelData.name && c.front.workspace?.id === monitor?.activeWorkspace?.id && !(c.front.lastIpcObject?.fullscreen > 0))

            LazyLoader {
                active: screenScope.cardShowing || screenScope.flipHere !== null

                StyledWindow {
                    id: flipWin

                    screen: screenScope.modelData
                    name: "cards"
                    WlrLayershell.exclusionMode: ExclusionMode.Ignore
                    WlrLayershell.layer: WlrLayer.Overlay
                    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                    mask: Region {}

                    anchors.top: true
                    anchors.bottom: true
                    anchors.left: true
                    anchors.right: true

                    Loader {
                        anchors.fill: parent
                        active: screenScope.flipHere !== null

                        sourceComponent: Flip {
                            card: screenScope.flipHere
                            monitor: screenScope.monitor
                            onFinished: Cards.flipping = null
                        }
                    }
                }
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
