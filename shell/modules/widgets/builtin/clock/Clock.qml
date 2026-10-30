pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.services

// The desktop clock: hours and minutes, then the month, day and weekday. It
// grows with the widget (drawn at its size, not stretched, so it stays sharp).
// Settings: invertColors, shadow, background, backgroundOpacity (%).
Item {
    id: root

    property var settings: ({})

    readonly property bool invertColors: settings.invertColors ?? false
    readonly property bool useLightSet: Colours.light ? !invertColors : invertColors
    readonly property color safePrimary: useLightSet ? Colours.palette.m3primaryContainer : Colours.palette.m3primary
    readonly property color safeSecondary: useLightSet ? Colours.palette.m3secondaryContainer : Colours.palette.m3secondary
    readonly property color safeTertiary: useLightSet ? Colours.palette.m3tertiaryContainer : Colours.palette.m3tertiary

    // How big it is at scale 1, to fit the widget's box
    readonly property real fitScale: Math.max(0.1, Math.min(width / Math.max(1, measure.implicitWidth), height / Math.max(1, measure.implicitHeight)))

    Face {
        id: measure

        visible: false
        clockScale: 1
    }

    Face {
        anchors.centerIn: parent
        clockScale: root.fitScale

        layer.enabled: root.settings.shadow ?? true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Colours.palette.m3shadow
            shadowOpacity: 0.85
            shadowBlur: 0.4
        }
    }

    component Face: Item {
        id: face

        property real clockScale: 1

        implicitWidth: layout.implicitWidth + Tokens.padding.large * 4 * clockScale
        implicitHeight: layout.implicitHeight + Tokens.padding.extraLargeIncreased * clockScale
        width: implicitWidth
        height: implicitHeight

        StyledRect {
            anchors.fill: parent
            visible: root.settings.background ?? false
            radius: Tokens.rounding.extraLarge * face.clockScale
            opacity: (root.settings.backgroundOpacity ?? 70) / 100
            color: Colours.palette.m3surface
        }

        RowLayout {
            id: layout

            anchors.centerIn: parent
            spacing: Tokens.spacing.large * face.clockScale

            RowLayout {
                spacing: Tokens.spacing.small * face.clockScale

                StyledText {
                    text: Time.hourStr
                    font: Tokens.font.clock.size(Tokens.font.headline.medium.pointSize * 3 * face.clockScale).weight(Font.Bold).build()
                    color: root.safePrimary
                }

                StyledText {
                    Layout.topMargin: -Tokens.padding.large * 1.5 * face.clockScale
                    text: ":"
                    font: Tokens.font.clock.size(Tokens.font.headline.medium.pointSize * 3 * face.clockScale).build()
                    color: root.safeTertiary
                    opacity: 0.8
                }

                StyledText {
                    text: Time.minuteStr
                    font: Tokens.font.clock.size(Tokens.font.headline.medium.pointSize * 3 * face.clockScale).weight(Font.Bold).build()
                    color: root.safeSecondary
                }

                StyledText {
                    Layout.alignment: Qt.AlignTop
                    Layout.topMargin: Tokens.padding.large * 1.4 * face.clockScale
                    visible: Units.twelveHourClock
                    text: Time.amPmStr
                    font: Tokens.font.clock.size(Tokens.font.title.medium.pointSize * face.clockScale).build()
                    color: root.safeSecondary
                }
            }

            StyledRect {
                Layout.fillHeight: true
                Layout.preferredWidth: 4 * face.clockScale
                Layout.topMargin: Tokens.spacing.large * face.clockScale
                Layout.bottomMargin: Tokens.spacing.large * face.clockScale
                radius: Tokens.rounding.full
                color: root.safePrimary
                opacity: 0.8
            }

            ColumnLayout {
                spacing: 0

                StyledText {
                    text: Time.format("MMMM").toUpperCase()
                    font: Tokens.font.clock.size(Tokens.font.title.medium.pointSize * face.clockScale).letterSpacing(4 * face.clockScale).weight(Font.Bold).build()
                    color: root.safeSecondary
                }

                StyledText {
                    text: Time.format("dd")
                    font: Tokens.font.clock.size(Tokens.font.headline.medium.pointSize * face.clockScale).letterSpacing(2 * face.clockScale).weight(Font.Medium).build()
                    color: root.safePrimary
                }

                StyledText {
                    text: Time.format("dddd")
                    font: Tokens.font.clock.size(Tokens.font.body.large.pointSize * face.clockScale).letterSpacing(2 * face.clockScale).build()
                    color: root.safeSecondary
                }
            }
        }
    }
}
