import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.services

// Two columns of cards around the clock and password. What the columns hold is
// services/LockLayout (Settings → Lock screen); without a lock.json it's the
// layout the lock screen always had.
RowLayout {
    id: root

    required property var lock

    spacing: Tokens.spacing.largeIncreased * 2

    LockColumn {
        cards: LockLayout.left
        lock: root.lock
        rootHeight: root.height
    }

    Center {
        lock: root.lock
    }

    LockColumn {
        cards: LockLayout.right
        lock: root.lock
        rootHeight: root.height
    }
}
