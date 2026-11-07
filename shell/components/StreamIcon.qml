pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import qs.services

// An app's audio stream's icon: for a browser, the favicon of the page that's
// playing, else the app's own icon (AppIcon).
//
// A browser's stream doesn't say which tab it's from, but its media player
// (MPRIS) says what's playing, and the browser's history knows which page had
// that title: assets/favicon.py --media, as the bar does for window titles.
Item {
    id: root

    property PwNode stream
    property real implicitSize

    readonly property string binary: stream?.properties["application.process.binary"] ?? ""
    readonly property string appName: stream?.properties["application.name"] ?? ""
    // The browser, as favicon.py knows it (by its window class)
    readonly property string browser: ({
            chrome: "google-chrome",
            chromium: "chromium",
            brave: "brave-browser",
            msedge: "microsoft-edge",
            "vivaldi-bin": "vivaldi-stable",
            firefox: "firefox",
            "firefox-bin": "firefox"
        })[binary] ?? ""
    // The browser's media player: by its name, else by its kind; one that's
    // playing first
    readonly property MprisPlayer player: {
        if (!browser)
            return null;
        const family = browser === "firefox" ? "firefox" : "chromium";
        const players = Mpris.players.values;
        const mine = players.filter(p => p.identity === appName);
        const candidates = mine.length > 0 ? mine : players.filter(p => p.dbusName.includes(family));
        return candidates.find(p => p.isPlaying) ?? candidates[0] ?? null;
    }
    readonly property string mediaTitle: player?.trackTitle ?? ""
    property string favicon

    implicitWidth: implicitSize
    implicitHeight: implicitSize

    Component.onCompleted: lookup.restart()
    onMediaTitleChanged: lookup.restart()
    onBrowserChanged: lookup.restart()

    // Titles change in bursts as a track starts
    Timer {
        id: lookup

        interval: 300
        onTriggered: {
            if (!root.browser || !root.mediaTitle) {
                root.favicon = "";
                return;
            }
            proc.running = false;
            proc.command = ["python3", "-I", `${Quickshell.shellDir}/assets/favicon.py`, "--media", root.browser, root.mediaTitle];
            proc.running = true;
        }
    }

    Process {
        id: proc

        stdout: StdioCollector {
            onStreamFinished: root.favicon = text.trim()
        }
    }

    Image {
        id: image

        anchors.centerIn: parent
        width: Math.round(root.implicitSize * 0.8)
        height: width
        source: root.favicon ? `file://${root.favicon}` : ""
        sourceSize: Qt.size(width * 2, height * 2)
        fillMode: Image.PreserveAspectFit
        smooth: true
        asynchronous: true
        visible: status === Image.Ready
    }

    AppIcon {
        anchors.fill: parent
        visible: !image.visible
        implicitSize: root.implicitSize
        entry: DesktopEntries.heuristicLookup(root.binary || Audio.getStreamName(root.stream))
    }
}
