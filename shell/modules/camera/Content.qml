pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtMultimedia as QM
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.containers
import qs.components.controls
import qs.components.effects
import qs.services
import qs.utils

// The camera panel: a mirror to check yourself, the camera's own controls,
// saved presets, and the camera features. While the mirror shows, the shell
// has the camera, so the daemon steps aside like it would for any app.
Item {
    id: root

    required property bool shown
    property string newPreset
    // Recording (assets/camera-record.sh): sound from the camera's microphone,
    // unless turned off. ffmpeg has the camera meanwhile and feeds the mirror.
    property bool withMic: true
    property string savingTo
    // Asked to record before the camera was ready: start once it is
    property bool recordWhenReady
    // Waiting for the mirror to let go of the camera
    property bool starting
    property int startAttempts
    // The mirror is showing the camera
    property bool mirrorLive
    property real recordStart
    property real now
    property int previewTick
    readonly property bool recording: starting || recorder.running
    readonly property string previewPath: `${Quickshell.env("XDG_RUNTIME_DIR")}/caelestia-camera-preview.jpg`

    // Controls grouped for the panel, keyed by V4L2 control name
    readonly property var groups: [
        {
            title: Tr.tr("Framing"),
            icon: "crop_free",
            keys: ["zoom_absolute", "pan_absolute", "tilt_absolute"]
        },
        {
            title: Tr.tr("Image"),
            icon: "tune",
            keys: ["brightness", "contrast", "saturation", "sharpness", "hue"]
        },
        {
            title: Tr.tr("Focus and colour"),
            icon: "center_focus_strong",
            keys: ["focus_automatic_continuous", "focus_absolute", "white_balance_automatic", "white_balance_temperature", "power_line_frequency"]
        }
    ]
    readonly property var grouped: groups.reduce((all, g) => all.concat(g.keys), [])

    signal closeRequested
    signal hidden

    function takeRecordRequest(): void {
        if (shown && Camera.recordOnOpen) {
            Camera.recordOnOpen = false;
            toggleRecording();
        }
    }

    function toggleRecording(): void {
        if (recorder.running) {
            recorder.write("q\n");
        } else if (starting) {
            starting = false;
            savingTo = "";
            startTimer.stop();
        } else if (!mirrorLive) {
            recordWhenReady = true;
        } else {
            // The mirror lets go of the camera first
            starting = true;
            startAttempts = 0;
            startTimer.restart();
        }
    }

    // Closing the panel ends a recording, and ffmpeg finishes writing the file
    onShownChanged: {
        recordWhenReady = false;
        if (!shown && recording)
            toggleRecording();
        takeRecordRequest();
    }
    Component.onCompleted: takeRecordRequest()
    onRecordingChanged: Camera.recording = recording

    Keys.onEscapePressed: closeRequested()
    focus: true

    Connections {
        function onRecordRequested(): void {
            root.toggleRecording();
        }

        target: Camera
    }

    StyledRect {
        anchors.fill: parent
        color: Qt.alpha(Colours.palette.m3scrim, 0.45)
        opacity: root.shown ? 1 : 0

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.closeRequested()
        }
    }

    Elevation {
        anchors.fill: sheet
        radius: sheet.radius
        opacity: sheet.opacity
        scale: sheet.scale
        level: 3
    }

    StyledRect {
        id: sheet

        anchors.centerIn: parent
        width: Math.min(parent.width - Tokens.padding.extraExtraLarge * 2, 1500)
        height: Math.min(parent.height - Tokens.padding.extraExtraLarge * 2, 860)
        radius: Tokens.rounding.extraLarge
        color: Colours.tPalette.m3surfaceContainerLow
        opacity: root.shown ? 1 : 0
        scale: root.shown ? 1 : 0.95

        onOpacityChanged: {
            if (opacity === 0 && !root.shown)
                root.hidden();
        }

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }

        Behavior on scale {
            Anim {
                type: Anim.DefaultSpatial
            }
        }

        MouseArea {
            anchors.fill: parent
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: Tokens.padding.extraLarge
            spacing: Tokens.spacing.extraLarge

            // Mirror, and who's using the camera
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 3
                spacing: Tokens.spacing.medium

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.medium

                    MaterialIcon {
                        text: "videocam"
                        color: Colours.palette.m3primary
                        fill: 1
                        fontStyle: Tokens.font.icon.large
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Tr.tr("Camera")
                        font: Tokens.font.headline.small
                    }

                    StyledText {
                        text: Camera.running ? "" : Camera.error || Tr.tr("Camera daemon not running")
                        color: Colours.palette.m3error
                        font: Tokens.font.label.medium
                    }
                }

                ClipRect {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Tokens.rounding.large
                    color: Colours.palette.m3surfaceContainerHighest

                    QM.MediaDevices {
                        id: devices
                    }

                    // The mirror's camera. Switching it off doesn't close the device, so
                    // it's destroyed while a recording needs the camera.
                    Loader {
                        active: root.shown && !root.recording

                        sourceComponent: Item {
                            Component.onDestruction: root.mirrorLive = false

                            QM.CaptureSession {
                                camera: QM.Camera {
                                    onActiveChanged: {
                                        root.mirrorLive = active;
                                        if (active && root.recordWhenReady) {
                                            root.recordWhenReady = false;
                                            root.toggleRecording();
                                        }
                                    }

                                    // Once the daemon has let go of the camera (gestures pause
                                    // while this is open)
                                    active: !Camera.capturing
                                    cameraDevice: devices.videoInputs.find(d => String(d.id).includes(GlobalConfig.camera.device)) ?? devices.defaultVideoInput
                                    // 1080p at the best frame rate: 4K is more than a mirror needs
                                    cameraFormat: {
                                        const formats = cameraDevice.videoFormats.filter(f => f.resolution.width === 1920 && f.resolution.height === 1080);
                                        return formats.sort((a, b) => b.maxFrameRate - a.maxFrameRate)[0] ?? cameraDevice.videoFormats[0];
                                    }
                                }
                                videoOutput: mirror
                            }
                        }
                    }

                    Timer {
                        id: startTimer

                        interval: 300
                        onTriggered: {
                            root.startAttempts++;
                            if (root.savingTo) {
                                recorder.running = true;
                                return;
                            }
                            const name = `Camera ${Qt.formatDateTime(new Date(), "yyyy-MM-dd hh-mm-ss")}.mp4`;
                            root.savingTo = `${Paths.videos}/Camera/${name}`;
                            recorder.running = true;
                        }
                    }

                    // Videos go to ~/Videos/Camera, the right way round (not mirrored)
                    Process {
                        id: recorder

                        command: ["sh", "-c", 'mkdir -p "$(dirname "$2")" && exec sh "$1" "$3" "$2" "$4" "$5"', "sh", Quickshell.shellPath("assets/camera-record.sh"), root.savingTo, GlobalConfig.camera.device, root.previewPath, root.withMic ? "on" : "off"]
                        stdinEnabled: true
                        stderr: StdioCollector {
                            id: recorderErrors
                        }

                        onRunningChanged: {
                            if (running) {
                                root.recordStart = Date.now();
                                root.now = root.recordStart;
                            }
                        }
                        onExited: code => {
                            // The mirror can take a moment to let go of the camera
                            if (code !== 0 && root.starting && root.startAttempts < 15 && /busy/i.test(recorderErrors.text)) {
                                startTimer.restart();
                                return;
                            }
                            const path = root.savingTo;
                            root.savingTo = "";
                            root.starting = false;
                            if (code !== 0)
                                console.warn("camera-record:", code, recorderErrors.text);
                            if (code === 0)
                                Toaster.toast(Tr.tr("Video saved"), Paths.shortenHome(path), "videocam");
                            else
                                Toaster.toast(Tr.tr("Couldn't record"), recorderErrors.text.trim().split("\n").pop() || Tr.tr("ffmpeg exited (%1)").arg(code), "videocam_off", Toast.Error);
                        }
                    }

                    // Recording for real: no more retries, and the mirror stays off until it ends
                    Timer {
                        running: recorder.running
                        interval: 2000
                        onTriggered: root.starting = false
                    }

                    Timer {
                        running: recorder.running
                        repeat: true
                        interval: 66
                        onTriggered: {
                            root.previewTick++;
                            root.now = Date.now();
                        }
                    }

                    // Mirrored, as you'd expect from a mirror
                    QM.VideoOutput {
                        id: mirror

                        anchors.fill: parent
                        fillMode: QM.VideoOutput.PreserveAspectCrop
                        transform: Scale {
                            origin.x: mirror.width / 2
                            xScale: -1
                        }
                    }

                    // While recording, ffmpeg has the camera: its preview stands in
                    Image {
                        anchors.fill: parent
                        visible: recorder.running
                        fillMode: Image.PreserveAspectCrop
                        cache: false
                        source: recorder.running ? `file://${root.previewPath}?${root.previewTick}` : ""
                    }

                    // While recording: a red dot and the time
                    StyledRect {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.margins: Tokens.padding.large
                        visible: root.recording
                        implicitWidth: recRow.implicitWidth + Tokens.padding.medium * 2
                        implicitHeight: recRow.implicitHeight + Tokens.padding.small * 2
                        radius: Tokens.rounding.full
                        color: Qt.alpha(Colours.palette.m3scrim, 0.6)

                        Row {
                            id: recRow

                            anchors.centerIn: parent
                            spacing: Tokens.spacing.small

                            StyledRect {
                                anchors.verticalCenter: parent.verticalCenter
                                implicitWidth: 10
                                implicitHeight: 10
                                radius: 5
                                color: Colours.palette.m3error

                                SequentialAnimation on opacity {
                                    running: root.recording
                                    loops: Animation.Infinite

                                    NumberAnimation {
                                        to: 0.3
                                        duration: 700
                                    }
                                    NumberAnimation {
                                        to: 1
                                        duration: 700
                                    }
                                }
                            }

                            StyledText {
                                text: {
                                    const s = Math.max(0, Math.floor((root.now - root.recordStart) / 1000));
                                    const pad = n => String(n).padStart(2, "0");
                                    return `${Math.floor(s / 60)}:${pad(s % 60)}`;
                                }
                                color: "white"
                                font: Tokens.font.label.large
                            }
                        }
                    }

                    // Record, and whether to record sound
                    Row {
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottomMargin: Tokens.padding.large
                        spacing: Tokens.spacing.large

                        IconButton {
                            anchors.verticalCenter: parent.verticalCenter
                            icon: root.withMic ? "mic" : "mic_off"
                            type: IconButton.Tonal
                            disabled: root.recording
                            onClicked: root.withMic = !root.withMic
                        }

                        // A white ring with a red dot, square while recording
                        Item {
                            implicitWidth: 64
                            implicitHeight: 64
                            opacity: root.mirrorLive || root.recording ? 1 : 0.4

                            StyledRect {
                                anchors.fill: parent
                                radius: width / 2
                                color: "transparent"
                                border.width: 4
                                border.color: "white"
                            }

                            StyledRect {
                                anchors.centerIn: parent
                                implicitWidth: root.recording ? 24 : 48
                                implicitHeight: implicitWidth
                                radius: root.recording ? 6 : implicitWidth / 2
                                color: Colours.palette.m3error

                                Behavior on implicitWidth {
                                    Anim {}
                                }

                                Behavior on radius {
                                    Anim {}
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                enabled: root.mirrorLive || root.recording
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.toggleRecording()
                            }
                        }

                        IconButton {
                            anchors.verticalCenter: parent.verticalCenter
                            icon: "folder_open"
                            type: IconButton.Tonal
                            onClicked: Quickshell.execDetached(["sh", "-c", `mkdir -p "$1" && xdg-open "$1"`, "sh", `${Paths.videos}/Camera`])
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    MaterialIcon {
                        text: Camera.others.length > 0 ? "groups" : "visibility_off"
                        color: Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.small
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: {
                            const apps = Camera.others.filter(u => !u.shell).map(u => u.name);
                            return apps.length > 0 ? Tr.tr("Also using the camera: %1").arg(apps.join(", ")) : Tr.tr("No other app is using the camera");
                        }
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.small
                        elide: Text.ElideRight
                    }
                }
            }

            // Controls, presets and features
            StyledFlickable {
                id: side

                Layout.fillHeight: true
                Layout.fillWidth: true
                Layout.preferredWidth: 2
                clip: true
                contentWidth: width
                contentHeight: sideColumn.implicitHeight

                StyledScrollBar.vertical: StyledScrollBar {
                    flickable: side
                }

                ColumnLayout {
                    id: sideColumn

                    width: side.width - Tokens.padding.medium
                    spacing: Tokens.spacing.medium

                    RowLayout {
                        Layout.fillWidth: true

                        Item {
                            Layout.fillWidth: true
                        }

                        IconButton {
                            icon: "settings"
                            type: IconButton.Text
                            onClicked: {
                                root.closeRequested();
                                Quickshell.execDetached(["caelestia", "shell", "nexus", "page", "camera"]);
                            }
                        }

                        IconButton {
                            icon: "close"
                            type: IconButton.Text
                            onClicked: root.closeRequested()
                        }
                    }

                    // Presets
                    Card {
                        title: Tr.tr("Presets")
                        icon: "bookmarks"

                        Flow {
                            Layout.fillWidth: true
                            spacing: Tokens.spacing.small

                            Repeater {
                                model: Camera.presets

                                IconTextButton {
                                    required property var modelData

                                    icon: "photo_camera"
                                    text: modelData.name
                                    type: TextButton.Tonal
                                    onClicked: Camera.applyPreset(modelData.name)
                                }
                            }

                            StyledText {
                                visible: Camera.presets.length === 0
                                text: Tr.tr("Set the camera up, then save it as a preset")
                                color: Colours.palette.m3outline
                                font: Tokens.font.body.small
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.spacing.small

                            StyledTextField {
                                id: presetName

                                Layout.fillWidth: true
                                placeholderText: Tr.tr("Preset name, e.g. Desk or Call")
                                onAccepted: saveBtn.clicked()
                            }

                            TextButton {
                                id: saveBtn

                                text: Tr.tr("Save")
                                type: TextButton.Filled
                                disabled: presetName.text.trim() === ""
                                onClicked: {
                                    Camera.savePreset(presetName.text.trim());
                                    presetName.text = "";
                                }
                            }

                            IconButton {
                                icon: "delete"
                                type: IconButton.Text
                                visible: Camera.presets.some(p => p.name === presetName.text.trim())
                                onClicked: Camera.deletePreset(presetName.text.trim())
                            }
                        }
                    }

                    // The camera's controls, in groups
                    Repeater {
                        model: root.groups

                        Card {
                            id: group

                            required property var modelData
                            readonly property var items: modelData.keys.map(k => Camera.controls.find(c => c.key === k)).filter(c => c)

                            visible: items.length > 0
                            title: modelData.title
                            icon: modelData.icon

                            Repeater {
                                model: group.items

                                ControlRow {
                                    required property var modelData

                                    control: modelData
                                }
                            }
                        }
                    }

                    // Anything the groups above don't cover
                    Card {
                        id: otherCard

                        readonly property var items: Camera.controls.filter(c => !root.grouped.includes(c.key) && c.type !== "button")

                        visible: items.length > 0
                        title: Tr.tr("Other")
                        icon: "more_horiz"

                        Repeater {
                            model: otherCard.items

                            ControlRow {
                                required property var modelData

                                control: modelData
                            }
                        }
                    }

                    // Features
                    Card {
                        title: Tr.tr("Camera features")
                        icon: "auto_awesome"

                        Feature {
                            icon: "person_search"
                            text: Tr.tr("Presence")
                            subtext: Camera.vision ? Tr.tr("Keep awake while you're here, lock when you leave") : Camera.visionError
                            disabled: !Camera.vision
                            checked: GlobalConfig.camera.presence.enabled
                            onToggled: GlobalConfig.camera.presence.enabled = checked
                        }

                        Feature {
                            icon: "light_mode"
                            text: Tr.tr("Light sensor")
                            subtext: Camera.lastLight ? Tr.tr("Room light %1").arg(Camera.lastLight.level.toFixed(2)) : Tr.tr("Set brightness from the room's light")
                            checked: GlobalConfig.camera.light.enabled
                            onToggled: GlobalConfig.camera.light.enabled = checked
                        }

                        Feature {
                            icon: "back_hand"
                            text: Tr.tr("Gestures")
                            subtext: !Camera.vision ? Camera.visionError : Camera.gesturesState === "paused" ? Tr.tr("Paused while another app uses the camera") : Camera.gesturesState === "running" ? Tr.tr("Watching for gestures") : Tr.tr("Palm to pause, swipe to skip")
                            disabled: !Camera.vision
                            checked: GlobalConfig.camera.gestures.enabled
                            onToggled: {
                                // The first time, the tutorial turns them on at its end
                                const want = checked;
                                if (want && !Camera.tutorialDone) {
                                    checked = false;
                                    root.closeRequested();
                                }
                                Camera.setGesturesEnabled(want);
                            }
                        }

                        Feature {
                            icon: "photo_camera_front"
                            text: Tr.tr("Unlock-attempt photos")
                            subtext: Tr.tr("A photo after %1 wrong passwords").arg(GlobalConfig.camera.snapshots.afterFailures)
                            checked: GlobalConfig.camera.snapshots.enabled
                            onToggled: GlobalConfig.camera.snapshots.enabled = checked
                        }
                    }
                }
            }
        }
    }

    component Card: StyledRect {
        id: card

        default property alias content: cardColumn.data
        property alias title: cardTitle.text
        property alias icon: cardIcon.text

        Layout.fillWidth: true
        implicitHeight: cardColumn.implicitHeight + Tokens.padding.large * 2
        radius: Tokens.rounding.large
        color: Colours.tPalette.m3surfaceContainer

        ColumnLayout {
            id: cardColumn

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.padding.large
            spacing: Tokens.spacing.small

            RowLayout {
                spacing: Tokens.spacing.small

                MaterialIcon {
                    id: cardIcon

                    color: Colours.palette.m3primary
                    fill: 1
                }

                StyledText {
                    id: cardTitle

                    font: Tokens.font.title.small
                }
            }
        }
    }

    component ControlRow: RowLayout {
        id: row

        required property var control
        readonly property bool isBool: control.type === "bool"
        readonly property bool isMenu: control.type === "menu"

        Layout.fillWidth: true
        spacing: Tokens.spacing.medium
        opacity: control.inactive ? 0.45 : 1

        StyledText {
            Layout.preferredWidth: Tokens.font.body.small.pointSize * 14
            text: row.control.name
            font: Tokens.font.body.small
            elide: Text.ElideRight
        }

        StyledSlider {
            Layout.fillWidth: true
            implicitHeight: Tokens.font.body.small.pointSize * 2.4
            visible: !row.isBool && !row.isMenu
            enabled: !row.control.inactive
            from: row.control.min
            to: row.control.max
            stepSize: row.control.step
            value: row.control.value ?? row.control.default
            onMoved: Camera.setControl(row.control.key, Math.round(value))
        }

        StyledText {
            visible: !row.isBool && !row.isMenu
            Layout.preferredWidth: Tokens.font.body.small.pointSize * 4
            horizontalAlignment: Text.AlignRight
            text: row.control.value ?? ""
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.medium
        }

        Item {
            Layout.fillWidth: true
            visible: row.isBool || row.isMenu
        }

        StyledSwitch {
            visible: row.isBool
            checked: row.control.value === true
            onToggled: Camera.setControl(row.control.key, checked)
        }

        // Menus are short (e.g. 50/60 Hz): click to cycle
        TextButton {
            visible: row.isMenu
            type: TextButton.Tonal
            text: (row.control.menu ?? []).find(m => m.value === row.control.value)?.label ?? String(row.control.value)
            onClicked: {
                const items = row.control.menu ?? [];
                const i = items.findIndex(m => m.value === row.control.value);
                if (items.length > 0)
                    Camera.setControl(row.control.key, items[(i + 1) % items.length].value);
            }
        }
    }

    component Feature: RowLayout {
        id: feature

        property alias icon: featureIcon.text
        property alias text: featureText.text
        property alias subtext: featureSub.text
        property alias checked: featureSwitch.checked
        property alias disabled: featureSwitch.disabled

        signal toggled

        Layout.fillWidth: true
        spacing: Tokens.spacing.medium

        MaterialIcon {
            id: featureIcon

            color: Colours.palette.m3onSurfaceVariant
            fontStyle: Tokens.font.icon.medium
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                id: featureText

                Layout.fillWidth: true
                font: Tokens.font.body.medium
            }

            StyledText {
                id: featureSub

                Layout.fillWidth: true
                color: Colours.palette.m3outline
                font: Tokens.font.label.small
                elide: Text.ElideRight
            }
        }

        StyledSwitch {
            id: featureSwitch

            onToggled: feature.toggled()
        }
    }
}
