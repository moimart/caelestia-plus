pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services

// The camera's state, from the bar's camera icon: who's using it, and the features
ColumnLayout {
    spacing: Tokens.spacing.small

    StyledText {
        text: !GlobalConfig.camera.enabled ? Tr.tr("Camera off") : Camera.inUse ? Tr.tr("Camera in use") : Tr.tr("Camera idle")
        font: Tokens.font.title.small
    }

    StyledText {
        visible: GlobalConfig.camera.enabled && !Camera.inUse
        text: Tr.tr("No app is using the camera")
        color: Colours.palette.m3onSurfaceVariant
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

    RowLayout {
        visible: GlobalConfig.camera.enabled && GlobalConfig.camera.gestures.enabled
        spacing: Tokens.spacing.small

        MaterialIcon {
            text: "back_hand"
            color: Colours.palette.m3onSurfaceVariant
            fontStyle: Tokens.font.icon.small
        }

        StyledText {
            text: Camera.gesturesState === "paused" ? Tr.tr("Gestures paused for another app") : Tr.tr("Gestures on")
            color: Colours.palette.m3onSurfaceVariant
        }
    }

    TextButton {
        Layout.topMargin: Tokens.spacing.small
        text: Tr.tr("Camera panel")
        type: TextButton.Tonal
        onClicked: Camera.openPanelRequested()
    }
}
