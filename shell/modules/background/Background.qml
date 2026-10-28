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
            id: behindClock

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

        // Desktop widgets, above the wallpaper and below the clock
        DesktopWidgets {
            anchors.fill: parent
            screen: win.modelData
        }

        Loader {
            id: clockLoader

            // The bar's and the right bar's room
            readonly property real barSpace: Tokens.sizes.bar.innerWidth + Math.max(Tokens.padding.small, Config.border.thickness)
            readonly property real otherSpace: Config.rightBar.enabled ? barSpace : 0

            asynchronous: true
            active: Config.background.desktopClock.enabled

            anchors.margins: Tokens.padding.extraLargeIncreased
            // Clear of the bar, and of the right bar when it's on (sides swapped
            // when right to left)
            anchors.leftMargin: Tokens.padding.extraLargeIncreased + (Config.general.rightToLeft ? otherSpace : barSpace)
            anchors.rightMargin: Tokens.padding.extraLargeIncreased + (Config.general.rightToLeft ? barSpace : otherSpace)

            state: Config.background.desktopClock.position
            states: [
                State {
                    name: "top-left"

                    AnchorChanges {
                        target: clockLoader
                        anchors.top: parent.top
                        anchors.left: parent.left
                    }
                },
                State {
                    name: "top-center"

                    AnchorChanges {
                        target: clockLoader
                        anchors.top: parent.top
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                },
                State {
                    name: "top-right"

                    AnchorChanges {
                        target: clockLoader
                        anchors.top: parent.top
                        anchors.right: parent.right
                    }
                },
                State {
                    name: "middle-left"

                    AnchorChanges {
                        target: clockLoader
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                    }
                },
                State {
                    name: "middle-center"

                    AnchorChanges {
                        target: clockLoader
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                },
                State {
                    name: "middle-right"

                    AnchorChanges {
                        target: clockLoader
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                    }
                },
                State {
                    name: "bottom-left"

                    AnchorChanges {
                        target: clockLoader
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                    }
                },
                State {
                    name: "bottom-center"

                    AnchorChanges {
                        target: clockLoader
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                },
                State {
                    name: "bottom-right"

                    AnchorChanges {
                        target: clockLoader
                        anchors.bottom: parent.bottom
                        anchors.right: parent.right
                    }
                }
            ]

            transitions: Transition {
                AnchorAnim {}
            }

            sourceComponent: DesktopClock {
                wallpaper: behindClock
                absX: clockLoader.x
                absY: clockLoader.y
            }
        }
    }
}
