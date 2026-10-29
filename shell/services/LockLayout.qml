pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.I18n
import qs.utils

// What the lock screen shows in its two side columns, top to bottom
// (the clock and password in the middle stay as they are).
//
// ~/.config/caelestia/lock.json: { "left": [card...], "right": [card...] }.
// A card is { "type", ... }:
//   built in: weather, fetch, media, resources, notifications
//   Home Assistant (with an optional "instance"): camera (entity, name,
//   aspect), energy (solar, home, grid, battery_soc, battery_power, autarky),
//   entities (title, entities), haEntity (entity, name), haCard (card: a
//   dashboard card's config). They only show; nothing can be pressed there.
//
// Without lock.json the layout is the one the lock screen always had, with
// the cards from lock-ha.json (its "left", "right" and "hide").
Singleton {
    id: root

    readonly property string path: `${Paths.config}/lock.json`

    property var left: []
    property var right: []
    // True while there's no lock.json: the classic layout
    property bool isDefault: true
    property var legacy: ({})

    readonly property var defaultLeft: [
        {
            type: "weather"
        },
        ...(legacy.left ?? []), ...((legacy.hide ?? []).includes("fetch") ? [] : [
                {
                    type: "fetch"
                }
            ]),
        {
            type: "media"
        }
    ]
    readonly property var defaultRight: [...((legacy.hide ?? []).includes("resources") ? [] : [
                {
                    type: "resources"
                }
            ]), ...(legacy.right ?? []),
        {
            type: "notifications"
        }
    ]

    // What each card type is, for Settings
    readonly property var types: [
        {
            type: "weather",
            name: Tr.tr("Weather"),
            icon: "partly_cloudy_day"
        },
        {
            type: "fetch",
            name: Tr.tr("System"),
            icon: "terminal"
        },
        {
            type: "media",
            name: Tr.tr("Media"),
            icon: "music_note"
        },
        {
            type: "resources",
            name: Tr.tr("Resources"),
            icon: "memory"
        },
        {
            type: "notifications",
            name: Tr.tr("Notifications"),
            icon: "notifications"
        },
        {
            type: "camera",
            name: Tr.tr("Camera"),
            icon: "videocam",
            ha: true
        },
        {
            type: "haEntity",
            name: Tr.tr("Entity"),
            icon: "sensors",
            ha: true
        },
        {
            type: "entities",
            name: Tr.tr("Entities"),
            icon: "list",
            ha: true
        },
        {
            type: "energy",
            name: Tr.tr("Energy"),
            icon: "bolt",
            ha: true
        },
        {
            type: "haCard",
            name: Tr.tr("Dashboard card"),
            icon: "dashboard",
            ha: true
        }
    ]

    function typeInfo(type: string): var {
        return types.find(t => t.type === type) ?? {
            type: type,
            name: type,
            icon: "help"
        };
    }

    function save(nextLeft: var, nextRight: var): void {
        left = nextLeft;
        right = nextRight;
        isDefault = false;
        file.setText(JSON.stringify({
            left: nextLeft,
            right: nextRight
        }, null, 4) + "\n");
    }

    // Back to the classic layout (lock.json goes)
    function reset(): void {
        Quickshell.execDetached(["rm", "-f", path]);
        isDefault = true;
        left = defaultLeft;
        right = defaultRight;
    }

    onDefaultLeftChanged: {
        if (isDefault)
            left = defaultLeft;
    }
    onDefaultRightChanged: {
        if (isDefault)
            right = defaultRight;
    }

    FileView {
        id: file

        path: root.path
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const data = JSON.parse(text());
                root.left = data.left ?? [];
                root.right = data.right ?? [];
                root.isDefault = false;
            } catch (e) {
                console.warn(`LockLayout: bad lock.json: ${e}`);
            }
        }
        onLoadFailed: {
            root.isDefault = true;
            root.left = root.defaultLeft;
            root.right = root.defaultRight;
        }
    }

    FileView {
        path: `${Paths.config}/lock-ha.json`
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root.legacy = JSON.parse(text());
            } catch (e) {}
        }
    }
}
