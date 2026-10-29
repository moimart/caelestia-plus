pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus.common

// One lock screen card (LockLayout.editSide / editIndex): where it sits, and
// for Home Assistant ones what they show.
PageBase {
    id: root

    readonly property string side: LockLayout.editSide
    readonly property int index: LockLayout.editIndex
    readonly property var card: LockLayout.editCard ?? ({})
    readonly property var info: LockLayout.typeInfo(card.type ?? "")
    readonly property var cards: side === "left" ? LockLayout.left : LockLayout.right
    readonly property string instance: card.instance ?? ""

    // The energy card's sensors
    readonly property var energyFields: [
        {
            key: "solar",
            label: Tr.tr("Solar power")
        },
        {
            key: "home",
            label: Tr.tr("Home power")
        },
        {
            key: "grid",
            label: Tr.tr("Grid power")
        },
        {
            key: "battery_soc",
            label: Tr.tr("Battery charge")
        },
        {
            key: "battery_power",
            label: Tr.tr("Battery power")
        },
        {
            key: "autarky",
            label: Tr.tr("Autarky")
        }
    ]
    property string energyField: "solar"

    function set(changes: var): void {
        LockLayout.update(side, index, changes);
    }

    title: info.name
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        InfoRow {
            first: true
            last: !root.info.ha
            icon: root.info.icon
            label: root.side === "left" ? Tr.tr("Left column, card %1 of %2").arg(root.index + 1).arg(root.cards.length) : Tr.tr("Right column, card %1 of %2").arg(root.index + 1).arg(root.cards.length)
            subtext: root.info.ha ? "" : Tr.tr("Built in: nothing to set up")
        }

        // Where it comes from
        SelectRow {
            visible: root.info.ha && HomeAssistant.instances.length > 1
            label: Tr.tr("Home Assistant")
            menuItems: instanceItems.instances
            active: instanceItems.instances.find(i => i.value === (root.instance || HomeAssistant.defaultId)) ?? null
            onSelected: item => root.set({
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
            visible: ["camera", "haEntity"].includes(root.card.type)
            label: Tr.tr("Name")
            placeholderText: Tr.tr("The entity's own")
            value: root.card.name ?? ""
            onEditingFinished: value => root.set({
                    name: value.trim()
                })
        }

        TextFieldRow {
            visible: ["entities", "energy"].includes(root.card.type)
            label: Tr.tr("Title")
            placeholderText: root.card.type === "energy" ? Tr.tr("Energy") : Tr.tr("None")
            value: root.card.title ?? ""
            onEditingFinished: value => root.set({
                    title: value.trim()
                })
        }

        StepperRow {
            visible: root.card.type === "camera"
            label: Tr.tr("Refresh every (seconds)")
            value: root.card.interval ?? 5
            from: 2
            to: 60
            onMoved: v => root.set({
                    interval: v
                })
        }

        // Camera and entity: the one entity
        HaEntityPicker {
            visible: ["camera", "haEntity"].includes(root.card.type)
            first: false
            last: true
            label: root.card.type === "camera" ? Tr.tr("Camera") : Tr.tr("Entity")
            instance: root.instance
            domains: root.card.type === "camera" ? ["camera"] : []
            value: root.card.entity ?? ""
            onPicked: id => root.set({
                    entity: id
                })
        }

        // Entities: a list
        SectionHeader {
            visible: root.card.type === "entities"
            text: Tr.tr("Entities")
        }

        Repeater {
            model: root.card.type === "entities" ? (root.card.entities ?? []) : []

            RowButton {
                required property var modelData
                required property int index
                readonly property string entityId: typeof modelData === "string" ? modelData : modelData.entity
                readonly property var entity: HomeAssistant.entity(root.instance, entityId)

                Layout.fillWidth: true
                first: index === 0
                icon: HaIcons.iconFor(entityId, entity)
                text: modelData.name ?? entity?.attributes?.friendly_name ?? entityId
                subtext: `${entityId} · ${HaIcons.stateText(entity)}`
                trailingIcon: "delete"
                onClicked: {
                    const list = (root.card.entities ?? []).slice();
                    list.splice(index, 1);
                    root.set({
                        entities: list
                    });
                }
            }
        }

        HaEntityPicker {
            visible: root.card.type === "entities"
            first: (root.card.entities ?? []).length === 0
            last: true
            label: Tr.tr("Add an entity")
            instance: root.instance
            onPicked: id => {
                const list = root.card.entities ?? [];
                if (!list.some(e => (typeof e === "string" ? e : e.entity) === id))
                    root.set({
                        entities: [...list, id]
                    });
            }
        }

        // Energy: a sensor per figure
        SectionHeader {
            visible: root.card.type === "energy"
            text: Tr.tr("Sensors")
        }

        Repeater {
            model: root.card.type === "energy" ? root.energyFields : []

            RowButton {
                required property var modelData
                required property int index

                Layout.fillWidth: true
                first: index === 0
                icon: root.energyField === modelData.key ? "edit" : "bolt"
                text: modelData.label
                subtext: root.card[modelData.key] ? `${root.card[modelData.key]} · ${HaIcons.stateText(HomeAssistant.entity(root.instance, root.card[modelData.key]))}` : Tr.tr("Not shown")
                trailingIcon: root.card[modelData.key] ? "close" : ""
                onClicked: {
                    // Tapping the one being picked clears it
                    if (root.energyField === modelData.key && root.card[modelData.key]) {
                        const changes = {};
                        changes[modelData.key] = undefined;
                        root.set(changes);
                    }
                    root.energyField = modelData.key;
                }
            }
        }

        HaEntityPicker {
            visible: root.card.type === "energy"
            first: false
            last: true
            label: root.energyFields.find(f => f.key === root.energyField)?.label ?? ""
            instance: root.instance
            domains: ["sensor"]
            value: root.card[root.energyField] ?? ""
            onPicked: id => {
                const changes = {};
                changes[root.energyField] = id;
                root.set(changes);
            }
        }

        // A dashboard card
        SectionHeader {
            visible: root.card.type === "haCard"
            text: Tr.tr("Dashboard card")
        }

        HaCardPicker {
            visible: root.card.type === "haCard"
            instance: root.instance
            dashboard: root.card.dashboard ?? ""
            cardPath: root.card.cardPath ?? ""
            onPicked: (dashboard, path, card) => root.set({
                    dashboard: dashboard,
                    cardPath: path,
                    card: card
                })
        }

        // Where it sits
        SectionHeader {
            text: Tr.tr("Place")
        }

        RowButton {
            Layout.fillWidth: true
            first: true
            disabled: root.index <= 0
            icon: "arrow_upward"
            text: Tr.tr("Move up")
            onClicked: LockLayout.move(root.side, root.index, -1)
        }

        RowButton {
            Layout.fillWidth: true
            disabled: root.index >= root.cards.length - 1
            icon: "arrow_downward"
            text: Tr.tr("Move down")
            onClicked: LockLayout.move(root.side, root.index, 1)
        }

        RowButton {
            Layout.fillWidth: true
            icon: root.side === "left" ? "arrow_forward" : "arrow_back"
            text: root.side === "left" ? Tr.tr("Move to the right column") : Tr.tr("Move to the left column")
            onClicked: LockLayout.moveAcross(root.side, root.index)
        }

        RowButton {
            Layout.fillWidth: true
            last: true
            icon: "delete"
            text: Tr.tr("Remove from the lock screen")
            onClicked: {
                LockLayout.remove(root.side, root.index);
                root.nState.closeSubPage();
            }
        }
    }
}
