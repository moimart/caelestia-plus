import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.services

// Runs one placed widget: loads its plugin's QML and hands it what it can use.
// A plugin's root item may declare any of these properties to receive them:
//   cursor (point, pointer relative to the widget; needs "needsCursor" in
//   widget.json), editing (bool), screen (ShellScreen), settings (object)
Loader {
    id: root

    required property var instance
    required property ShellScreen screen
    property bool editing
    // Where the widget sits on its screen, for the pointer maths
    property real screenX: instance.x
    property real screenY: instance.y

    readonly property var plugin: Widgets.pluginFor(instance.type)
    readonly property HyprlandMonitor monitor: Hypr.monitorFor(screen)
    readonly property point cursor: {
        const c = Hypr.extras.cursorPos;
        const m = monitor?.lastIpcObject;
        return Qt.point(c.x - (m?.x ?? 0) - screenX, c.y - (m?.y ?? 0) - screenY);
    }

    // Which of those the plugin takes, read once when it loads
    property var accepts: ({})

    asynchronous: true
    source: plugin?.url ?? ""
    onLoaded: accepts = {
        cursor: "cursor" in item,
        editing: "editing" in item,
        screen: "screen" in item,
        settings: "settings" in item
    }

    Binding {
        target: root.item
        property: "cursor"
        value: root.cursor
        when: root.status === Loader.Ready && root.plugin?.needsCursor && root.accepts.cursor === true
    }

    Binding {
        target: root.item
        property: "editing"
        value: root.editing
        when: root.status === Loader.Ready && root.accepts.editing === true
    }

    Binding {
        target: root.item
        property: "screen"
        value: root.screen
        when: root.status === Loader.Ready && root.accepts.screen === true
    }

    Binding {
        target: root.item
        property: "settings"
        value: root.instance.settings ?? {}
        when: root.status === Loader.Ready && root.accepts.settings === true
    }
}
