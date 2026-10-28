pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils

// The right bar: as thick as the left one, with action buttons at the top
// (Config.rightBar.actions, see services/BarActions) and the volume at the
// bottom. Its background is the drawers' frame, which widens its right side
// to fit; this is only what's on it.
Item {
    id: root

    required property ShellScreen screen
    required property bool fullscreen

    readonly property bool on: Config.rightBar.enabled
    readonly property int padding: Math.max(Tokens.padding.small, Config.border.thickness)
    readonly property int contentWidth: Tokens.sizes.bar.innerWidth + padding * 2
    // Its width on screen: none when off, or while a window is fullscreen
    readonly property int thickness: on && !fullscreen ? contentWidth : 0
    readonly property int exclusiveZone: on ? contentWidth : Config.border.thickness
    readonly property var actions: Config.rightBar.actions.map(id => BarActions.find(id)).filter(a => a)

    implicitWidth: thickness
    clip: true
    visible: thickness > 0

    Behavior on implicitWidth {
        Anim {}
    }

    // The buttons
    StyledRect {
        id: actionsGroup

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Tokens.padding.large
        visible: root.actions.length > 0

        implicitWidth: Tokens.sizes.bar.innerWidth
        implicitHeight: buttons.implicitHeight + Tokens.padding.small * 2
        color: Colours.tPalette.m3surfaceContainer
        radius: Tokens.rounding.full

        Column {
            id: buttons

            anchors.centerIn: parent
            spacing: Tokens.spacing.small

            Repeater {
                model: root.actions

                Column {
                    id: action

                    required property var modelData
                    readonly property bool active: BarActions.isActive(modelData)

                    spacing: 0

                    IconButton {
                        anchors.horizontalCenter: parent.horizontalCenter
                        type: action.active ? IconButton.Filled : IconButton.Text
                        icon: action.active ? "stop_circle" : action.modelData.icon
                        onClicked: action.modelData.run()
                    }

                    // How long the recording has run
                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: action.active
                        text: {
                            const s = Math.floor(Recorder.elapsed);
                            return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
                        }
                        color: Colours.palette.m3primary
                        font: Tokens.font.label.small
                    }
                }
            }
        }
    }

    // The volume, always there
    StyledRect {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Tokens.padding.large
        visible: Config.rightBar.volume || Config.rightBar.microphone

        implicitWidth: Tokens.sizes.bar.innerWidth
        implicitHeight: sliders.implicitHeight + Tokens.padding.small * 2
        color: Colours.tPalette.m3surfaceContainer
        radius: Tokens.rounding.full

        Column {
            id: sliders

            anchors.centerIn: parent
            spacing: Tokens.spacing.small

            CustomMouseArea {
                function onWheel(event: WheelEvent) {
                    if (event.angleDelta.y > 0)
                        Audio.incrementVolume();
                    else if (event.angleDelta.y < 0)
                        Audio.decrementVolume();
                }

                visible: Config.rightBar.volume
                implicitWidth: Tokens.sizes.osd.sliderWidth
                implicitHeight: Tokens.sizes.osd.sliderHeight

                FilledSlider {
                    anchors.fill: parent

                    icon: Icons.getVolumeIcon(value, Audio.muted)
                    value: Audio.volume
                    to: GlobalConfig.services.maxVolume
                    onMoved: Audio.setVolume(value)
                }
            }

            CustomMouseArea {
                function onWheel(event: WheelEvent) {
                    if (event.angleDelta.y > 0)
                        Audio.incrementSourceVolume();
                    else if (event.angleDelta.y < 0)
                        Audio.decrementSourceVolume();
                }

                visible: Config.rightBar.microphone
                implicitWidth: Tokens.sizes.osd.sliderWidth
                implicitHeight: Tokens.sizes.osd.sliderHeight

                FilledSlider {
                    anchors.fill: parent

                    icon: Icons.getMicVolumeIcon(value, Audio.sourceMuted)
                    value: Audio.sourceVolume
                    to: GlobalConfig.services.maxVolume
                    onMoved: Audio.setSourceVolume(value)
                }
            }
        }
    }
}
