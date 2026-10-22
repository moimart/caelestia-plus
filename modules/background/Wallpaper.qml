pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.filedialog
import qs.components.images
import qs.services
import qs.utils

// The wallpaper for one screen. Images crossfade as before. A video shows as
// its poster frame first; once the poster is fully visible the video starts
// underneath (VideoPlayer), and the poster fades out when frames are playing.
Item {
    id: root

    required property ShellScreen screen
    property bool locked

    readonly property var chosen: Wallpapers.forScreen(screen.name)
    property string source: chosen.image
    property CachingImage current
    property bool completed

    // The video handed to the player; lags `chosen.video` until its poster is shown.
    property string shownVideo
    readonly property bool videoShowing: chosen.video !== "" && player.video === chosen.video && player.playing
    readonly property bool hasVideo: player.active

    onSourceChanged: {
        if (!source)
            current = null;
        else
            current = imgComp.createObject(images, {
                path: source
            });
        handover.restart();
    }

    onChosenChanged: handover.restart()

    Component.onCompleted: {
        if (source)
            Qt.callLater(() => {
                current = imgComp.createObject(images, {
                    path: source
                });
                completed = true;
                handover.restart();
            });
    }

    // Swap the video once the current image is on screen and fully faded in,
    // so neither the old video nor the old image is seen through it.
    Timer {
        id: handover

        interval: Tokens.anim.durations.expressiveSlowEffects
        onTriggered: {
            // Previews are opaque stills; leave the video running underneath.
            if (Wallpapers.showPreview)
                return;
            if (root.chosen.video && root.current?.status !== Image.Ready)
                return restart();
            player.startTime = root.chosen.time;
            root.shownVideo = root.chosen.video;
        }
    }

    VideoPlayer {
        id: player

        screenName: root.screen.name
        video: root.shownVideo
        paused: {
            if (!GlobalConfig.forScreen(root.screen.name).background.video.pauseWhenHidden)
                return false;
            if (root.locked || GameMode.enabled)
                return true;
            const ws = Hypr.monitorFor(root.screen)?.activeWorkspace;
            return ws?.toplevels.values.some(t => t.lastIpcObject.fullscreen > 1) ?? false;
        }
    }

    Item {
        id: images

        anchors.fill: parent
        opacity: root.videoShowing ? 0 : 1

        Behavior on opacity {
            Anim {
                type: Anim.SlowEffects
            }
        }
    }

    Loader {
        asynchronous: true
        anchors.fill: parent

        active: root.completed && !root.source

        sourceComponent: StyledRect {
            color: Colours.palette.m3surfaceContainer

            Row {
                anchors.centerIn: parent
                spacing: Tokens.spacing.largeIncreased

                MaterialIcon {
                    text: "sentiment_stressed"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.builders.extraLarge.scale(5).build()
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Tokens.spacing.small

                    StyledText {
                        text: qsTr("Wallpaper missing?")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.builders.large.size(28 * 2).weight(Font.Bold).build()
                    }

                    StyledRect {
                        implicitWidth: selectWallText.implicitWidth + Tokens.padding.extraLargeIncreased
                        implicitHeight: selectWallText.implicitHeight + Tokens.padding.small

                        radius: Tokens.rounding.full
                        color: Colours.palette.m3primary

                        FileDialog {
                            id: dialog

                            title: qsTr("Select a wallpaper")
                            filterLabel: qsTr("Image files")
                            filters: Images.validImageExtensions
                            onAccepted: path => Wallpapers.setWallpaper(path)
                        }

                        StateLayer {
                            radius: parent.radius
                            color: Colours.palette.m3onPrimary
                            onClicked: dialog.open()
                        }

                        StyledText {
                            id: selectWallText

                            anchors.centerIn: parent

                            text: qsTr("Set it now!")
                            color: Colours.palette.m3onPrimary
                            font: Tokens.font.body.large
                        }
                    }
                }
            }
        }
    }

    Component {
        id: imgComp

        CachingImage {
            id: img

            anchors.fill: parent

            opacity: 0

            onStatusChanged: {
                if (status === Image.Ready)
                    anim.start();
            }

            Anim on opacity {
                id: anim

                type: Anim.SlowEffects
                running: false
                from: 0
                to: 1
            }

            Timer {
                running: root.current !== img && root.current?.status === Image.Ready
                interval: anim.duration
                onTriggered: img.destroy()
            }
        }
    }
}
