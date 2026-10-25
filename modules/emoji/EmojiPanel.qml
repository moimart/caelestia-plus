pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.components.containers
import qs.components.misc
import qs.services

// The emoji picker, opened on the focused monitor next to the pointer
Scope {
    id: root

    readonly property bool open: Emoji.panelOpen
    property ShellScreen screen
    property var anchorPoint: null

    function show(): void {
        Emoji.panelOpen = true;
    }

    function hide(): void {
        Emoji.panelOpen = false;
    }

    function toggle(): void {
        Emoji.panelOpen = !Emoji.panelOpen;
    }

    Connections {
        function onPanelOpenChanged(): void {
            if (!Emoji.panelOpen)
                return;
            Emoji.target = Hypr.activeToplevel?.address ?? "";
            Emoji.targetClass = Hypr.activeToplevel?.lastIpcObject?.class ?? "";
            Emoji.ensureLoaded();
            cursor.running = true;
        }

        target: Emoji
    }

    // Where the pointer is, to open next to it (on the focused monitor only)
    Process {
        id: cursor

        command: ["hyprctl", "cursorpos", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                const mon = Hypr.focusedMonitor;
                root.screen = Quickshell.screens.find(s => s.name === mon?.name) ?? Quickshell.screens[0];
                root.anchorPoint = null;
                try {
                    const c = JSON.parse(text);
                    const m = mon?.lastIpcObject;
                    const scale = m?.scale ?? 1;
                    const x = c.x - (m?.x ?? 0);
                    const y = c.y - (m?.y ?? 0);
                    const w = (m?.width ?? 0) / scale;
                    const h = (m?.height ?? 0) / scale;
                    if (x >= 0 && y >= 0 && x < w && y < h)
                        root.anchorPoint = Qt.point(x, y);
                } catch (e) {}
                loader.activeAsync = true;
            }
        }
    }

    LazyLoader {
        id: loader

        StyledWindow {
            screen: root.screen
            name: "emoji"
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            mask: root.open ? null : empty
            color: "transparent"

            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            Region {
                id: empty
            }

            Content {
                anchors.fill: parent
                shown: root.open
                anchorPoint: root.anchorPoint
                onCloseRequested: root.hide()
                onHidden: {
                    Emoji.flush();
                    loader.active = false;
                }
            }
        }
    }

    IpcHandler {
        function toggle(): void {
            root.toggle();
        }

        function open(): void {
            root.show();
        }

        function close(): void {
            root.hide();
        }

        function isOpen(): string {
            return root.open ? "1" : "0";
        }

        // Matching emoji as JSON: [{ emoji, name }]
        function search(query: string): string {
            Emoji.ensureLoaded();
            return JSON.stringify(Emoji.search(query).slice(0, 30).map(e => ({
                            emoji: Emoji.toned(e),
                            name: e.n
                        })));
        }

        // Types text (an emoji) into the focused window
        function type(text: string): void {
            Emoji.type(text);
        }

        target: "emoji"
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "emoji"
        description: "Toggle the emoji picker"
        onPressed: root.toggle()
    }
}
