pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.components.containers
import qs.components.misc
import qs.services

// Launchpad, like macOS's: every app in a grid of pages, in the middle of the
// focused monitor. Typing filters it; Enter or a click launches. Apps only.
Scope {
    id: root

    property bool open
    property ShellScreen screen

    function show(): void {
        if (open)
            return;
        const mon = Hypr.focusedMonitor;
        screen = Quickshell.screens.find(s => s.name === mon?.name) ?? Quickshell.screens[0];
        open = true;
        loader.activeAsync = true;
    }

    function hide(): void {
        open = false;
    }

    function toggle(): void {
        if (open)
            hide();
        else
            show();
    }

    // Blur what's behind it, like Launchpad (Hyprland's Lua config only)
    function installRules(): void {
        if (Hypr.usingLua)
            Hypr.extras.message(`eval hl.layer_rule({ name = "caelestia-launchpad", match = { namespace = "caelestia-launchpad" }, blur = true })`);
    }

    Component.onCompleted: installRules()

    Connections {
        function onConfigReloaded(): void {
            root.installRules();
        }

        function onUsingLuaChanged(): void {
            root.installRules();
        }

        target: Hypr
    }

    LazyLoader {
        id: loader

        StyledWindow {
            screen: root.screen
            name: "launchpad"
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

        target: "launchpad"
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "launchpad"
        description: "Toggle Launchpad, the app grid"
        onPressed: root.toggle()
    }
}
