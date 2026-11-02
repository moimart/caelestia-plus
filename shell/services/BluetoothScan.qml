pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Bluetooth

// Bluetooth scans, which stop by themselves. A scan nobody is looking at
// (the pairing page closed, the bar's toggle forgotten) floods the shell with
// every nearby device's signal strength, dozens of updates a second, for as
// long as it runs: so it's stopped two minutes in, unless a pairing page is
// still showing (it holds the scan while it does).
Singleton {
    id: root

    readonly property BluetoothAdapter adapter: Bluetooth.defaultAdapter
    readonly property bool scanning: adapter?.discovering ?? false
    // Pairing pages showing now
    property int holders: 0

    function hold(): void {
        holders++;
        if (adapter?.enabled)
            adapter.discovering = true;
    }

    function release(): void {
        holders = Math.max(0, holders - 1);
        if (holders === 0 && adapter?.enabled)
            adapter.discovering = false;
    }

    onScanningChanged: if (scanning)
        timeout.restart()
    // One already running when the shell starts counts too
    Component.onCompleted: if (scanning)
        timeout.start()

    Timer {
        id: timeout

        interval: 120000
        onTriggered: {
            if (!root.scanning)
                return;
            if (root.holders > 0)
                restart();
            else if (root.adapter?.enabled)
                root.adapter.discovering = false;
        }
    }
}
