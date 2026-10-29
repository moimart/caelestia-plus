pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

// Picks a card from one of an instance's dashboards: the dashboard, then the
// card (searchable by title, type or entity). Picking hands back where it is
// and its config.
ColumnLayout {
    id: root

    property string instance
    property string dashboard
    property string cardPath
    property bool first: true
    property bool last: true

    property var dashboards: []
    property var cards: []
    property string query
    property bool loading
    readonly property var current: cards.find(c => c.path === cardPath) ?? null
    readonly property var matches: {
        const words = query.toLowerCase().split(/\s+/).filter(w => w);
        // Headings and stacks are rarely what you want on their own
        const pool = cards.filter(c => !["heading"].includes(c.type));
        const hay = c => `${c.title} ${c.type} ${c.view} ${c.card?.entity ?? ""}`.toLowerCase();
        return (words.length === 0 ? pool : pool.filter(c => words.every(w => hay(c).includes(w)))).slice(0, 10);
    }

    signal picked(dashboard: string, path: string, card: var)

    function describe(c: var): string {
        return c.title || c.card?.name || c.card?.entity || c.card?.camera_image || c.type;
    }

    function loadDashboards(): void {
        HomeAssistant.request(instance, "dashboards", {}, msg => root.dashboards = msg.ok ? msg.result : []);
    }

    function loadCards(): void {
        loading = true;
        HomeAssistant.request(instance, "cards", {
            dashboard: dashboard || null
        }, msg => {
            root.loading = false;
            root.cards = msg.ok ? msg.result : [];
        });
    }

    spacing: parent?.spacing ?? 0

    onInstanceChanged: {
        loadDashboards();
        loadCards();
    }
    onDashboardChanged: loadCards()
    Component.onCompleted: {
        loadDashboards();
        loadCards();
    }

    SelectRow {
        first: root.first
        label: Tr.tr("Dashboard")
        menuItems: dashboardItems.instances
        active: dashboardItems.instances.find(i => (i.value ?? "") === (root.dashboard ?? "")) ?? null
        fallbackText: root.dashboards.length === 0 ? Tr.tr("Loading…") : ""
        onSelected: item => root.dashboard = item.value ?? ""

        Variants {
            id: dashboardItems

            model: root.dashboards

            MenuItem {
                required property var modelData

                text: modelData.title ?? Tr.tr("Overview")
                value: modelData.url_path ?? ""
            }
        }
    }

    InfoRow {
        icon: "dashboard"
        label: root.current ? root.describe(root.current) : Tr.tr("No card yet: search below")
        subtext: root.current ? `${root.current.type} · ${root.current.view}` : ""
    }

    TextFieldRow {
        label: Tr.tr("Search")
        placeholderText: Tr.tr("Title, type or entity")
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
            icon: ({
                    tile: "crop_square",
                    entities: "list",
                    "picture-entity": "videocam",
                    "picture-glance": "videocam",
                    glance: "grid_view",
                    gauge: "speed",
                    grid: "grid_view",
                    "vertical-stack": "view_agenda",
                    "horizontal-stack": "view_column"
                })[modelData.type] ?? "dashboard"
            text: root.describe(modelData)
            subtext: `${modelData.type} · ${modelData.view}`
            trailingIcon: modelData.path === root.cardPath ? "check" : ""
            onClicked: root.picked(root.dashboard, modelData.path, modelData.card)
        }
    }

    InfoRow {
        visible: root.matches.length === 0
        last: root.last
        icon: root.loading ? "hourglass" : "search_off"
        label: root.loading ? Tr.tr("Loading the cards…") : Tr.tr("No cards match")
    }
}
