pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.modules.bar as Bar

Region {
    id: root

    required property Bar.BarWrapper bar
    required property Panels panels
    required property var win

    readonly property real borderThickness: win.contentItem.Config.border.thickness
    readonly property real clampedThickness: win.contentItem.Config.border.clampedThickness
    // The right side: the border, or the right bar when it's on
    readonly property real rightThickness: Math.max(clampedThickness, win.rightBarWidth)

    // The bar's side is the right one when right to left
    x: (win.rtl ? rightThickness : bar.clampedWidth) + win.dragMaskPadding
    y: clampedThickness + win.dragMaskPadding
    width: win.width - bar.clampedWidth - rightThickness - win.dragMaskPadding * 2
    height: win.height - clampedThickness * 2 - win.dragMaskPadding * 2
    intersection: Intersection.Xor

    R {
        panel: root.panels.dashboard
        y: 0
        height: panel.height * (1 - root.panels.dashboard.offsetScale) + root.borderThickness
    }

    R {
        panel: root.panels.launcher
        y: root.win.height - height
        height: panel.height * (1 - root.panels.launcher.offsetScale) + root.borderThickness
    }

    R {
        id: sessionRegion

        panel: root.panels.sessionWrapper
        x: root.win.rtl ? 0 : root.win.width - width
        width: panel.width * (1 - root.panels.session.offsetScale) + sidebarRegion.width
    }

    R {
        id: sidebarRegion

        panel: root.panels.sidebar
        x: root.win.rtl ? 0 : root.win.width - width
        width: panel.width * (1 - root.panels.sidebar.offsetScale) + Math.max(root.borderThickness, root.win.rightBarWidth)
    }

    R {
        panel: root.panels.osdWrapper
        x: root.win.rtl ? 0 : root.win.width - width
        width: panel.width * (1 - root.panels.osd.offsetScale) + sessionRegion.width
    }

    R {
        panel: root.panels.notifications
        y: 0
        height: panel.height + root.borderThickness
    }

    R {
        panel: root.panels.utilities
        y: root.win.height - height
        height: panel.height * (1 - root.panels.utilities.offsetScale) + root.borderThickness
    }

    R {
        panel: root.panels.popoutsWrapper
        width: panel.width * (1 - root.panels.popoutsWrapper.offsetScale)
    }

    component R: Region {
        required property Item panel

        x: panel.x + root.win.panelsLeft
        y: panel.y + root.borderThickness
        width: panel.width
        height: panel.height
        intersection: Intersection.Subtract
    }
}
