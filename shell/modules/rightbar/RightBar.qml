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
    // This display's brightness, where it can be set (each display's bar has its own)
    readonly property var brightness: Brightness.getMonitorForScreen(screen)
    readonly property bool showBrightness: Config.rightBar.brightness && !!brightness?.controllable
    // The action button under the pointer, for its tooltip
    property Item hoveredButton
    property var hoveredAction
    // The last one hovered: where the tooltip stays while the pointer moves
    // between buttons
    property Item tipButton

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
            spacing: 0

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
                        // The same size either way, so lighting one up doesn't move the rest
                        padding: Tokens.padding.small
                        // A recording shows stop; a Home Assistant entity that's on stays itself
                        icon: action.active && action.modelData.recorder ? "stop_circle" : action.modelData.icon
                        onClicked: action.modelData.run()
                        onHoveredChanged: {
                            if (hovered) {
                                root.hoveredButton = this;
                                root.tipButton = this;
                                root.hoveredAction = action.modelData;
                            } else if (root.hoveredButton === this) {
                                root.hoveredButton = null;
                            }
                        }
                    }

                    // How long the recording has run
                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: action.active && !!action.modelData.recorder
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

    // Brightness and volume, always there
    StyledRect {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Tokens.padding.large
        visible: root.showBrightness || Config.rightBar.volume || Config.rightBar.microphone

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
                    const step = GlobalConfig.services.brightnessIncrement;
                    if (event.angleDelta.y > 0)
                        root.brightness.setBrightness(root.brightness.brightness + step);
                    else if (event.angleDelta.y < 0)
                        root.brightness.setBrightness(root.brightness.brightness - step);
                }

                visible: root.showBrightness
                implicitWidth: Tokens.sizes.osd.sliderWidth
                implicitHeight: Tokens.sizes.osd.sliderHeight

                FilledSlider {
                    anchors.fill: parent

                    icon: `brightness_${Math.round(value * 6) + 1}`
                    value: root.brightness?.brightness ?? 0
                    onMoved: root.brightness?.setBrightness(value)
                }
            }

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

    // What the hovered button does, beside the bar: in the window around it,
    // as the bar clips what's outside it (and on its other side when the
    // layout is right to left)
    StyledRect {
        id: tooltip

        readonly property bool mirrored: root.LayoutMirroring.enabled
        readonly property bool shown: (root.hoveredButton !== null || grace.running) && showDelay.done
        readonly property point at: root.tipButton ? root.tipButton.mapToItem(parent, 0, root.tipButton.height / 2) : Qt.point(0, 0)

        parent: root.parent
        z: 10
        x: mirrored ? root.x + root.width + Tokens.spacing.medium : root.x - width - Tokens.spacing.medium
        y: at.y - height / 2
        implicitWidth: tipText.implicitWidth + Tokens.padding.large * 2
        implicitHeight: tipText.implicitHeight + Tokens.padding.small * 2
        radius: Tokens.rounding.full
        color: Colours.palette.m3inverseSurface
        opacity: shown ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            Anim {
                type: Anim.FastEffects
            }
        }

        Behavior on y {
            enabled: tooltip.opacity > 0

            Anim {
                type: Anim.FastSpatial
            }
        }

        Column {
            id: tipText

            anchors.centerIn: parent

            StyledText {
                text: root.hoveredAction?.name ?? ""
                color: Colours.palette.m3inverseOnSurface
                font: Tokens.font.label.large
            }

            StyledText {
                visible: text !== ""
                width: Math.min(implicitWidth, 320)
                text: root.hoveredAction?.description ?? ""
                color: Qt.alpha(Colours.palette.m3inverseOnSurface, 0.7)
                font: Tokens.font.label.small
                elide: Text.ElideRight
            }
        }

        // A moment's hover first: not on every pass of the pointer
        Timer {
            id: showDelay

            property bool done

            interval: 400
            running: root.hoveredButton !== null && !done
            onTriggered: done = true
        }

        // Off a button for a moment (on the way to the next one, say), it
        // stays up; longer, and the next hover waits again
        Timer {
            id: grace

            interval: 200
            onTriggered: if (root.hoveredButton === null)
                showDelay.done = false
        }

        Connections {
            function onHoveredButtonChanged(): void {
                if (root.hoveredButton === null)
                    grace.restart();
            }

            target: root
        }
    }
}
