pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.services

// The widgets placed on one screen, drawn on the desktop above the wallpaper.
// Hidden while editing, when the editor shows them above everything instead.
Item {
    id: root

    required property ShellScreen screen

    visible: GlobalConfig.widgets.enabled && !Widgets.editing

    Repeater {
        // uids, so moving or resizing one widget doesn't reload the others
        model: ScriptModel {
            values: Widgets.instancesOn(root.screen.name).map(i => i.uid)
        }

        WidgetHost {
            required property string modelData
            readonly property var inst: Widgets.instances.find(i => i.uid === modelData) ?? null

            active: inst !== null
            instance: inst ?? ({})
            screen: root.screen
            x: inst?.x ?? 0
            y: inst?.y ?? 0
            width: inst?.width ?? 0
            height: inst?.height ?? 0
        }
    }
}
