import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.services

// A camera snapshot, refreshed on every poll. The next frame loads off-screen
// and replaces the shown one only once it's ready, so the image never blanks.
StyledClippingRect {
    id: root

    required property var card
    required property var ha

    readonly property var entity: ha.state(card.entity)
    readonly property string picture: entity?.attributes?.entity_picture ?? ""

    implicitHeight: width * (card.aspect ?? 9 / 16)
    radius: Tokens.rounding.extraLarge
    color: Colours.tPalette.m3surfaceContainer

    Image {
        id: next

        visible: false
        asynchronous: true
        source: root.picture ? `${root.ha.url}${root.picture}&_=${root.ha.tick}` : ""
        sourceSize: shown.sourceSize
        onStatusChanged: if (status === Image.Ready) shown.source = source
    }

    Image {
        id: shown

        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        sourceSize: {
            const dpr = (QsWindow.window as QsWindow)?.devicePixelRatio ?? 1;
            return Qt.size(width * dpr, height * dpr);
        }
    }

    StyledRect {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: Tokens.padding.large

        implicitWidth: label.implicitWidth + Tokens.padding.medium * 2
        implicitHeight: label.implicitHeight + Tokens.padding.small * 2
        radius: Tokens.rounding.full
        color: Qt.alpha(Colours.palette.m3surface, 0.7)

        StyledText {
            id: label

            anchors.centerIn: parent
            text: root.card.name ?? root.entity?.attributes?.friendly_name ?? root.card.entity
            font: Tokens.font.body.small
        }
    }
}
