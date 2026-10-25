pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    property bool howdyInstalled

    title: Tr.tr("Camera")

    Component.onCompleted: Camera.refreshControls()

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // Whether face unlock can work
        Process {
            running: true
            command: ["sh", "-c", "command -v howdy"]
            onExited: code => root.howdyInstalled = code === 0
        }

        ConnectedRect {
            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: hero.implicitHeight + Tokens.padding.extraLarge * 2

            RowLayout {
                id: hero

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Tokens.padding.extraLarge
                spacing: Tokens.spacing.large

                StyledRect {
                    implicitWidth: Math.round(Tokens.font.icon.large.pointSize * 2.6)
                    implicitHeight: implicitWidth
                    radius: Tokens.rounding.large
                    color: Camera.running ? Colours.palette.m3primaryContainer : Colours.palette.m3errorContainer

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: Camera.running ? "videocam" : "videocam_off"
                        color: Camera.running ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onErrorContainer
                        fill: 1
                        fontStyle: Tokens.font.icon.large
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.extraSmall

                    StyledText {
                        Layout.fillWidth: true
                        text: !Camera.running ? Tr.tr("Camera daemon not running") : !Camera.hasCamera ? Tr.tr("No camera found") : Camera.inUse ? Tr.tr("In use by %1").arg(Camera.others.map(u => u.name).join(", ")) : Tr.tr("Ready, and off")
                        font: Tokens.font.title.medium
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: !Camera.running ? (Camera.error || Tr.tr("Install the shell package with caelestia-camerad")) : !Camera.hasCamera ? Tr.tr("Plug in a webcam, or set the device below") : !Camera.vision ? Tr.tr("%1. Presence and gestures are off; the rest works.").arg(Camera.visionError) : Tr.tr("The camera only turns on while a feature needs a frame, and steps aside whenever an app wants it.")
                        color: Camera.running && Camera.hasCamera && Camera.vision ? Colours.palette.m3onSurfaceVariant : Colours.palette.m3error
                        font: Tokens.font.body.small
                        wrapMode: Text.WordWrap
                    }
                }

                IconTextButton {
                    icon: "open_in_full"
                    text: Tr.tr("Panel")
                    onClicked: Camera.openPanelRequested()
                }
            }
        }

        SectionHeader {
            text: Tr.tr("General")
        }

        ToggleRow {
            first: true
            text: Tr.trCtx("Enabled", "toggle label")
            subtext: Tr.tr("Run the camera daemon and its features")
            checked: GlobalConfig.camera.enabled
            onToggled: GlobalConfig.camera.enabled = checked
        }

        TextFieldRow {
            last: true
            label: Tr.tr("Device")
            subtext: Tr.tr("The camera's V4L2 device")
            value: GlobalConfig.camera.device
            onEditingFinished: value => GlobalConfig.camera.device = value.trim() || "/dev/video0"
        }

        SectionHeader {
            text: Tr.tr("Presence")
        }

        ToggleRow {
            first: true
            text: Tr.trCtx("Enabled", "toggle label")
            subtext: Camera.vision ? Tr.tr("While you're idle, check whether you're still at the desk") : Camera.visionError
            disabled: !Camera.vision
            checked: GlobalConfig.camera.presence.enabled
            onToggled: GlobalConfig.camera.presence.enabled = checked
        }

        ToggleRow {
            text: Tr.tr("Keep awake while you're here")
            subtext: Tr.tr("Reading or watching without touching anything won't dim or lock")
            checked: GlobalConfig.camera.presence.keepAwake
            onToggled: GlobalConfig.camera.presence.keepAwake = checked
        }

        ToggleRow {
            text: Tr.tr("Lock when you leave")
            checked: GlobalConfig.camera.presence.lockWhenAway
            onToggled: GlobalConfig.camera.presence.lockWhenAway = checked
        }

        ToggleRow {
            text: Tr.tr("Wake when you're back")
            subtext: Tr.tr("While locked, turn the screen on and start face unlock when you sit down")
            checked: GlobalConfig.camera.presence.wakeOnReturn
            onToggled: GlobalConfig.camera.presence.wakeOnReturn = checked
        }

        StepperRow {
            label: Tr.tr("Start checking after")
            subtext: Tr.tr("Seconds without input")
            value: GlobalConfig.camera.presence.checkAfter
            from: 15
            to: 600
            stepSize: 15
            onMoved: v => GlobalConfig.camera.presence.checkAfter = v
        }

        StepperRow {
            label: Tr.tr("Check every")
            subtext: Tr.tr("Seconds, while idle")
            value: GlobalConfig.camera.presence.interval
            from: 5
            to: 120
            stepSize: 5
            onMoved: v => GlobalConfig.camera.presence.interval = v
        }

        StepperRow {
            last: true
            label: Tr.tr("Away after")
            subtext: Tr.tr("Checks in a row without seeing you")
            value: GlobalConfig.camera.presence.awayAfter
            from: 1
            to: 10
            onMoved: v => GlobalConfig.camera.presence.awayAfter = v
        }

        SectionHeader {
            text: Tr.tr("Light sensor")
        }

        ToggleRow {
            first: true
            text: Tr.trCtx("Enabled", "toggle label")
            subtext: Tr.tr("The camera has no exposure control, so readings are relative: calibrate the levels below with Read now")
            checked: GlobalConfig.camera.light.enabled
            onToggled: GlobalConfig.camera.light.enabled = checked
        }

        ConnectedRect {
            Layout.fillWidth: true
            implicitHeight: readRow.implicitHeight + Tokens.padding.medium * 2

            RowLayout {
                id: readRow

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased

                StyledText {
                    Layout.fillWidth: true
                    text: Camera.lastLight ? Tr.tr("Room light now: %1").arg(Camera.lastLight.level.toFixed(2)) : Tr.tr("No reading yet")
                    font: Tokens.font.body.small
                }

                TextButton {
                    text: Tr.tr("Read now")
                    type: TextButton.Tonal
                    onClicked: Camera.light(null)
                }
            }
        }

        ToggleRow {
            text: Tr.tr("Adjust brightness")
            checked: GlobalConfig.camera.light.adjustBrightness
            onToggled: GlobalConfig.camera.light.adjustBrightness = checked
        }

        StepperRow {
            label: Tr.tr("Dark room level")
            value: GlobalConfig.camera.light.darkLevel
            from: 0
            to: 1
            stepSize: 0.01
            onMoved: v => GlobalConfig.camera.light.darkLevel = Math.round(v * 100) / 100
        }

        StepperRow {
            label: Tr.tr("Bright room level")
            value: GlobalConfig.camera.light.brightLevel
            from: 0
            to: 1
            stepSize: 0.01
            onMoved: v => GlobalConfig.camera.light.brightLevel = Math.round(v * 100) / 100
        }

        StepperRow {
            label: Tr.tr("Brightness in the dark")
            value: GlobalConfig.camera.light.minBrightness
            from: 0
            to: 1
            stepSize: 0.05
            onMoved: v => GlobalConfig.camera.light.minBrightness = Math.round(v * 100) / 100
        }

        StepperRow {
            label: Tr.tr("Brightness in daylight")
            value: GlobalConfig.camera.light.maxBrightness
            from: 0
            to: 1
            stepSize: 0.05
            onMoved: v => GlobalConfig.camera.light.maxBrightness = Math.round(v * 100) / 100
        }

        StepperRow {
            label: Tr.tr("Read every")
            subtext: Tr.tr("Seconds")
            value: GlobalConfig.camera.light.interval
            from: 30
            to: 3600
            stepSize: 30
            onMoved: v => GlobalConfig.camera.light.interval = v
        }

        ToggleRow {
            last: true
            text: Tr.tr("Switch light and dark scheme")
            subtext: Tr.tr("Dark below the dark level, light above the bright level")
            checked: GlobalConfig.camera.light.switchScheme
            onToggled: GlobalConfig.camera.light.switchScheme = checked
        }

        SectionHeader {
            text: Tr.tr("Gestures")
        }

        ToggleRow {
            first: true
            text: Tr.trCtx("Enabled", "toggle label")
            subtext: !Camera.vision ? Camera.visionError : Camera.gesturesState === "paused" ? Tr.tr("Paused while another app uses the camera") : Tr.tr("Keeps the camera on while enabled; pauses whenever an app needs it")
            disabled: !Camera.vision
            checked: GlobalConfig.camera.gestures.enabled
            onToggled: {
                // The first time, the tutorial turns them on at its end
                const want = checked;
                if (want && !Camera.tutorialDone)
                    checked = false;
                Camera.setGesturesEnabled(want);
            }
        }

        ConnectedRect {
            Layout.fillWidth: true
            implicitHeight: tutorialRow.implicitHeight + Tokens.padding.medium * 2

            RowLayout {
                id: tutorialRow

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased

                StyledText {
                    Layout.fillWidth: true
                    text: Tr.tr("Learn the gestures, with a live view of what the camera sees")
                    font: Tokens.font.body.small
                    wrapMode: Text.WordWrap
                }

                TextButton {
                    text: Tr.tr("Gesture tutorial")
                    type: TextButton.Tonal
                    disabled: !Camera.vision
                    onClicked: Camera.tutorial = true
                }
            }
        }

        ActionRow {
            label: Tr.tr("Open palm, held")
            value: GlobalConfig.camera.gestures.palm
            onEditingFinished: value => GlobalConfig.camera.gestures.palm = value.trim() || "none"
        }

        ActionRow {
            label: Tr.tr("Swipe left")
            value: GlobalConfig.camera.gestures.swipeLeft
            onEditingFinished: value => GlobalConfig.camera.gestures.swipeLeft = value.trim() || "none"
        }

        ActionRow {
            label: Tr.tr("Swipe right")
            value: GlobalConfig.camera.gestures.swipeRight
            onEditingFinished: value => GlobalConfig.camera.gestures.swipeRight = value.trim() || "none"
        }

        ActionRow {
            label: Tr.tr("Thumbs up, held")
            value: GlobalConfig.camera.gestures.thumbsUp
            onEditingFinished: value => GlobalConfig.camera.gestures.thumbsUp = value.trim() || "none"
        }

        ActionRow {
            last: true
            label: Tr.tr("Thumbs down, held")
            value: GlobalConfig.camera.gestures.thumbsDown
            onEditingFinished: value => GlobalConfig.camera.gestures.thumbsDown = value.trim() || "none"
        }

        SectionHeader {
            text: Tr.tr("Lock screen")
        }

        ToggleRow {
            first: true
            text: Tr.tr("Face unlock")
            subtext: root.howdyInstalled ? Tr.tr("With howdy. The camera has no infrared, so a photo could fool it: keep a password too") : Tr.tr("Needs howdy installed and your face added: see FORK.md")
            checked: GlobalConfig.lock.enableHowdy
            onToggled: GlobalConfig.lock.enableHowdy = checked
        }

        ToggleRow {
            text: Tr.tr("Photo after wrong passwords")
            subtext: Tr.tr("Shown to you once you unlock")
            checked: GlobalConfig.camera.snapshots.enabled
            onToggled: GlobalConfig.camera.snapshots.enabled = checked
        }

        StepperRow {
            label: Tr.tr("Wrong passwords before the photo")
            value: GlobalConfig.camera.snapshots.afterFailures
            from: 1
            to: 10
            onMoved: v => GlobalConfig.camera.snapshots.afterFailures = v
        }

        TextFieldRow {
            last: true
            label: Tr.tr("Photos folder")
            value: GlobalConfig.camera.snapshots.dir
            onEditingFinished: value => GlobalConfig.camera.snapshots.dir = value.trim() || "~/Pictures/Unlock attempts"
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.large
            Layout.leftMargin: Tokens.padding.small
            text: Tr.tr("Gesture actions: media.toggle, media.next, media.previous, media.stop, none, or any shell command. For Chrome to share the camera with these features, enable chrome://flags/#enable-webrtc-pipewire-camera.")
            color: Colours.palette.m3outline
            font: Tokens.font.label.medium
            wrapMode: Text.WordWrap
        }
    }

    component ActionRow: TextFieldRow {
        placeholderText: "none"
    }
}
