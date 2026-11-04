pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.services

// The widgets docked in one of a screen's bars (Widgets.dockedOn), top to
// bottom in a pill as wide as the bar's other groups. Nothing when there are
// none, or when desktop widgets are off.
StyledRect {
    id: root

    required property ShellScreen screen
    // "left" or "right"
    required property string side

    readonly property list<string> uids: GlobalConfig.widgets.enabled ? Widgets.dockedOn(screen.name, side).map(i => i.uid) : []

    visible: uids.length > 0
    implicitWidth: Tokens.sizes.bar.innerWidth
    implicitHeight: visible ? column.implicitHeight + Tokens.padding.small * 2 : 0
    radius: Tokens.rounding.full
    color: Colours.tPalette.m3surfaceContainer

    Column {
        id: column

        anchors.centerIn: parent
        spacing: Tokens.spacing.small

        Repeater {
            // uids, so changing one widget doesn't reload the others
            model: ScriptModel {
                values: root.uids
            }

            WidgetHost {
                required property string modelData
                readonly property var inst: Widgets.instances.find(i => i.uid === modelData) ?? null

                active: inst !== null
                instance: inst ?? ({})
                screen: root.screen
                bar: root.side
                width: Tokens.sizes.bar.innerWidth
            }
        }
    }
}
