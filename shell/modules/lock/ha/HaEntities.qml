pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

// A titled list of entities with their state, like Lovelace's entities card.
// Lights show brightness when on. Display only: rows can't be toggled.
StyledRect {
    id: root

    required property var card
    required property var ha

    readonly property var icons: ({
            light: "lightbulb",
            switch: "toggle_on",
            sensor: "sensors",
            binary_sensor: "sensors",
            lock: "lock",
            cover: "blinds",
            climate: "thermostat",
            media_player: "speaker",
            person: "person",
            fan: "mode_fan"
        })

    implicitHeight: layout.implicitHeight + layout.anchors.margins * 2
    radius: Tokens.rounding.extraLarge
    color: Colours.tPalette.m3surfaceContainer

    ColumnLayout {
        id: layout

        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.small

        StyledText {
            visible: !!root.card.title
            Layout.leftMargin: Tokens.padding.small
            text: root.card.title ?? ""
            color: Colours.palette.m3primary
            font: Tokens.font.title.small
        }

        Repeater {
            model: root.card.entities ?? []

            StyledRect {
                id: row

                required property var modelData

                readonly property string entityId: typeof modelData === "string" ? modelData : modelData.entity
                readonly property var entity: root.ha.entity(entityId)
                readonly property string domain: entityId.split(".")[0]
                readonly property bool on: ["on", "open", "unlocked", "playing", "home"].includes(entity?.state)
                readonly property string stateText: {
                    const s = entity?.state;
                    if (s === undefined)
                        return "…";
                    const a = entity.attributes ?? {};
                    if (domain === "light" && s === "on" && a.brightness)
                        return `${Math.round(a.brightness / 2.55)}%`;
                    return a.unit_of_measurement ? `${s} ${a.unit_of_measurement}` : s;
                }

                Layout.fillWidth: true
                implicitHeight: rowLayout.implicitHeight + Tokens.padding.medium * 2
                radius: Tokens.rounding.large
                color: on ? Colours.palette.m3secondaryContainer : Colours.tPalette.m3surfaceContainerHigh

                Behavior on color {
                    CAnim {}
                }

                RowLayout {
                    id: rowLayout

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    spacing: Tokens.spacing.medium

                    MaterialIcon {
                        text: (typeof row.modelData === "object" && row.modelData.icon) || root.icons[row.domain] || "radio_button_checked"
                        color: row.on ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                        fill: row.on ? 1 : 0
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: (typeof row.modelData === "object" && row.modelData.name) || row.entity?.attributes?.friendly_name || row.entityId
                        color: row.on ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                        font: Tokens.font.body.medium
                        elide: Text.ElideRight
                    }

                    StyledText {
                        text: row.stateText
                        color: row.on ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.small
                    }
                }
            }
        }
    }
}
