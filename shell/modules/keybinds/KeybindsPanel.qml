pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Caelestia.Config
import qs.components.containers
import qs.components.misc
import qs.services
import qs.modules.nexus

// Keyboard shortcuts cheatsheet, opened on the focused monitor
Scope {
    id: root

    readonly property bool open: Keybinds.panelOpen
    property ShellScreen screen

    function show(): void {
        if (GlobalConfig.keybinds.enabled)
            Keybinds.panelOpen = true;
    }

    function hide(): void {
        Keybinds.panelOpen = false;
    }

    function toggle(): void {
        if (root.open)
            hide();
        else
            show();
    }

    function openSettings(): void {
        WindowFactory.create(null, {
            initialPage: PageRegistry.pages.findIndex(p => p.icon === "keyboard")
        });
    }

    Connections {
        function onPanelOpenChanged(): void {
            if (!Keybinds.panelOpen)
                return;
            const focused = Hypr.focusedMonitor?.name;
            root.screen = Quickshell.screens.find(s => s.name === focused) ?? Quickshell.screens[0];
            loader.activeAsync = true;
        }

        target: Keybinds
    }

    LazyLoader {
        id: loader

        StyledWindow {
            id: win

            screen: root.screen
            name: "keybinds"
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            mask: root.open ? null : empty

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

        // Opens the settings window on the keyboard shortcuts page
        function settings(): void {
            root.openSettings();
        }

        function reload(): void {
            Keybinds.reload();
        }

        // The binds as JSON (what the panel shows), for scripts and agents
        function list(): string {
            Keybinds.ensureLoaded();
            return JSON.stringify(Keybinds.visibleBinds.map(b => ({
                        combo: b.combo,
                        title: b.title,
                        category: b.category,
                        owner: b.owner,
                        note: b.note,
                        detail: b.detail
                    })));
        }

        target: "keybinds"
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "keybinds"
        description: "Toggle the keyboard shortcuts panel"
        onPressed: root.toggle()
    }
}
