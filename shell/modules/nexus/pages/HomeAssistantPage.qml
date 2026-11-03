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

        // Surface Dial modes: an entity's level, turned by the dial
        SectionHeader {
            visible: HomeAssistant.instances.length > 0
            text: Tr.tr("Surface Dial")
        }

        Repeater {
            model: HomeAssistant.dialControls

            ColumnLayout {
                id: control

                required property var modelData
                readonly property var domain: SurfaceDial.haDomain(modelData)
                readonly property var state: HomeAssistant.entity(modelData.instance, modelData.entity)
                // Temperatures and numbers step in their own units; the rest in percent
                readonly property real unitStep: domain && state && !["light", "media_player", "cover", "valve", "fan"].includes(modelData.entity.split(".")[0]) ? domain.step(state) : 1

                Layout.fillWidth: true
                Layout.bottomMargin: Tokens.spacing.small
                spacing: Tokens.spacing.extraSmall / 2

                // To turn another entity, remove this and add that one
                InfoRow {
                    first: true
                    icon: control.domain?.icon ?? "error"
                    iconColour: control.domain ? Colours.palette.m3onSurfaceVariant : Colours.palette.m3error
                    label: SurfaceDial.info(`ha:${control.modelData.id}`).name
                    subtext: control.modelData.entity
                    value: !control.state ? Tr.tr("Not found") : control.domain?.available && !control.domain.available(control.state) ? Tr.tr("Unavailable now") : control.domain ? `${control.domain.value(control.state)}${control.domain.unit}` : ""
                }

                SelectRow {
                    visible: HomeAssistant.instances.length > 1
                    label: Tr.tr("Instance")
                    menuItems: instanceItems.instances
                    active: instanceItems.instances.find(i => i.value === control.modelData.instance) ?? null
                    onSelected: item => HomeAssistant.updateDialControl(control.modelData.id, {
                            instance: item.value
                        })

                    Variants {
                        id: instanceItems

                        model: HomeAssistant.instances

                        MenuItem {
                            required property var modelData

                            text: modelData.name
                            value: modelData.id
                        }
                    }
                }

                TextFieldRow {
                    label: Tr.tr("Name")
                    subtext: Tr.tr("In the toast when the dial switches to it")
                    placeholderText: control.state?.attributes?.friendly_name ?? control.modelData.entity
                    value: control.modelData.name ?? ""
                    onEditingFinished: value => HomeAssistant.updateDialControl(control.modelData.id, {
                            name: value.trim()
                        })
                }

                StepperRow {
                    label: Tr.tr("Step")
                    subtext: control.domain ? Tr.tr("%1 per step of the dial, in %2").arg(control.domain.what).arg(control.domain.unit || Tr.tr("its units")) : Tr.tr("The dial can't turn this entity")
                    value: SurfaceDial.stepOf(control.modelData)
                    from: control.unitStep
                    to: control.unitStep * 50
                    stepSize: control.unitStep
                    onMoved: v => HomeAssistant.updateDialControl(control.modelData.id, {
                            step: v
                        })
                }

                RowButton {
                    Layout.fillWidth: true
                    last: true
                    icon: "delete"
                    text: Tr.tr("Remove")
                    subtext: Tr.tr("The dial stops offering it")
                    onClicked: {
                        const mode = `ha:${control.modelData.id}`;
                        GlobalConfig.surfaceDial.modes = GlobalConfig.surfaceDial.modes.filter(m => m !== mode);
                        HomeAssistant.removeDialControl(control.modelData.id);
                    }
                }
            }
        }

        HaEntityPicker {
            visible: HomeAssistant.instances.length > 0
            first: true
            last: true
            label: Tr.tr("Add a dial control")
            instance: HomeAssistant.defaultId
            domains: SurfaceDial.haSupportedDomains
            value: ""
            onPicked: id => {
                const mode = `ha:${HomeAssistant.addDialControl(HomeAssistant.defaultId, id)}`;
                GlobalConfig.surfaceDial.modes = SurfaceDial.allModes.filter(m => m === mode || GlobalConfig.surfaceDial.modes.includes(m));
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
