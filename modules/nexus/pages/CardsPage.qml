pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.keybinds
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    // The binds that run the card shortcuts, from the Hyprland config
    readonly property var binds: Keybinds.binds.filter(b => /caelestia:card|cards (pair|flip|unpair)/.test(b.detail))

    title: Tr.tr("Window cards")

    Component.onCompleted: Keybinds.ensureLoaded()

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

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
                    color: Colours.palette.m3tertiaryContainer

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: "flip"
                        color: Colours.palette.m3onTertiaryContainer
                        fill: 1
                        fontStyle: Tokens.font.icon.large
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.extraSmall

                    StyledText {
                        Layout.fillWidth: true
                        text: Cards.cards.length === 1 ? Tr.tr("1 card") : Tr.tr("%1 cards").arg(Cards.cards.length)
                        font: Tokens.font.title.medium
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Tr.tr("Pair two windows into one card that flips over to show the other. Cards are Hyprland groups, so they keep their place in the layout.")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.small
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }

        SectionHeader {
            text: Tr.tr("Shortcuts")
        }

        Repeater {
            model: root.binds

            ConnectedRect {
                id: bindRect

                required property var modelData
                required property int index

                Layout.fillWidth: true
                first: index === 0
                last: index === root.binds.length - 1
                implicitHeight: bindRow.implicitHeight + Tokens.padding.small * 2

                BindRow {
                    id: bindRow

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Tokens.padding.medium
                    anchors.rightMargin: Tokens.padding.medium
                    bind: bindRect.modelData
                }
            }
        }

        InfoRow {
            visible: root.binds.length === 0
            first: true
            last: true
            label: Tr.tr("No keys are bound")
            value: "hl.dsp.global(\"caelestia:cardPair\" | \"cardFlip\" | \"cardUnpair\")"
        }

        SectionHeader {
            text: Tr.tr("Flip")
        }

        ToggleRow {
            first: true
            text: Tr.trCtx("Enabled", "toggle label")
            checked: GlobalConfig.cards.enabled
            onToggled: GlobalConfig.cards.enabled = checked
        }

        StepperRow {
            label: Tr.tr("Duration")
            subtext: Tr.tr("How long a flip takes, in milliseconds")
            value: GlobalConfig.cards.duration
            from: 150
            to: 2000
            stepSize: 50
            onMoved: v => GlobalConfig.cards.duration = v
        }

        StepperRow {
            label: Tr.tr("Perspective")
            subtext: Tr.tr("Camera distance in card widths; lower looks more dramatic")
            value: GlobalConfig.cards.perspective
            from: 0.8
            to: 8
            stepSize: 0.2
            onMoved: v => GlobalConfig.cards.perspective = Math.round(v * 10) / 10
        }

        StepperRow {
            label: Tr.tr("Lift")
            subtext: Tr.tr("How much the card shrinks mid-flip, as if picked up")
            value: GlobalConfig.cards.lift
            from: 0
            to: 0.3
            stepSize: 0.02
            onMoved: v => GlobalConfig.cards.lift = Math.round(v * 100) / 100
        }

        ToggleRow {
            last: true
            text: Tr.tr("Turn to the left")
            subtext: Tr.tr("Off turns the card to the right")
            checked: GlobalConfig.cards.direction === "left"
            onToggled: GlobalConfig.cards.direction = checked ? "left" : "right"
        }
    }
}
