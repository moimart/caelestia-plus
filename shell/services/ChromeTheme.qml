pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Google Chrome's and Chromium's colour, from the colour scheme: their
// BrowserThemeColor policy, rewritten on every scheme change and picked up by
// a running browser. The policy files live in root's folders; the one-time
// setup (assets/chrome-theme-setup.sh, with sudo) makes them and hands them to
// you. Until then this does nothing.
Singleton {
    id: root

    readonly property list<string> paths: ["/etc/opt/chrome/policies/managed/caelestia-theme.json", "/etc/chromium/policies/managed/caelestia-theme.json"]
    // The scheme's seed: the browser builds its palette from it, as the scheme
    // was built
    readonly property string colour: `${Colours.palette.m3primary_paletteKeyColor}`
    readonly property string text: JSON.stringify({
        BrowserThemeColor: colour
    }, null, 4) + "\n"
    // Whether the setup has been done (for Settings)
    readonly property bool enabled: {
        for (let i = 0; i < files.count; i++)
            if (files.objectAt(i)?.present)
                return true;
        return false;
    }

    Instantiator {
        id: files

        model: root.paths

        FileView {
            required property string modelData
            property bool present
            readonly property string wanted: root.text

            function sync(): void {
                if (present && /^#[0-9a-f]{6}$/i.test(root.colour) && text() !== root.text)
                    setText(root.text);
            }

            path: modelData
            printErrors: false
            watchChanges: true
            onFileChanged: reload()
            onLoaded: {
                present = true;
                sync();
            }
            onLoadFailed: present = false
            onWantedChanged: sync()
        }
    }
}
