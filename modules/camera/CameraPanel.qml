pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Caelestia.Config
import qs.components.containers
import qs.components.misc
import qs.services

// The camera panel: mirror, controls, presets and camera features
Scope {
    id: root

    property bool open
    property ShellScreen screen

    function show(): void {
        const focused = Hypr.focusedMonitor?.name;
        root.screen = Quickshell.screens.find(s => s.name === focused) ?? Quickshell.screens[0];
        root.open = true;
        loader.activeAsync = true;
        Camera.refreshControls();
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

    function setGestures(on: bool): void {
        GlobalConfig.camera.gestures.enabled = on;
    }

    LazyLoader {
        id: loader

        StyledWindow {
            screen: root.screen
            name: "camera"
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

    Connections {
        function onOpenPanelRequested(): void {
            root.show();
        }

        target: Camera
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

        function gestures(on: bool): void {
            root.setGestures(on);
        }

        function toggleGestures(): void {
            root.setGestures(!GlobalConfig.camera.gestures.enabled);
        }

        // { running, inUse, users, gestures, light, presence } as JSON
        function status(): string {
            return JSON.stringify({
                running: Camera.running,
                error: Camera.error,
                inUse: Camera.inUse,
                users: Camera.others,
                gestures: Camera.gesturesState,
                light: Camera.lastLight,
                presence: Camera.lastPresence
            });
        }

        function controls(): string {
            Camera.refreshControls();
            return JSON.stringify(Camera.controls);
        }

        function set(key: string, value: string): void {
            Camera.setControl(key, value === "true" ? true : value === "false" ? false : Number(value));
        }

        function presets(): string {
            return Camera.presets.map(p => p.name).join("\n");
        }

        function applyPreset(name: string): bool {
            return Camera.applyPreset(name);
        }

        target: "camera"
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "camera"
        description: "Open the camera panel"
        onPressed: root.toggle()
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "cameraGestures"
        description: "Turn camera hand gestures on or off"
        onPressed: root.setGestures(!GlobalConfig.camera.gestures.enabled)
    }
}
