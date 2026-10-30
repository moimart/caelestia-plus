pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services
import qs.utils

// One card of a Home Assistant dashboard, drawn here from its config (as
// Home Assistant's own frontend would, in the shell's style): tile, entity,
// button and button-card as a tile; entities as rows; glance as a row of icons;
// picture-entity, picture-glance and camera pictures; heading; gauge; stacks
// and grids of cards. Custom cards (custom:..., from HACS) are drawn by a
// headless browser (HaWebCard). Other types show what they are.
Item {
    id: root

    property string instance
    property var card: ({})
    property bool readOnly
    // On the desktop, where windows can cover it (custom cards freeze then)
    property bool onDesktop
    // Custom cards: their own animations, which cost
    property bool animate

    readonly property string type: (card?.type ?? "").replace(/^custom:/, "")
    // Every entity this card (and its children) shows, kept live
    readonly property var entityIds: {
        const ids = new Set();
        const walk = c => {
            if (!c)
                return;
            for (const k of ["entity", "camera_image"])
                if (typeof c[k] === "string")
                    ids.add(c[k]);
            for (const e of c.entities ?? [])
                ids.add(typeof e === "string" ? e : e?.entity);
            for (const child of c.cards ?? [])
                walk(child);
        };
        walk(card);
        ids.delete(undefined);
        return [...ids];
    }
    readonly property string consumer: `card-${Math.random().toString(36).slice(2)}`

    function name(e: var): string {
        if (typeof e === "object" && e?.name)
            return e.name;
        const id = typeof e === "string" ? e : e?.entity;
        return HomeAssistant.entity(instance, id)?.attributes?.friendly_name ?? id ?? "";
    }

    implicitWidth: body.item?.implicitWidth ?? 220
    implicitHeight: body.item?.implicitHeight ?? 72

    onEntityIdsChanged: HomeAssistant.watch(consumer, instance, entityIds)
    Component.onCompleted: HomeAssistant.watch(consumer, instance, entityIds)
    Component.onDestruction: HomeAssistant.unwatch(consumer, instance)

    Loader {
        id: body

        anchors.fill: parent
        sourceComponent: {
            switch (root.type) {
            case "tile":
            case "entity":
            case "button":
            case "button-card":
            case "light":
            case "sensor":
            case "thermostat":
            case "media-control":
                return tileCard;
            case "entities":
                return entitiesCard;
            case "glance":
                return glanceCard;
            case "picture-entity":
            case "picture-glance":
                return pictureCard;
            case "heading":
                return headingCard;
            case "gauge":
                return gaugeCard;
            case "vertical-stack":
            case "horizontal-stack":
            case "grid":
                return stackCard;
            default:
                return (root.card?.type ?? "").startsWith("custom:") ? webCard : unsupportedCard;
            }
        }
    }

    Component {
        id: webCard

        HaWebCard {
            instance: root.instance
            card: root.card
            pauseWhenCovered: root.onDesktop
            animate: root.animate
        }
    }

    Component {
        id: tileCard

        HaTile {
            instance: root.instance
            entityId: root.card.entity ?? ""
            name: root.card.name ?? ""
            readOnly: root.readOnly
        }
    }

    Component {
        id: entitiesCard

        StyledRect {
            implicitWidth: 280
            implicitHeight: rows.implicitHeight + Tokens.padding.medium * 2
            radius: Tokens.rounding.large
            color: Colours.tPalette.m3surfaceContainer

            ColumnLayout {
                id: rows

                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                spacing: Tokens.spacing.small

                StyledText {
                    visible: !!root.card.title
                    text: root.card.title ?? ""
                    font: Tokens.font.title.small
                }

                Repeater {
                    model: (root.card.entities ?? []).filter(e => typeof e === "string" || e?.entity)

                    RowLayout {
                        id: row

                        required property var modelData
                        readonly property string entityId: typeof modelData === "string" ? modelData : modelData.entity
                        readonly property var entity: HomeAssistant.entity(root.instance, entityId)

                        Layout.fillWidth: true
                        spacing: Tokens.spacing.medium

                        MaterialIcon {
                            text: HaIcons.iconFor(row.entityId, row.entity)
                            color: HaIcons.isOn(row.entity?.state ?? "") ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                        }

                        StyledText {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 60
                            text: root.name(row.modelData)
                            elide: Text.ElideRight
                        }

                        // At most half the row, so the name always shows
                        StyledText {
                            Layout.maximumWidth: row.width / 2
                            text: HaIcons.stateText(row.entity)
                            color: Colours.palette.m3onSurfaceVariant
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            // Rows toggle what can be toggled
            MouseArea {
                anchors.fill: rows
                enabled: !root.readOnly
                onClicked: mouse => {
                    const item = rows.childAt(mouse.x, mouse.y);
                    const id = item?.entityId;
                    if (id && HaIcons.isActionable(id))
                        HomeAssistant.activate(root.instance, id);
                }
            }
        }
    }

    Component {
        id: glanceCard

        StyledRect {
            implicitWidth: Math.max(160, cells.implicitWidth + Tokens.padding.medium * 2)
            implicitHeight: col.implicitHeight + Tokens.padding.medium * 2
            radius: Tokens.rounding.large
            color: Colours.tPalette.m3surfaceContainer

            ColumnLayout {
                id: col

                anchors.fill: parent
                anchors.margins: Tokens.padding.medium

                StyledText {
                    visible: !!root.card.title
                    text: root.card.title ?? ""
                    font: Tokens.font.title.small
                }

                RowLayout {
                    id: cells

                    Layout.fillWidth: true
                    spacing: Tokens.spacing.large

                    Repeater {
                        model: (root.card.entities ?? []).filter(e => typeof e === "string" || e?.entity)

                        ColumnLayout {
                            id: cell

                            required property var modelData
                            readonly property string entityId: typeof modelData === "string" ? modelData : modelData.entity
                            readonly property var entity: HomeAssistant.entity(root.instance, entityId)

                            Layout.fillWidth: true
                            spacing: 0

                            MaterialIcon {
                                Layout.alignment: Qt.AlignHCenter
                                text: HaIcons.iconFor(cell.entityId, cell.entity)
                                color: HaIcons.isOn(cell.entity?.state ?? "") ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: root.name(cell.modelData)
                                font: Tokens.font.label.small
                                elide: Text.ElideRight
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: HaIcons.stateText(cell.entity)
                                color: Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.label.small
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: pictureCard

        HaCameraView {
            implicitWidth: 360
            implicitHeight: 210
            instance: root.instance
            entityId: root.card.camera_image ?? root.card.entity ?? ""
            name: root.card.name ?? root.card.title ?? ""
        }
    }

    Component {
        id: headingCard

        Item {
            implicitWidth: 220
            implicitHeight: heading.implicitHeight + Tokens.padding.small * 2

            StyledText {
                id: heading

                anchors.fill: parent
                text: root.card.heading ?? root.card.title ?? ""
                font: Tokens.font.title.medium
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }
        }
    }

    Component {
        id: gaugeCard

        StyledRect {
            id: gauge

            readonly property var entity: HomeAssistant.entity(root.instance, root.card.entity ?? "")
            readonly property real min: root.card.min ?? 0
            readonly property real max: root.card.max ?? 100
            readonly property real value: parseFloat(entity?.state ?? "")
            readonly property real fraction: isNaN(value) ? 0 : Math.max(0, Math.min(1, (value - min) / (max - min)))

            implicitWidth: 220
            implicitHeight: 96
            radius: Tokens.rounding.large
            color: Colours.tPalette.m3surfaceContainer

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                spacing: Tokens.spacing.small

                StyledText {
                    Layout.fillWidth: true
                    text: root.card.name ?? root.name(root.card.entity)
                    elide: Text.ElideRight
                }

                StyledText {
                    text: HaIcons.stateText(gauge.entity)
                    font: Tokens.font.title.medium
                }

                StyledRect {
                    Layout.fillWidth: true
                    implicitHeight: 8
                    radius: Tokens.rounding.full
                    color: Colours.tPalette.m3surfaceContainerHighest

                    StyledRect {
                        width: parent.width * gauge.fraction
                        height: parent.height
                        radius: parent.radius
                        color: Colours.palette.m3primary
                    }
                }
            }
        }
    }

    Component {
        id: stackCard

        GridLayout {
            readonly property bool horizontal: root.type === "horizontal-stack"

            columns: root.type === "grid" ? (root.card.columns ?? 2) : (horizontal ? (root.card.cards ?? []).length : 1)
            columnSpacing: Tokens.spacing.small
            rowSpacing: Tokens.spacing.small

            Repeater {
                model: root.card.cards ?? []

                // By URL: a type can't contain itself directly
                Loader {
                    required property var modelData

                    Layout.fillWidth: true
                    Component.onCompleted: setSource(Qt.resolvedUrl("HaCard.qml"), {
                        instance: root.instance,
                        card: modelData,
                        readOnly: root.readOnly
                    })
                }
            }
        }
    }

    Component {
        id: unsupportedCard

        StyledRect {
            implicitWidth: 220
            implicitHeight: 72
            radius: Tokens.rounding.large
            color: Colours.tPalette.m3surfaceContainer

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 0

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.card.title ?? root.card.name ?? root.card.type ?? ""
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: `${root.card.type ?? "?"}: not drawn here yet`
                    color: Colours.palette.m3outline
                    font: Tokens.font.label.small
                }
            }
        }
    }
}
