pragma ComponentBehavior: Bound

import "ha"
import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.ha
import qs.services

// One card of a lock screen column (see services/LockLayout): a built-in one,
// or a Home Assistant one, read-only. Media and notifications take the space
// left in their column, as they always have.
Loader {
    id: root

    required property var card
    required property var lock
    required property real rootHeight

    readonly property string type: card?.type ?? ""
    readonly property bool fills: type === "media" || type === "notifications"

    Layout.fillWidth: true
    Layout.fillHeight: fills
    asynchronous: !fills

    sourceComponent: ({
            weather: weather,
            fetch: fetch,
            media: media,
            resources: resources,
            notifications: notifications,
            camera: haLegacy,
            energy: haLegacy,
            entities: haLegacy,
            haEntity: haEntity,
            haCard: haCard
        })[type] ?? null

    Component {
        id: weather

        WeatherInfo {
            rootHeight: root.rootHeight
        }
    }

    Component {
        id: fetch

        Fetch {
            rootHeight: root.rootHeight
        }
    }

    Component {
        id: media

        Media {
            lock: root.lock
        }
    }

    Component {
        id: resources

        Resources {}
    }

    Component {
        id: notifications

        StyledRect {
            bottomRightRadius: Tokens.rounding.extraLarge
            radius: Tokens.rounding.medium
            color: Colours.tPalette.m3surfaceContainer

            NotifDock {
                lock: root.lock
            }
        }
    }

    // The lock screen's own camera, energy and entities cards, on the live
    // connection: `ha` is what they've always asked for (entity, url, tick)
    Component {
        id: haLegacy

        Loader {
            id: legacy

            readonly property QtObject ha: QtObject {
                readonly property string instance: root.card.instance ?? ""
                readonly property string url: (HomeAssistant.instances.find(i => i.id === (instance || HomeAssistant.defaultId))?.url ?? "").replace(/\/+$/, "")
                property int tick

                function entity(id: string): var {
                    return HomeAssistant.entity(instance, id);
                }
            }
            readonly property var entityIds: {
                const ids = new Set();
                for (const key of ["entity", "solar", "home", "grid", "battery_soc", "battery_power", "autarky"])
                    if (root.card[key])
                        ids.add(root.card[key]);
                for (const e of root.card.entities ?? [])
                    ids.add(typeof e === "string" ? e : e.entity);
                return [...ids];
            }
            readonly property string consumer: `lock-${Math.random().toString(36).slice(2)}`

            Component.onCompleted: {
                HomeAssistant.watch(consumer, ha.instance, entityIds);
                const files = {
                    camera: "ha/HaCamera.qml",
                    energy: "ha/HaEnergy.qml",
                    entities: "ha/HaEntities.qml"
                };
                setSource(files[root.type], {
                    card: root.card,
                    ha: ha
                });
            }
            Component.onDestruction: HomeAssistant.unwatch(consumer, ha.instance)

            // The camera picture's refresh
            Timer {
                running: root.type === "camera"
                repeat: true
                interval: Math.max(2, root.card.interval ?? 5) * 1000
                onTriggered: legacy.ha.tick++
            }
        }
    }

    Component {
        id: haEntity

        HaTile {
            instance: root.card.instance ?? ""
            entityId: root.card.entity ?? ""
            name: root.card.name ?? ""
            readOnly: true
        }
    }

    Component {
        id: haCard

        HaCard {
            instance: root.card.instance ?? ""
            card: root.card.card ?? ({})
            readOnly: true
        }
    }
}
