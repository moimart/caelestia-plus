pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services

// Who has the camera, from the bar's camera indicator
ColumnLayout {
    spacing: Tokens.spacing.small

    StyledText {
        text: Tr.tr("Camera in use")
        font: Tokens.font.title.small
    }

    Repeater {
        model: Camera.others

        RowLayout {
            id: user

            required property var modelData

            spacing: Tokens.spacing.small

            MaterialIcon {
                text: user.modelData.shell ? "auto_awesome" : user.modelData.via === "pipewire" ? "share" : "videocam"
                color: Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.small
            }

            StyledText {
                text: user.modelData.shell ? Tr.tr("Caelestia (mirror)") : user.modelData.name
            }

            StyledText {
                text: user.modelData.via === "pipewire" ? Tr.tr("shared") : Tr.tr("exclusive")
                color: Colours.palette.m3outline
                font: Tokens.font.label.small
            }
        }
    }

    TextButton {
        Layout.topMargin: Tokens.spacing.small
        text: Tr.tr("Camera panel")
        type: TextButton.Tonal
        onClicked: Camera.openPanelRequested()
    }
}
