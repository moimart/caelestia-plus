pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.services

// A Home Assistant camera's picture, fetched again every `interval` seconds,
// each new frame swapped in once it has loaded (so it never blanks).
Item {
    id: root

    property string instance
    property string entityId
    property string name
    property int interval: 5
    property real radius: Tokens.rounding.large

    readonly property string consumer: `camera-${Math.random().toString(36).slice(2)}`
    readonly property string base: HomeAssistant.pictureUrl(instance, entityId)
    property int tick

    onEntityIdChanged: HomeAssistant.watch(consumer, instance, [entityId])
    Component.onCompleted: HomeAssistant.watch(consumer, instance, [entityId])
    Component.onDestruction: HomeAssistant.unwatch(consumer, instance)

    Timer {
        running: root.visible && root.base !== ""
        repeat: true
        interval: Math.max(1, root.interval) * 1000
        onTriggered: root.tick++
    }

    ClipRect {
        anchors.fill: parent
        radius: root.radius
        color: Colours.tPalette.m3surfaceContainer

        // Loads the next frame out of sight
        Image {
            id: next

            visible: false
            asynchronous: true
            cache: false
            source: root.base ? `${root.base}${root.base.includes("?") ? "&" : "?"}_=${root.tick}` : ""
            sourceSize: Qt.size(root.width * 2, root.height * 2)
            onStatusChanged: {
                if (status === Image.Ready)
                    shown.source = source;
            }
        }

        Image {
            id: shown

            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            cache: false
            asynchronous: true
            sourceSize: next.sourceSize
        }

        MaterialIcon {
            anchors.centerIn: parent
            visible: shown.status !== Image.Ready
            text: "videocam"
            color: Colours.palette.m3onSurfaceVariant
            fontStyle: Tokens.font.icon.large
        }

        StyledRect {
            visible: !!root.name
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.margins: Tokens.padding.small
            implicitWidth: label.implicitWidth + Tokens.padding.medium * 2
            implicitHeight: label.implicitHeight + Tokens.padding.small * 2
            radius: Tokens.rounding.full
            color: Qt.alpha(Colours.palette.m3scrim, 0.55)

            StyledText {
                id: label

                anchors.centerIn: parent
                text: root.name
                color: "white"
                font: Tokens.font.label.medium
            }
        }
    }
}
