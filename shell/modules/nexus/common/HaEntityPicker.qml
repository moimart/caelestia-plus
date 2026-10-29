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

    signal picked(id: string)

    function load(): void {
        HomeAssistant.entityList(instance, list => root.all = list);
    }

    spacing: parent?.spacing ?? 0

    onInstanceChanged: load()
    Component.onCompleted: load()

    InfoRow {
        first: root.first
        icon: root.value ? HaIcons.iconFor(root.value, HomeAssistant.entity(root.instance, root.value)) : "help"
        label: root.label
        subtext: root.value ? root.value : Tr.tr("None yet: search below")
        value: root.current?.name ?? ""
    }

    TextFieldRow {
        label: Tr.tr("Search")
        placeholderText: root.domains.length > 0 ? root.domains.join(", ") : Tr.tr("Name or id")
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
            subtext: `${modelData.id} · ${modelData.state}`
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
