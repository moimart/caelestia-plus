pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.services
import qs.modules.widgets

Variants {
    id: root

    property var lock

    model: Screens.screens.filter(s => GlobalConfig.forScreen(s.name).background.enabled)

    StyledWindow {
        id: win

        required property ShellScreen modelData

        screen: modelData
        name: "background"
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        // Bottom rather than Background so video wallpapers (mpvpaper, on the
        // background layer) can play underneath; transparent while one shows.
        WlrLayershell.layer: WlrLayer.Bottom
        color: contentItem.Config.background.wallpaperEnabled && !((wallpaper.item as Wallpaper)?.hasVideo ?? false) ? "black" : "transparent"
        surfaceFormat.opaque: false

        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true

        ShellState.ComponentRef {
            screen: win.screen
            slot: "background"
            component: win
        }

        Item {
            anchors.fill: parent

            Loader {
                id: wallpaper

                asynchronous: true

                anchors.fill: parent
                active: Config.background.wallpaperEnabled

                sourceComponent: Wallpaper {
                    screen: win.modelData
                    locked: root.lock?.lock.locked ?? false
                }
            }

            Visualiser {
                anchors.fill: parent
                screen: win.modelData
                wallpaper: wallpaper
            }
        }

        // Desktop widgets (the clock is one), above the wallpaper
        DesktopWidgets {
            anchors.fill: parent
            screen: win.modelData
        }
    }
}
