pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

// Solar / home / grid / battery at a glance, standing in for the Prism and
// Helios energy cards. Negative battery power means charging and negative
// grid power means exporting, unless the card sets *_invert.
StyledRect {
    id: root

    required property var card
    required property var ha

    readonly property real solar: num(card.solar)
    readonly property real home: num(card.home)
    readonly property real grid: num(card.grid) * (card.grid_invert ? -1 : 1)
    readonly property real batteryPower: num(card.battery_power) * (card.battery_invert ? -1 : 1)
    readonly property real soc: num(card.battery_soc)
    readonly property real autarky: num(card.autarky)

    function num(id: string): real {
        const s = id ? ha.entity(id) : null;
        const v = parseFloat(s?.state);
        return isNaN(v) ? NaN : v;
    }

    function power(watts: real): string {
        if (isNaN(watts))
            return "–";
        const w = Math.abs(watts);
        return w >= 1000 ? `${(w / 1000).toFixed(1)} kW` : `${Math.round(w)} W`;
    }

    implicitHeight: layout.implicitHeight + layout.anchors.margins * 2
    radius: Tokens.rounding.extraLarge
    color: Colours.tPalette.m3surfaceContainer

    ColumnLayout {
        id: layout

        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.medium

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.small
            spacing: Tokens.spacing.small

            MaterialIcon {
                text: "solar_power"
                color: Colours.palette.m3primary
            }

            StyledText {
                Layout.fillWidth: true
                text: root.card.title ?? qsTr("Energy")
                color: Colours.palette.m3primary
                font: Tokens.font.title.small
                elide: Text.ElideRight
            }

            StyledText {
                visible: !isNaN(root.autarky)
                text: qsTr("%1% autarky").arg(Math.round(root.autarky))
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.small
            }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            rowSpacing: Tokens.spacing.small
            columnSpacing: Tokens.spacing.small

            Stat {
                visible: !!root.card.solar
                icon: "wb_sunny"
                label: qsTr("Solar")
                value: root.power(root.solar)
                accent: root.solar > 0
            }

            Stat {
                visible: !!root.card.home
                icon: "home"
                label: qsTr("Home")
                value: root.power(root.home)
            }

            Stat {
                visible: !!root.card.grid
                icon: "electrical_services"
                label: root.grid < 0 ? qsTr("Exporting") : qsTr("Grid")
                value: root.power(root.grid)
            }

            Stat {
                visible: !!root.card.battery_soc
                icon: root.batteryPower < 0 ? "battery_charging_full" : "battery_full"
                label: isNaN(root.soc) ? qsTr("Battery") : qsTr("Battery %1%").arg(Math.round(root.soc))
                value: root.batteryPower < 0 ? qsTr("+%1").arg(root.power(root.batteryPower)) : root.power(root.batteryPower)
                accent: root.batteryPower < 0
                fill: isNaN(root.soc) ? 0 : root.soc / 100
            }
        }
    }

    component Stat: StyledRect {
        id: stat

        property string icon
        property string label
        property string value
        property bool accent
        property real fill

        Layout.fillWidth: true
        Layout.preferredWidth: 1
        implicitHeight: statLayout.implicitHeight + Tokens.padding.medium * 2
        radius: Tokens.rounding.large
        color: Colours.tPalette.m3surfaceContainerHigh
        clip: true

        StyledRect {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width * stat.fill
            radius: stat.radius
            color: Qt.alpha(Colours.palette.m3primary, 0.15)
        }

        RowLayout {
            id: statLayout

            anchors.fill: parent
            anchors.margins: Tokens.padding.medium
            spacing: Tokens.spacing.small

            MaterialIcon {
                text: stat.icon
                color: stat.accent ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                fill: stat.accent ? 1 : 0
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: stat.value
                    font: Tokens.font.title.small
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: stat.label
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.small
                    elide: Text.ElideRight
                }
            }
        }
    }
}
