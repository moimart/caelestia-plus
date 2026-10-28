pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
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

                    StyledSwitch {
                        checked: row.shown
                        onToggled: root.toggle(row.modelData.id, checked)
                    }
                }
            }
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
