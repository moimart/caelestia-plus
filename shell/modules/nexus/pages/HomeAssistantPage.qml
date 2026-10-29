pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

// Home Assistant instances, as many as you have: each with its URL and a
// long-lived access token. The lock screen's cards, the desktop widgets and the
// right bar's shortcuts (Panels → Right bar) pick one of them.
PageBase {
    id: root

    property string newName
    property string newUrl
    property string newToken
    readonly property bool canAdd: /^https?:\/\/.+/.test(newUrl.trim()) && newToken.trim().length > 20

    function statusText(id: string): string {
        const c = HomeAssistant.connection(id);
        if (!c)
            return Tr.tr("Starting…");
        if (c.connected)
            return c.version ? Tr.tr("Connected · Home Assistant %1").arg(c.version) : Tr.tr("Connected");
        return c.error || Tr.tr("Connecting…");
    }

    title: Tr.tr("Home Assistant")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        ConnectedRect {
            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: hero.implicitHeight + Tokens.padding.extraLarge * 2

            RowLayout {
                id: hero

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Tokens.padding.extraLarge
                spacing: Tokens.spacing.large

                StyledRect {
                    implicitWidth: Math.round(Tokens.font.icon.large.pointSize * 2.6)
                    implicitHeight: implicitWidth
                    radius: Tokens.rounding.large
                    color: Colours.palette.m3primaryContainer

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: "home_iot_device"
                        color: Colours.palette.m3onPrimaryContainer
                        fill: 1
                        fontStyle: Tokens.font.icon.large
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.extraSmall

                    StyledText {
                        Layout.fillWidth: true
                        text: HomeAssistant.instances.length === 1 ? Tr.tr("1 instance") : Tr.tr("%1 instances").arg(HomeAssistant.instances.length)
                        font: Tokens.font.title.medium
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Tr.tr("Each with a long-lived access token (your profile in Home Assistant → Security). The lock screen, desktop widgets and the right bar use them; tokens stay in their own files, readable only by you.")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.small
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }

        // One group per instance
        Repeater {
            model: HomeAssistant.instances

            ColumnLayout {
                id: instance

                required property var modelData
                required property int index
                readonly property var conn: HomeAssistant.connection(modelData.id)

                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall / 2

                SectionHeader {
                    text: instance.modelData.name
                }

                InfoRow {
                    first: true
                    icon: instance.conn?.connected ? "check_circle" : "error"
                    iconColour: instance.conn?.connected ? Colours.palette.m3primary : Colours.palette.m3error
                    label: root.statusText(instance.modelData.id)
                    subtext: instance.index === 0 ? Tr.tr("The default, for anything that doesn't pick one") : ""
                    value: instance.modelData.id
                }

                TextFieldRow {
                    label: Tr.tr("Name")
                    value: instance.modelData.name
                    onEditingFinished: value => {
                        if (value.trim() && value.trim() !== instance.modelData.name)
                            HomeAssistant.updateInstance(instance.modelData.id, {
                                name: value.trim()
                            }, "");
                    }
                }

                TextFieldRow {
                    label: Tr.tr("URL")
                    value: instance.modelData.url
                    onEditingFinished: value => {
                        if (/^https?:\/\//.test(value.trim()) && value.trim() !== instance.modelData.url)
                            HomeAssistant.updateInstance(instance.modelData.id, {
                                url: value.trim().replace(/\/+$/, "")
                            }, "");
                    }
                }

                TextFieldRow {
                    label: Tr.tr("Token")
                    subtext: Tr.tr("In %1. Paste a new one to replace it").arg(instance.modelData.tokenFile)
                    placeholderText: Tr.tr("Keep the current token")
                    field.echoMode: TextInput.Password
                    onEditingFinished: value => {
                        if (value.trim().length > 20) {
                            HomeAssistant.updateInstance(instance.modelData.id, {}, value.trim());
                            field.text = "";
                        }
                    }
                }

                RowButton {
                    Layout.fillWidth: true
                    last: true
                    icon: "delete"
                    text: Tr.tr("Remove %1").arg(instance.modelData.name)
                    subtext: Tr.tr("Cards and widgets using it stop updating; its token file stays")
                    onClicked: HomeAssistant.removeInstance(instance.modelData.id)
                }
            }
        }

        SectionHeader {
            text: HomeAssistant.instances.length === 0 ? Tr.tr("Add your Home Assistant") : Tr.tr("Add another")
        }

        TextFieldRow {
            first: true
            label: Tr.tr("Name")
            placeholderText: Tr.tr("Home")
            onValueEdited: value => root.newName = value
            value: root.newName
        }

        TextFieldRow {
            label: Tr.tr("URL")
            subtext: Tr.tr("Like http://homeassistant.local:8123")
            onValueEdited: value => root.newUrl = value
            value: root.newUrl
        }

        TextFieldRow {
            last: true
            label: Tr.tr("Token")
            subtext: Tr.tr("A long-lived access token")
            field.echoMode: TextInput.Password
            onValueEdited: value => root.newToken = value
            value: root.newToken
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.small

            Item {
                Layout.fillWidth: true
            }

            TextButton {
                text: Tr.tr("Add")
                type: TextButton.Filled
                disabled: !root.canAdd
                onClicked: {
                    HomeAssistant.addInstance(root.newName.trim() || Tr.tr("Home"), root.newUrl.trim(), root.newToken.trim());
                    root.newName = "";
                    root.newUrl = "";
                    root.newToken = "";
                }
            }
        }
    }
}
