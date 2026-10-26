pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

// The favicon of the page the focused browser window shows (or a web app
// window's site), for the bar.
// assets/favicon.py finds it in the browser's own history and favicon
// databases (read-only, nothing over the network), from the window title.
Singleton {
    id: root

    // Browsers it knows; other windows have no favicon
    readonly property list<string> browsers: ["google-chrome", "google-chrome-beta", "chromium", "brave-browser", "microsoft-edge", "vivaldi-stable", "firefox"]

    readonly property string windowClass: Hypr.activeToplevel?.lastIpcObject.class ?? ""
    readonly property string windowTitle: Hypr.activeToplevel?.title ?? ""
    // Web app windows: "<browser>-<host>__...", the site's icon whatever the title
    readonly property bool isWebApp: /^(chrome|chromium|brave|msedge|vivaldi)-[^_]+__/.test(windowClass)
    readonly property bool isBrowser: isWebApp || browsers.includes(windowClass)
    readonly property string key: isWebApp ? windowClass : `${windowClass}\n${windowTitle}`

    // "class\ntitle" -> file path ("" when there's none)
    property var cache: ({})
    // The focused window's favicon, if it's a browser and has one
    readonly property string current: isBrowser ? (cache[key] ?? "") : ""

    property string running
    property bool retried

    function lookup(): void {
        if (!isBrowser || proc.running)
            return;
        running = key;
        proc.command = ["python3", "-I", `${Quickshell.shellDir}/assets/favicon.py`, windowClass, windowTitle];
        proc.running = true;
    }

    Component.onCompleted: {
        if (isBrowser)
            settle.restart();
    }
    onKeyChanged: {
        retried = false;
        if (isBrowser && !(key in cache))
            settle.restart();
    }

    // Titles change a lot while a page loads: wait until it settles
    Timer {
        id: settle

        interval: 400
        onTriggered: root.lookup()
    }

    // A page's history entry can be written a moment after its title shows
    Timer {
        id: retry

        interval: 3000
        onTriggered: {
            if (root.isBrowser && !root.cache[root.key]) {
                const next = Object.assign({}, root.cache);
                delete next[root.key];
                root.cache = next;
                root.lookup();
            }
        }
    }

    Process {
        id: proc

        stdout: StdioCollector {
            onStreamFinished: {
                const next = Object.assign({}, root.cache);
                next[root.running] = text.trim();
                root.cache = next;
                if (!text.trim() && !root.retried && root.running === root.key) {
                    root.retried = true;
                    retry.restart();
                }
                // The window changed while it ran
                if (root.isBrowser && !(root.key in root.cache))
                    settle.restart();
            }
        }
    }
}
