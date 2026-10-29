pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

// The right bar: on or off, the volume on it, and its action buttons (which,
// and in what order), built-in ones and action plugins.
PageBase {
    id: root

    readonly property list<string> chosen: GlobalConfig.rightBar.actions
    // The chosen actions in their order, then the rest
    readonly property var rows: [...chosen.map(id => BarActions.find(id)).filter(a => a), ...BarActions.all.filter(a => !chosen.includes(a.id))]

    // Which instance new Home Assistant shortcuts come from
    property string shortcutInstance: HomeAssistant.defaultId

    // A Home Assistant shortcut, put on the bar at once
    function addShortcut(entityId: string, name: string): void {
        const id = HomeAssistant.addShortcut(shortcutInstance, entityId, name);
        setChosen([...chosen.filter(c => c !== id), id]);
    }

    function removeShortcut(id: string): void {
        setChosen(chosen.filter(c => c !== id));
        HomeAssistant.removeShortcut(id);
    }

    function setChosen(ids: var): void {
        GlobalConfig.rightBar.actions = ids;
    }

    function toggle(id: string, on: bool): void {
        setChosen(on ? [...chosen.filter(c => c !== id), id] : chosen.filter(c => c !== id));
    }

    function move(id: string, by: int): void {
        const ids = chosen.slice();
        const i = ids.indexOf(id), j = i + by;
        if (i < 0 || j < 0 || j >= ids.length)
            return;
        [ids[i], ids[j]] = [ids[j], ids[i]];
        setChosen(ids);
    }

    title: Tr.tr("Right bar")
    isSubPage: true

    Component.onCompleted: BarActions.rescan()

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: Tr.tr("General")
        }

        ToggleRow {
            first: true
            text: Tr.trCtx("Enabled", "toggle label")
            subtext: Tr.tr("A bar on the right edge, as thick as the left one")
            checked: GlobalConfig.rightBar.enabled
            onToggled: GlobalConfig.rightBar.enabled = checked
        }

        ToggleRow {
            text: Tr.tr("Brightness")
            subtext: Tr.tr("Each display's own, where it can be set (DDC monitors, laptop screens)")
            checked: GlobalConfig.rightBar.brightness
            onToggled: GlobalConfig.rightBar.brightness = checked
        }

        ToggleRow {
            text: Tr.tr("Volume")
            subtext: Tr.tr("The output volume, always on the bar")
            checked: GlobalConfig.rightBar.volume
            onToggled: GlobalConfig.rightBar.volume = checked
        }

        ToggleRow {
            last: true
            text: Tr.tr("Microphone")
            subtext: Tr.tr("Its volume as well")
            checked: GlobalConfig.rightBar.microphone
            onToggled: GlobalConfig.rightBar.microphone = checked
        }

        SectionHeader {
            text: Tr.tr("Actions")
        }

        Repeater {
            model: root.rows

            ConnectedRect {
                id: row

                required property var modelData
                required property int index
                readonly property int position: root.chosen.indexOf(modelData.id)
                readonly property bool shown: position >= 0

                Layout.fillWidth: true
                first: index === 0
                last: index === root.rows.length - 1
                implicitHeight: layout.implicitHeight + Tokens.padding.medium * 2

                RowLayout {
                    id: layout

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Tokens.padding.largeIncreased
                    anchors.rightMargin: Tokens.padding.largeIncreased
                    spacing: Tokens.spacing.medium

                    MaterialIcon {
                        text: row.modelData.icon
                        color: row.shown ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.medium
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: row.modelData.plugin ? Tr.tr("%1 (plugin)").arg(row.modelData.name) : row.modelData.name
                            font: Tokens.font.body.small
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            visible: !!row.modelData.description
                            text: row.modelData.description
                            color: Colours.palette.m3outline
                            font: Tokens.font.label.small
                            elide: Text.ElideRight
                        }
                    }

                    // Order, for the ones on the bar
                    IconButton {
                        visible: row.shown
                        type: IconButton.Text
                        icon: "arrow_upward"
                        disabled: row.position <= 0
                        onClicked: root.move(row.modelData.id, -1)
                    }

                    IconButton {
                        visible: row.shown
                        type: IconButton.Text
                        icon: "arrow_downward"
                        disabled: row.position >= root.chosen.length - 1
                        onClicked: root.move(row.modelData.id, 1)
                    }

                    // Home Assistant shortcuts can go altogether
                    IconButton {
                        visible: !!row.modelData.ha
                        type: IconButton.Text
                        icon: "delete"
                        onClicked: root.removeShortcut(row.modelData.id)
                    }

                    StyledSwitch {
                        checked: row.shown
                        onToggled: root.toggle(row.modelData.id, checked)
                    }
                }
            }
        }

        // Buttons that act like tapping a Home Assistant entity
        SectionHeader {
            visible: HomeAssistant.instances.length > 0
            text: Tr.tr("Home Assistant shortcuts")
        }

        InfoRow {
            visible: HomeAssistant.instances.length > 0
            first: true
            icon: "touch_app"
            label: Tr.tr("Pick an entity or a dashboard card")
            subtext: Tr.tr("It joins the actions above and acts like tapping it: toggle a light, press a button, run a script")
        }

        SelectRow {
            visible: HomeAssistant.instances.length > 1
            label: Tr.tr("From")
            menuItems: shortcutInstanceItems.instances
            active: shortcutInstanceItems.instances.find(i => i.value === root.shortcutInstance) ?? null
            onSelected: item => root.shortcutInstance = item.value

            Variants {
                id: shortcutInstanceItems

                model: HomeAssistant.instances

                MenuItem {
                    required property var modelData

                    text: modelData.name
                    value: modelData.id
                }
            }
        }

        HaEntityPicker {
            visible: HomeAssistant.instances.length > 0
            first: false
            last: true
            label: Tr.tr("Add an entity")
            instance: root.shortcutInstance
            domains: ["light", "switch", "input_boolean", "fan", "lock", "cover", "button", "input_button", "scene", "script", "automation", "media_player"]
            onPicked: id => root.addShortcut(id, "")
        }

        StyledText {
            visible: HomeAssistant.instances.length > 0
            Layout.topMargin: Tokens.spacing.medium
            Layout.leftMargin: Tokens.padding.large
            text: Tr.tr("Or a card from a dashboard (its entity, as its tap does):")
            color: Colours.palette.m3outline
            font: Tokens.font.label.medium
        }

        HaCardPicker {
            visible: HomeAssistant.instances.length > 0
            instance: root.shortcutInstance
            onPicked: (dashboard, path, card) => {
                const entity = card?.entity ?? card?.tap_action?.target?.entity_id ?? "";
                if (entity)
                    root.addShortcut(entity, card?.name ?? "");
            }
        }

        InfoRow {
            visible: HomeAssistant.instances.length === 0
            Layout.topMargin: Tokens.spacing.large - parent.spacing
            first: true
            last: true
            icon: "home_iot_device"
            label: Tr.tr("Home Assistant shortcuts")
            subtext: Tr.tr("Add your Home Assistant in Settings → Home Assistant first")
        }

        InfoRow {
            Layout.topMargin: Tokens.spacing.large - parent.spacing
            first: true
            last: true
            icon: "extension"
            label: Tr.tr("Your own actions")
            value: "~/.config/caelestia/plugins/actions"
        }
    }
}
