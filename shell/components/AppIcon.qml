pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Widgets
import Caelestia.Config
import qs.services
import qs.utils

// An app's icon from its desktop entry. When the icon theme has no such icon
// (or it fails to load), shows a tile in the scheme's colours with a symbol
// for the app's category, instead of the "missing image" checkerboard.
Item {
    id: root

    property DesktopEntry entry
    property real implicitSize

    readonly property string iconName: entry?.icon ?? ""
    readonly property string source: {
        if (!iconName)
            return "";
        if (iconName.startsWith("/"))
            return `file://${iconName}`;
        return Quickshell.iconPath(iconName, true);
    }
    readonly property bool missing: !source || image.status === Image.Error
    readonly property string symbol: {
        const categories = entry?.categories ?? [];
        for (const [key, value] of Object.entries(Icons.categoryIcons))
            if (categories.includes(key))
                return value;
        return "apps";
    }

    implicitWidth: implicitSize
    implicitHeight: implicitSize

    IconImage {
        id: image

        anchors.fill: parent
        visible: !root.missing
        asynchronous: true
        source: root.source
        implicitSize: root.implicitSize
    }

    Loader {
        anchors.centerIn: parent
        active: root.missing

        sourceComponent: StyledRect {
            implicitWidth: root.width * 0.86
            implicitHeight: implicitWidth
            radius: implicitWidth * 0.3
            color: Colours.palette.m3secondaryContainer

            MaterialIcon {
                anchors.centerIn: parent
                text: root.symbol
                color: Colours.palette.m3onSecondaryContainer
                fill: 1
                fontStyle: Tokens.font.icon.size(Math.max(1, root.width * 0.34)).build()
            }
        }
    }
}
