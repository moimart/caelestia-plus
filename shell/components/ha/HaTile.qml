pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services
import qs.utils

// A Home Assistant entity as a tile, like Home Assistant's own tile card: its
// icon, name and state, lit while it's on. Tapping toggles, presses or runs it
// (for the domains that do something); sensors only show.
StyledRect {
    id: root

    property string instance
    property string entityId
    property string name
    property string icon
    // Taps do nothing (while arranging widgets, or for read-only places)
    property bool readOnly

    readonly property var entity: HomeAssistant.entity(instance, entityId)
    readonly property bool on: !!entity && HaIcons.isOn(entity.state)
    readonly property bool actionable: !readOnly && entityId !== "" && HaIcons.isActionable(entityId)
    readonly property string consumer: `tile-${Math.random().toString(36).slice(2)}`

    implicitWidth: 220
    implicitHeight: 72
    radius: Tokens.rounding.large
    color: on ? Colours.palette.m3primaryContainer : Colours.tPalette.m3surfaceContainer

    onInstanceChanged: HomeAssistant.watch(consumer, instance, [entityId])
    onEntityIdChanged: HomeAssistant.watch(consumer, instance, [entityId])
    Component.onCompleted: HomeAssistant.watch(consumer, instance, [entityId])
    Component.onDestruction: HomeAssistant.unwatch(consumer, instance)

    Behavior on color {
        CAnim {}
    }

    StateLayer {
        disabled: !root.actionable
        radius: root.radius
        onClicked: HomeAssistant.activate(root.instance, root.entityId)
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: Tokens.padding.medium
        spacing: Tokens.spacing.medium

        StyledRect {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: Math.min(root.height - Tokens.padding.medium * 2, 44)
            implicitHeight: implicitWidth
            radius: Tokens.rounding.full
            color: root.on ? Colours.palette.m3primary : Colours.tPalette.m3surfaceContainerHighest

            MaterialIcon {
                anchors.centerIn: parent
                text: root.icon || HaIcons.iconFor(root.entityId, root.entity)
                color: root.on ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                fill: root.on ? 1 : 0
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: root.name || root.entity?.attributes?.friendly_name || root.entityId || "Home Assistant"
                color: root.on ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurface
                font: Tokens.font.body.medium
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.entityId !== ""
                text: HaIcons.stateText(root.entity)
                color: root.on ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.medium
                elide: Text.ElideRight
            }
        }
    }
}
