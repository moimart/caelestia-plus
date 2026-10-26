pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.components.effects
import qs.services

// Learning the hand gestures: one step per gesture, with a live view of where
// the camera sees your hand and what pose it reads, confirmation when it
// recognises the gesture, and a summary that turns gestures on.
Item {
    id: root

    readonly property var steps: [
        {
            gesture: "palm",
            pose: "open",
            icon: "back_hand",
            title: Tr.tr("Open palm"),
            how: Tr.tr("Raise an open hand, fingers up, and hold it still for a second."),
            action: GlobalConfig.camera.gestures.palm
        },
        {
            gesture: "swipe_right",
            pose: "open",
            icon: "swipe_right",
            title: Tr.tr("Swipe right"),
            how: Tr.tr("With an open hand, sweep quickly from your left to your right."),
            action: GlobalConfig.camera.gestures.swipeRight
        },
        {
            gesture: "swipe_left",
            pose: "open",
            icon: "swipe_left",
            title: Tr.tr("Swipe left"),
            how: Tr.tr("With an open hand, sweep quickly from your right to your left."),
            action: GlobalConfig.camera.gestures.swipeLeft
        },
        {
            gesture: "thumbs_up",
            pose: "thumbs_up",
            icon: "thumb_up",
            title: Tr.tr("Thumbs up"),
            how: Tr.tr("Make a fist with your thumb pointing up, and hold it for a second."),
            action: GlobalConfig.camera.gestures.thumbsUp
        },
        {
            gesture: "thumbs_down",
            pose: "thumbs_down",
            icon: "thumb_down",
            title: Tr.tr("Thumbs down"),
            how: Tr.tr("Make a fist with your thumb pointing down, and hold it for a second."),
            action: GlobalConfig.camera.gestures.thumbsDown
        }
    ]
    readonly property var gestureTitles: ({
            palm: Tr.tr("an open palm"),
            swipe_right: Tr.tr("a swipe right"),
            swipe_left: Tr.tr("a swipe left"),
            thumbs_up: Tr.tr("a thumbs up"),
            thumbs_down: Tr.tr("a thumbs down")
        })
    readonly property var poseNames: ({
            open: Tr.tr("an open hand"),
            thumbs_up: Tr.tr("a thumb up"),
            thumbs_down: Tr.tr("a thumb down"),
            other: Tr.tr("a hand")
        })

    property int index
    readonly property bool finished: index >= steps.length
    readonly property var step: finished ? null : steps[index]
    // gesture -> true (done) or false (skipped)
    property var results: ({})
    property bool success
    property string wrong
    readonly property var hand: Camera.hand
    readonly property bool matches: !!step && !!hand && hand.pose === step.pose

    function describe(action: string): string {
        switch (action) {
        case "media.toggle":
            return Tr.tr("Plays or pauses what's playing");
        case "media.next":
            return Tr.tr("Skips to the next track");
        case "media.previous":
            return Tr.tr("Goes back a track");
        case "media.stop":
            return Tr.tr("Stops playback");
        case "":
        case "none":
            return Tr.tr("Not assigned yet; pick an action in Settings → Camera");
        default:
            return Tr.tr("Runs: %1").arg(action);
        }
    }

    function record(done: bool): void {
        const r = Object.assign({}, results);
        r[step.gesture] = done;
        results = r;
    }

    function next(): void {
        success = false;
        wrong = "";
        index++;
    }

    function close(turnOn: bool): void {
        if (turnOn)
            GlobalConfig.camera.gestures.enabled = true;
        Camera.finishTutorial();
    }

    focus: true
    Keys.onEscapePressed: Camera.tutorial = false

    Connections {
        function onGesture(name: string): void {
            if (root.finished || root.success)
                return;
            if (name === root.step.gesture) {
                root.record(true);
                root.success = true;
                root.wrong = "";
                advance.restart();
            } else {
                root.wrong = name;
                clearWrong.restart();
            }
        }

        target: Camera
    }

    Timer {
        id: advance

        interval: 1300
        onTriggered: root.next()
    }

    Timer {
        id: clearWrong

        interval: 2200
        onTriggered: root.wrong = ""
    }

    StyledRect {
        anchors.fill: parent
        color: Qt.alpha(Colours.palette.m3scrim, 0.6)

        MouseArea {
            anchors.fill: parent
        }
    }

    Elevation {
        anchors.fill: card
        radius: card.radius
        level: 3
    }

    StyledRect {
        id: card

        anchors.centerIn: parent
        width: Math.min(parent.width - Tokens.padding.extraExtraLarge * 2, 900)
        implicitHeight: layout.implicitHeight + Tokens.padding.extraLarge * 2
        radius: Tokens.rounding.extraLarge
        color: Colours.tPalette.m3surfaceContainerLow

        ColumnLayout {
            id: layout

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.padding.extraLarge
            spacing: Tokens.spacing.large

            RowLayout {
                Layout.fillWidth: true

                StyledText {
                    Layout.fillWidth: true
                    text: Tr.tr("Hand gestures")
                    font: Tokens.font.headline.small
                }

                StyledText {
                    visible: !root.finished
                    text: Tr.tr("%1 of %2").arg(root.index + 1).arg(root.steps.length)
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.large
                }

                IconButton {
                    icon: "close"
                    type: IconButton.Text
                    onClicked: Camera.tutorial = false
                }
            }

            // A step
            RowLayout {
                Layout.fillWidth: true
                visible: !root.finished
                spacing: Tokens.spacing.extraLarge

                // What the camera sees, mirrored like a mirror
                ColumnLayout {
                    spacing: Tokens.spacing.small

                    StyledRect {
                        id: view

                        implicitWidth: 384
                        implicitHeight: 216
                        radius: Tokens.rounding.large
                        color: Colours.palette.m3surfaceContainerHighest
                        clip: true

                        // Swipes: which way to go
                        MaterialIcon {
                            anchors.centerIn: parent
                            visible: root.step?.gesture.startsWith("swipe") ?? false
                            text: root.step?.gesture === "swipe_right" ? "arrow_right_alt" : "arrow_left_alt"
                            color: Qt.alpha(Colours.palette.m3onSurfaceVariant, 0.25)
                            fontStyle: Tokens.font.icon.size(Tokens.font.icon.extraLarge.pointSize * 2.5).build()
                        }

                        StyledText {
                            anchors.centerIn: parent
                            visible: !root.hand && Camera.gesturesState !== "paused"
                            text: Tr.tr("Raise your hand")
                            color: Colours.palette.m3outline
                            font: Tokens.font.body.medium
                        }

                        StyledText {
                            anchors.centerIn: parent
                            visible: Camera.gesturesState === "paused"
                            text: Tr.tr("Another app has the camera")
                            color: Colours.palette.m3error
                            font: Tokens.font.body.medium
                        }

                        // The hand
                        StyledRect {
                            visible: !!root.hand
                            width: 34
                            height: 34
                            radius: 17
                            x: (1 - (root.hand?.x ?? 0.5)) * view.width - width / 2
                            y: (root.hand?.y ?? 0.5) * view.height - height / 2
                            color: root.matches ? Colours.palette.m3primary : "transparent"
                            border.width: 3
                            border.color: root.matches ? Colours.palette.m3onPrimary : Colours.palette.m3outline

                            Behavior on x {
                                Anim {
                                    type: Anim.FastSpatial
                                }
                            }

                            Behavior on y {
                                Anim {
                                    type: Anim.FastSpatial
                                }
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.hand ? Tr.tr("I see %1").arg(root.poseNames[root.hand.pose] ?? root.hand.pose) : Tr.tr("No hand in view")
                        color: root.matches ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.large
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                // The gesture to make
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.medium

                    StyledRect {
                        implicitWidth: 112
                        implicitHeight: 112
                        radius: 56
                        color: root.success ? Colours.palette.m3primary : Colours.palette.m3primaryContainer

                        Behavior on color {
                            CAnim {}
                        }

                        MaterialIcon {
                            id: hint

                            anchors.centerIn: parent
                            text: root.success ? "check" : (root.step?.icon ?? "")
                            color: root.success ? Colours.palette.m3onPrimary : Colours.palette.m3onPrimaryContainer
                            fill: 1
                            fontStyle: Tokens.font.icon.size(Tokens.font.icon.extraLarge.pointSize * 1.2).build()

                            // A gentle nudge in the gesture's direction
                            SequentialAnimation on anchors.horizontalCenterOffset {
                                running: !root.success && (root.step?.gesture.startsWith("swipe") ?? false)
                                loops: Animation.Infinite

                                NumberAnimation {
                                    to: root.step?.gesture === "swipe_right" ? 14 : -14
                                    duration: 450
                                    easing.type: Easing.OutCubic
                                }
                                NumberAnimation {
                                    to: 0
                                    duration: 650
                                    easing.type: Easing.InOutSine
                                }
                            }

                            SequentialAnimation on scale {
                                running: !root.success && !(root.step?.gesture.startsWith("swipe") ?? true)
                                loops: Animation.Infinite

                                NumberAnimation {
                                    to: 1.08
                                    duration: 700
                                    easing.type: Easing.InOutSine
                                }
                                NumberAnimation {
                                    to: 1
                                    duration: 700
                                    easing.type: Easing.InOutSine
                                }
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.success ? Tr.tr("Got it") : (root.step?.title ?? "")
                        font: Tokens.font.headline.medium
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.wrong ? Tr.tr("That looked like %1. Try once more.").arg(root.gestureTitles[root.wrong] ?? root.wrong) : (root.step?.how ?? "")
                        color: root.wrong ? Colours.palette.m3tertiary : Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.large
                        wrapMode: Text.WordWrap
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.describe(root.step?.action ?? "")
                        color: Colours.palette.m3outline
                        font: Tokens.font.body.small
                        wrapMode: Text.WordWrap
                    }
                }
            }

            // The summary
            ColumnLayout {
                Layout.fillWidth: true
                visible: root.finished
                spacing: Tokens.spacing.small

                StyledText {
                    Layout.fillWidth: true
                    text: Object.values(root.results).filter(v => v).length === root.steps.length ? Tr.tr("All five work. Gestures are ready.") : Tr.tr("Gestures you skipped still work; you can rerun this from Settings → Camera.")
                    font: Tokens.font.body.large
                    wrapMode: Text.WordWrap
                }

                Repeater {
                    model: root.steps

                    RowLayout {
                        id: summaryRow

                        required property var modelData
                        readonly property bool done: root.results[modelData.gesture] === true

                        spacing: Tokens.spacing.medium

                        MaterialIcon {
                            text: summaryRow.done ? "check_circle" : "radio_button_unchecked"
                            color: summaryRow.done ? Colours.palette.m3primary : Colours.palette.m3outline
                            fill: summaryRow.done ? 1 : 0
                        }

                        StyledText {
                            Layout.preferredWidth: 160
                            text: summaryRow.modelData.title
                            font: Tokens.font.body.medium
                        }

                        StyledText {
                            text: root.describe(summaryRow.modelData.action)
                            color: Colours.palette.m3outline
                            font: Tokens.font.body.small
                        }
                    }
                }
            }

            // Progress and buttons
            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                Row {
                    spacing: Tokens.spacing.extraSmall

                    Repeater {
                        model: root.steps.length

                        StyledRect {
                            required property int index

                            width: index === root.index ? 22 : 8
                            height: 8
                            radius: 4
                            color: index < root.index ? Colours.palette.m3primary : index === root.index ? Colours.palette.m3primary : Colours.palette.m3outlineVariant
                            opacity: index < root.index ? 0.5 : 1

                            Behavior on width {
                                Anim {
                                    type: Anim.FastSpatial
                                }
                            }
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                TextButton {
                    visible: !root.finished && root.index > 0 && !root.success
                    text: Tr.tr("Back")
                    type: TextButton.Text
                    onClicked: {
                        root.wrong = "";
                        root.index--;
                    }
                }

                TextButton {
                    visible: !root.finished && !root.success
                    text: Tr.tr("Skip")
                    type: TextButton.Tonal
                    onClicked: {
                        root.record(false);
                        root.next();
                    }
                }

                TextButton {
                    visible: root.finished
                    text: Tr.tr("Not now")
                    type: TextButton.Text
                    onClicked: root.close(false)
                }

                TextButton {
                    visible: root.finished
                    text: GlobalConfig.camera.gestures.enabled ? Tr.tr("Done") : Tr.tr("Turn on gestures")
                    type: TextButton.Filled
                    onClicked: root.close(true)
                }
            }
        }
    }
}
