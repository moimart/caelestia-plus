pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.I18n
import qs.components
import qs.services
import qs.utils
import qs.modules.nexus.common

// Picks a Home Assistant entity: the current one, a search box, and the best
// matches (by name or id, every word), only from `domains` if given.
ColumnLayout {
    id: root

    property string instance
    property string value
    property list<string> domains
    property string label: Tr.tr("Entity")
    property bool first: true
    property bool last: true

    property var all: []
    property string query
    readonly property var current: all.find(e => e.id === value) ?? null
    readonly property var matches: {
        const words = query.toLowerCase().split(/\s+/).filter(w => w);
        // Ones that work first: unavailable entities go last
        const dead = e => ["unavailable", "unknown"].includes(e.state) ? 1 : 0;
        const pool = (domains.length > 0 ? all.filter(e => domains.includes(e.domain)) : all).slice().sort((a, b) => dead(a) - dead(b));
        if (words.length === 0)
            return pool.slice(0, 6);
        return pool.filter(e => {
            const hay = `${e.name} ${e.id}`.toLowerCase();
            return words.every(w => hay.includes(w));
        }).slice(0, 8);
    }

    // What it offers, as people say it ("Lights, switches, fans")
    readonly property string kinds: {
        const names = {
            light: Tr.tr("lights"),
            switch: Tr.tr("switches"),
            input_boolean: Tr.tr("toggles"),
            fan: Tr.tr("fans"),
            lock: Tr.tr("locks"),
            cover: Tr.tr("blinds and doors"),
            button: Tr.tr("buttons"),
            input_button: Tr.tr("buttons"),
            scene: Tr.tr("scenes"),
            script: Tr.tr("scripts"),
            automation: Tr.tr("automations"),
            media_player: Tr.tr("media players"),
            camera: Tr.tr("cameras"),
            sensor: Tr.tr("sensors"),
            binary_sensor: Tr.tr("sensors")
        };
        const list = [...new Set(domains.map(d => names[d] ?? d.replace(/_/g, " ")))].join(", ");
        return list ? list[0].toUpperCase() + list.slice(1) : "";
    }

    signal picked(id: string)

    function load(): void {
        HomeAssistant.entityList(instance, list => root.all = list);
    }

    spacing: parent?.spacing ?? 0

    onInstanceChanged: load()
    Component.onCompleted: load()

    InfoRow {
        first: root.first
        icon: root.value ? HaIcons.iconFor(root.value, HomeAssistant.entity(root.instance, root.value)) : "search"
        label: root.label
        subtext: root.value ? root.value : Tr.tr("Search below")
        value: root.current?.name ?? ""
    }

    TextFieldRow {
        label: Tr.tr("Search")
        subtext: root.kinds
        placeholderText: Tr.tr("Name or id")
        value: root.query
        onValueEdited: value => root.query = value
    }

    Repeater {
        model: root.matches

        RowButton {
            required property var modelData
            required property int index

            Layout.fillWidth: true
            last: root.last && index === root.matches.length - 1
            icon: HaIcons.iconFor(modelData.id, {
                state: modelData.state,
                attributes: {}
            })
            text: modelData.name
            // Buttons and the like have the time they were last pressed as their state
            subtext: `${modelData.id} · ${HaIcons.stateText({
                state: modelData.state,
                attributes: /^\d{4}-\d\d-\d\dT/.test(modelData.state) ? {
                    device_class: "timestamp"
                } : {}
            })}`
            trailingIcon: modelData.id === root.value ? "check" : ""
            onClicked: root.picked(modelData.id)
        }
    }

    InfoRow {
        visible: root.matches.length === 0
        last: root.last
        icon: "search_off"
        label: root.all.length === 0 ? Tr.tr("Loading the entities…") : Tr.tr("Nothing matches")
    }
}
