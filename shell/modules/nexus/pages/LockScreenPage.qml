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

// The lock screen: what its two columns show around the clock and password
// (services/LockLayout), and how it behaves. Tapping a card opens it (sub-page 1).
PageBase {
    id: root

    function describe(card: var): string {
        const info = LockLayout.typeInfo(card.type);
        const entity = card.entity ? HomeAssistant.entity(card.instance ?? "", card.entity) : null;
        return card.name || card.title || card.card?.title || card.card?.name || entity?.attributes?.friendly_name || info.name;
    }

    function details(card: var): string {
        const info = LockLayout.typeInfo(card.type);
        const parts = [info.name];
        if (card.entity)
            parts.push(card.entity);
        else if (card.entities)
            parts.push(card.entities.length === 1 ? Tr.tr("1 entity") : Tr.tr("%1 entities").arg(card.entities.length));
        else if (card.card)
            parts.push(card.card.type);
        if (info.ha && HomeAssistant.instances.length > 1)
            parts.push(HomeAssistant.instances.find(i => i.id === card.instance)?.name ?? card.instance);
        return parts.filter((p, i) => p && (i > 0 || p !== root.describe(card))).join(" · ");
    }

    title: Tr.tr("Lock screen")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        InfoRow {
            first: true
            last: true
            icon: LockLayout.isDefault ? "lock" : "dashboard_customize"
            label: LockLayout.isDefault ? Tr.tr("The classic layout") : Tr.tr("Your layout")
            subtext: Tr.tr("The clock and password stay in the middle; each side shows its cards top to bottom. Home Assistant cards only show: nothing on the lock screen can be pressed.")
        }

        Repeater {
            model: [
                {
                    side: "left",
                    label: Tr.tr("Left column")
                },
                {
                    side: "right",
                    label: Tr.tr("Right column")
                }
            ]

            ColumnLayout {
                id: column

                required property var modelData
                readonly property string side: modelData.side
                readonly property var cards: side === "left" ? LockLayout.left : LockLayout.right

                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall / 2

                SectionHeader {
                    text: column.modelData.label
                }

                Repeater {
                    model: column.cards

                    NavRow {
                        required property var modelData
                        required property int index

                        Layout.fillWidth: true
                        first: index === 0
                        icon: LockLayout.typeInfo(modelData.type).icon
                        text: root.describe(modelData)
                        subtext: root.details(modelData)
                        onClicked: {
                            LockLayout.editSide = column.side;
                            LockLayout.editIndex = index;
                            root.nState.openSubPage(1);
                        }
                    }
                }

                SelectRow {
                    first: column.cards.length === 0
                    last: true
                    label: Tr.tr("Add a card")
                    fallbackText: Tr.tr("Pick one")
                    fallbackIcon: "add"
                    menuItems: typeItems.instances
                    active: null
                    onSelected: item => {
                        const index = LockLayout.add(column.side, item.value);
                        // Home Assistant cards need setting up
                        if (LockLayout.typeInfo(item.value).ha) {
                            LockLayout.editSide = column.side;
                            LockLayout.editIndex = index;
                            root.nState.openSubPage(1);
                        }
                    }

                    Variants {
                        id: typeItems

                        // Home Assistant ones only with an instance to show
                        model: LockLayout.types.filter(t => !t.ha || HomeAssistant.instances.length > 0)

                        MenuItem {
                            required property var modelData

                            icon: modelData.icon
                            text: modelData.name
                            value: modelData.type
                        }
                    }
                }
            }
        }

        RowButton {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.medium
            first: true
            last: true
            visible: !LockLayout.isDefault
            icon: "restart_alt"
            text: Tr.tr("Back to the classic layout")
            subtext: Tr.tr("Weather, system, media | resources, notifications, with the cards from lock-ha.json")
            onClicked: LockLayout.reset()
        }

        SectionHeader {
            text: Tr.tr("Behaviour")
        }

        ToggleRow {
            first: true
            text: Tr.tr("Hide notification content")
            subtext: Tr.tr("Only how many there are, until you unlock")
            checked: GlobalConfig.lock.hideNotifs
            onToggled: GlobalConfig.lock.hideNotifs = checked
        }

        ToggleRow {
            text: Tr.tr("Session buttons")
            subtext: Tr.tr("Shut down, reboot and the rest, over the resources card")
            checked: GlobalConfig.lock.enableSessionControls
            onToggled: GlobalConfig.lock.enableSessionControls = checked
        }

        ToggleRow {
            text: Tr.tr("Wallpaper behind")
            subtext: Tr.tr("Instead of the blurred screen")
            checked: GlobalConfig.lock.useWallpaper
            onToggled: GlobalConfig.lock.useWallpaper = checked
        }

        ToggleRow {
            last: true
            text: Tr.tr("Recolour the logo")
            subtext: Tr.tr("In the system card, to the colour scheme")
            checked: GlobalConfig.lock.recolourLogo
            onToggled: GlobalConfig.lock.recolourLogo = checked
        }

        InfoRow {
            Layout.topMargin: Tokens.spacing.medium
            first: true
            last: true
            icon: "face"
            label: Tr.tr("Face and fingerprint unlock")
            subtext: Tr.tr("In Settings → Camera")
        }
    }
}
