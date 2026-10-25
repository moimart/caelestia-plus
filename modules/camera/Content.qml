pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtMultimedia as QM
import Quickshell
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.containers
import qs.components.controls
import qs.components.effects
import qs.services

// The camera panel: a mirror to check yourself, the camera's own controls,
// saved presets, and the camera features. While the mirror shows, the shell
// has the camera, so the daemon steps aside like it would for any app.
Item {
    id: root

    required property bool shown
    property string newPreset

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

    Keys.onEscapePressed: closeRequested()
    focus: true

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

                    QM.CaptureSession {
                        camera: QM.Camera {
                            active: root.shown
                            cameraDevice: devices.videoInputs.find(d => String(d.id).includes(GlobalConfig.camera.device)) ?? devices.defaultVideoInput
                        }
                        videoOutput: mirror
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
                            subtext: Tr.tr("Keep awake while you're here, lock when you leave")
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
                            subtext: Camera.gesturesState === "paused" ? Tr.tr("Paused while another app uses the camera") : Camera.gesturesState === "running" ? Tr.tr("Watching for gestures") : Tr.tr("Palm to pause, swipe to skip")
                            checked: GlobalConfig.camera.gestures.enabled
                            onToggled: GlobalConfig.camera.gestures.enabled = checked
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
