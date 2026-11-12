pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.components.containers
import qs.components.misc
import qs.services

// The audio mixer: every app's volume, and the device each one plays to,
// over the focused monitor
Scope {
    id: root

    property bool open
    property ShellScreen screen

    function show(): void {
        const mon = Hypr.focusedMonitor;
        root.screen = Quickshell.screens.find(s => s.name === mon?.name) ?? Quickshell.screens[0];
        loader.activeAsync = true;
        root.open = true;
    }

    function hide(): void {
        root.open = false;
    }

    function toggle(): void {
        if (root.open)
            hide();
        else
            show();
    }

    LazyLoader {
        id: loader

        StyledWindow {
            screen: root.screen
            name: "mixer"
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
                onCloseRequested: root.hide()
                onHidden: loader.active = false
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

        target: "mixer"
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "mixer"
        description: "Toggle the audio mixer"
        onPressed: root.toggle()
    }
}
