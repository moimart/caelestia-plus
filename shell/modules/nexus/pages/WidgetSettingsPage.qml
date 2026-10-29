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

// One placed widget's settings, as a form drawn from its plugin's schema
// ("settings" in widget.json: [{ key, type, label, ... }]). Types: string,
// number (min, max, step, default), bool, enum (options: [{ value, label }]),
// haInstance, haEntity (domains), haCard (a dashboard card: sets dashboard,
// cardPath and card).
PageBase {
    id: root

    readonly property var instance: Widgets.instances.find(i => i.uid === Widgets.settingsUid) ?? null
    readonly property var plugin: instance ? Widgets.pluginFor(instance.type) : null
    readonly property var schema: plugin?.schema ?? []
    readonly property var settings: instance?.settings ?? ({})

    function set(key: string, value: var): void {
        Widgets.setSetting(Widgets.settingsUid, key, value);
    }

    title: plugin?.name ?? Tr.tr("Widget")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        InfoRow {
            first: true
            last: root.schema.length > 0
            icon: root.plugin?.icon ?? "widgets"
            label: root.plugin?.description ?? ""
            value: root.instance ? root.instance.screen : ""
        }

        InfoRow {
            visible: root.schema.length === 0
            last: true
            icon: "tune"
            label: Tr.tr("This widget has no settings")
        }

        Repeater {
            model: root.schema

            Loader {
                id: field

                required property var modelData
                required property int index

                Layout.fillWidth: true
                sourceComponent: ({
                        string: stringField,
                        number: numberField,
                        bool: boolField,
                        enum: enumField,
                        haInstance: instanceField,
                        haEntity: entityField,
                        haCard: cardField
                    })[modelData.type] ?? stringField

                Component {
                    id: stringField

                    TextFieldRow {
                        first: field.index === 0
                        last: field.index === root.schema.length - 1
                        label: field.modelData.label ?? field.modelData.key
                        placeholderText: field.modelData.placeholder ?? ""
                        value: root.settings[field.modelData.key] ?? ""
                        onEditingFinished: value => root.set(field.modelData.key, value.trim())
                    }
                }

                Component {
                    id: numberField

                    StepperRow {
                        first: field.index === 0
                        last: field.index === root.schema.length - 1
                        label: field.modelData.label ?? field.modelData.key
                        value: root.settings[field.modelData.key] ?? field.modelData.default ?? 0
                        from: field.modelData.min ?? 0
                        to: field.modelData.max ?? 100
                        stepSize: field.modelData.step ?? 1
                        onMoved: v => root.set(field.modelData.key, v)
                    }
                }

                Component {
                    id: boolField

                    ToggleRow {
                        first: field.index === 0
                        last: field.index === root.schema.length - 1
                        text: field.modelData.label ?? field.modelData.key
                        checked: root.settings[field.modelData.key] ?? field.modelData.default ?? false
                        onToggled: root.set(field.modelData.key, checked)
                    }
                }

                Component {
                    id: enumField

                    SelectRow {
                        first: field.index === 0
                        last: field.index === root.schema.length - 1
                        label: field.modelData.label ?? field.modelData.key
                        menuItems: enumItems.instances
                        active: enumItems.instances.find(i => i.value === (root.settings[field.modelData.key] ?? field.modelData.default)) ?? null
                        onSelected: item => root.set(field.modelData.key, item.value)

                        Variants {
                            id: enumItems

                            model: field.modelData.options ?? []

                            MenuItem {
                                required property var modelData

                                text: modelData.label ?? String(modelData.value)
                                value: modelData.value
                            }
                        }
                    }
                }

                Component {
                    id: instanceField

                    SelectRow {
                        first: field.index === 0
                        last: field.index === root.schema.length - 1
                        label: field.modelData.label ?? Tr.tr("Home Assistant")
                        subtext: HomeAssistant.instances.length === 0 ? Tr.tr("Add one in Settings → Home Assistant") : ""
                        menuItems: instanceItems.instances
                        active: instanceItems.instances.find(i => i.value === (root.settings[field.modelData.key] || HomeAssistant.defaultId)) ?? null
                        onSelected: item => root.set(field.modelData.key, item.value)

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
                }

                Component {
                    id: cardField

                    HaCardPicker {
                        first: field.index === 0
                        last: field.index === root.schema.length - 1
                        instance: root.settings.instance ?? ""
                        dashboard: root.settings.dashboard ?? ""
                        cardPath: root.settings.cardPath ?? ""
                        onPicked: (dashboard, path, card) => Widgets.setSettings(Widgets.settingsUid, {
                                dashboard: dashboard,
                                cardPath: path,
                                card: card
                            })
                    }
                }

                Component {
                    id: entityField

                    HaEntityPicker {
                        first: field.index === 0
                        last: field.index === root.schema.length - 1
                        label: field.modelData.label ?? Tr.tr("Entity")
                        // The widget's instance setting, if it has one
                        instance: root.settings.instance ?? ""
                        domains: field.modelData.domains ?? []
                        value: root.settings[field.modelData.key] ?? ""
                        onPicked: id => root.set(field.modelData.key, id)
                    }
                }
            }
        }

        RowButton {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.large - parent.spacing
            first: true
            last: true
            icon: "delete"
            text: Tr.tr("Remove this widget")
            onClicked: {
                Widgets.remove(Widgets.settingsUid);
                root.nState.closeSubPage();
            }
        }
    }
}
