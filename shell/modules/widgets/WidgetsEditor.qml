pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Caelestia.Config
import Caelestia.I18n
import qs.components.containers
import qs.components.misc
import qs.services
import qs.modules.nexus

// Placing and resizing desktop widgets, on every monitor that has a desktop
Scope {
    id: root

    LazyLoader {
        active: Widgets.editing

        Variants {
            model: Screens.screens.filter(s => GlobalConfig.forScreen(s.name).background.enabled)

            StyledWindow {
                id: win

                required property ShellScreen modelData
                readonly property bool focusedMon: Hypr.focusedMonitor?.name === modelData.name

                screen: modelData
                name: "widgets-editor"
                WlrLayershell.exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: focusedMon ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

                anchors.top: true
                anchors.bottom: true
                anchors.left: true
                anchors.right: true

                EditView {
                    anchors.fill: parent
                    screen: win.modelData
                    focus: win.focusedMon
                }
            }
        }
    }

    // A widget's settings asked for (its button in the editor, a widget
    // just placed that needs setting up, the IPC call): Settings, on its page
    Connections {
        function onSettingsRequested(uid: string): void {
            WindowFactory.create(null, {
                initialPage: PageRegistry.pages.findIndex(p => p.label === Tr.tr("Plugins")),
                initialSubPage: 1
            });
        }

        target: Widgets
    }

    IpcHandler {
        // Place and resize widgets
        function edit(): void {
            Widgets.rescan();
            Widgets.editing = true;
        }

        function done(): void {
            Widgets.editing = false;
        }

        function toggle(): void {
            if (!Widgets.editing)
                Widgets.rescan();
            Widgets.editing = !Widgets.editing;
        }

        // Add a widget of a plugin type ("eyes") to a monitor ("DP-1"), centred
        function add(type: string, screen: string): void {
            Widgets.add(type, Quickshell.screens.find(s => s.name === screen) ?? null);
        }

        function remove(uid: string): void {
            Widgets.remove(uid);
        }

        // Move/resize a widget, in that screen's logical pixels
        function place(uid: string, x: int, y: int, width: int, height: int): void {
            Widgets.update(uid, {
                x: x,
                y: y,
                width: width,
                height: height
            });
        }

        // Replace a widget's settings with a JSON object, e.g. {"style": "orbit"}
        function configure(uid: string, json: string): void {
            try {
                Widgets.update(uid, {
                    settings: JSON.parse(json)
                });
            } catch (e) {
                console.warn(`widgets.configure: ${e}`);
            }
        }

        // Opens a placed widget's settings (Settings → Plugins)
        function settings(uid: string): void {
            Widgets.openSettings(uid);
        }

        function rescan(): void {
            Widgets.rescan();
        }

        // { plugins: [...], widgets: [...] } as JSON
        function list(): string {
            return JSON.stringify({
                plugins: Widgets.plugins.map(p => ({
                            id: p.id,
                            name: p.name,
                            description: p.description,
                            builtin: p.builtin,
                            dir: p.dir
                        })),
                widgets: Widgets.instances
            });
        }

        target: "widgets"
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "widgets"
        description: "Place and resize desktop widgets"
        onPressed: {
            if (!Widgets.editing)
                Widgets.rescan();
            Widgets.editing = !Widgets.editing;
        }
    }
}
