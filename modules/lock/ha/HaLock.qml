pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Caelestia.Config
import qs.utils

// Read-only Home Assistant cards for one column of the lock screen.
// Cards come from ~/.config/caelestia/lock-ha.json (see README.md here);
// states are polled over HA's REST API only while the lock surface exists.
ColumnLayout {
    id: root

    required property string column // "left" or "right"

    property var config: ({})
    property string token: ""
    property var states: ({})
    property int tick: 0

    readonly property string url: (config.url ?? "").replace(/\/+$/, "")
    readonly property var cards: config[column] ?? []
    readonly property bool ready: url !== "" && token !== ""
    readonly property var entityIds: {
        const ids = new Set();
        for (const card of cards) {
            for (const key of ["entity", "solar", "home", "grid", "battery_soc", "battery_power", "autarky"])
                if (card[key])
                    ids.add(card[key]);
            for (const e of card.entities ?? [])
                ids.add(typeof e === "string" ? e : e.entity);
        }
        return [...ids];
    }

    function hides(name: string): bool {
        return (config.hide ?? []).includes(name);
    }

    function state(id: string): var {
        return states[id] ?? null;
    }

    function refresh(): void {
        for (const id of entityIds) {
            const xhr = new XMLHttpRequest();
            xhr.onreadystatechange = () => {
                if (xhr.readyState !== XMLHttpRequest.DONE)
                    return;
                if (xhr.status !== 200) {
                    console.warn(`lock-ha: ${id}: HTTP ${xhr.status}`);
                    return;
                }
                const next = Object.assign({}, root.states);
                next[id] = JSON.parse(xhr.responseText);
                root.states = next;
            };
            xhr.open("GET", `${root.url}/api/states/${id}`);
            xhr.setRequestHeader("Authorization", `Bearer ${root.token}`);
            xhr.send();
        }
        tick++;
    }

    visible: ready && cards.length > 0
    spacing: Tokens.spacing.medium

    FileView {
        printErrors: false
        path: `${Paths.config}/lock-ha.json`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root.config = JSON.parse(text());
            } catch (e) {
                console.warn(`lock-ha: bad lock-ha.json: ${e}`);
            }
        }
    }

    FileView {
        printErrors: false
        path: Paths.absolutePath(root.config.tokenFile ?? `${Paths.config}/ha-token`)
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.token = text().trim()
    }

    Timer {
        running: root.ready && root.entityIds.length > 0
        repeat: true
        triggeredOnStart: true
        interval: Math.max(2, root.config.interval ?? 10) * 1000
        onTriggered: root.refresh()
    }

    Repeater {
        model: root.cards

        Loader {
            id: card

            required property var modelData

            Layout.fillWidth: true
            asynchronous: true

            Component.onCompleted: {
                const files = {
                    camera: "HaCamera.qml",
                    energy: "HaEnergy.qml",
                    entities: "HaEntities.qml"
                };
                if (files[modelData.type])
                    setSource(files[modelData.type], {
                        card: modelData,
                        ha: root
                    });
                else
                    console.warn(`lock-ha: unknown card type "${modelData.type}"`);
            }
        }
    }
}
