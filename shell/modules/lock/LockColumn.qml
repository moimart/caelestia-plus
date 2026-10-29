pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config

// One side of the lock screen: its cards, top to bottom
ColumnLayout {
    id: root

    required property var cards
    required property var lock
    required property real rootHeight

    Layout.fillWidth: true
    Layout.fillHeight: true
    spacing: Tokens.spacing.medium

    Repeater {
        model: root.cards

        LockCard {
            required property var modelData

            card: modelData
            lock: root.lock
            rootHeight: root.rootHeight
        }
    }

    // When nothing in the column takes the space left, its cards stay at the top
    Item {
        Layout.fillHeight: true
        visible: !root.cards.some(c => c.type === "media" || c.type === "notifications")
    }
}
