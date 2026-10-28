pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components.containers
import qs.modules.bar as Bar

Scope {
    id: root

    required property ShellScreen screen
    required property Bar.BarWrapper bar
    // The right bar's space (its width when on, else the border's)
    property int rightExclusiveZone: -1
    // Right to left: the bar's space on the right, the right bar's on the left
    property bool rtl
    readonly property int otherZone: rightExclusiveZone >= 0 ? rightExclusiveZone : -1

    ExclusionZone {
        anchors.left: true
        exclusiveZone: root.rtl ? (root.otherZone >= 0 ? root.otherZone : contentItem.Config.border.thickness) : root.bar.exclusiveZone
    }

    ExclusionZone {
        anchors.top: true
    }

    ExclusionZone {
        anchors.right: true
        exclusiveZone: root.rtl ? root.bar.exclusiveZone : (root.otherZone >= 0 ? root.otherZone : contentItem.Config.border.thickness)
    }

    ExclusionZone {
        anchors.bottom: true
    }

    component ExclusionZone: StyledWindow {
        screen: root.screen
        name: "border-exclusion"
        exclusiveZone: contentItem.Config.border.thickness
        mask: Region {}
        implicitWidth: 1
        implicitHeight: 1
    }
}
