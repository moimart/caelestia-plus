import QtQuick
import qs.utils

// Resolves an icon or image reference as apps send it (theme name, file path
// or URL, image://icon/ URL) to a drawable `source`, and loads it at 1x1 to
// learn whether it really exists. `ok` is false for names the icon theme lacks
// and for files that are gone (Chrome deletes its temporary notification
// icons), which would otherwise render Qt's "missing image" checkerboard.
Image {
    property string name

    readonly property string resolved: Icons.iconSource(name)
    readonly property bool ok: resolved !== "" && status === Image.Ready

    visible: false
    asynchronous: true
    sourceSize: Qt.size(1, 1)
    source: resolved
}
