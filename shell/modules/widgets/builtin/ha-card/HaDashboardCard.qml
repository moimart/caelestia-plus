import QtQuick
import qs.components.ha

// A card from a Home Assistant dashboard on the desktop. settings.card is the
// card's config as it was when you picked it (settings.dashboard, cardPath say
// where it came from)
HaCard {
    property var settings: ({})
    property bool editing

    instance: settings.instance ?? ""
    card: settings.card ?? ({
            type: "heading",
            heading: "Pick a card in Settings → Plugins"
        })
    readOnly: editing
}
