import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Caelestia
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.services

// One shortcut: icon, what it does, and its keys. `bind` is a row from
// hyprbinds.py; `unbound` rows are global shortcuts nothing is bound to.
Item {
    id: root

    required property var bind
    property bool unbound
    property bool showCommand: GlobalConfig.keybinds.showCommands

    readonly property string appIcon: bind.app?.icon ? Quickshell.iconPath(bind.app.icon, true) : ""
    readonly property string subtitle: {
        if (unbound)
            return `hl.dsp.global("${bind.name}")`;
        if (bind.note)
            return showCommand && bind.detail ? `${bind.note} · ${bind.detail}` : bind.note;
        return showCommand ? bind.detail : "";
    }
    readonly property color tile: {
        const owner = unbound ? "shell" : bind.owner;
        if (owner === "shell")
            return Colours.palette.m3primaryContainer;
        if (owner === "app")
            return Colours.palette.m3tertiaryContainer;
        return Colours.palette.m3secondaryContainer;
    }
    readonly property color tileInk: {
        const owner = unbound ? "shell" : bind.owner;
        if (owner === "shell")
            return Colours.palette.m3onPrimaryContainer;
        if (owner === "app")
            return Colours.palette.m3onTertiaryContainer;
        return Colours.palette.m3onSecondaryContainer;
    }

    implicitHeight: Math.max(layout.implicitHeight, tileItem.implicitHeight) + Tokens.padding.small * 2
    opacity: bind.missing ? 0.55 : 1

    StateLayer {
        anchors.fill: parent
        radius: Tokens.rounding.medium
        disabled: !root.unbound
        onClicked: {
            Quickshell.clipboardText = `hl.bind("SUPER + …", hl.dsp.global("${root.bind.name}"))`;
            Toaster.toast(Tr.tr("Copied"), Tr.tr("A Lua bind for %1 is on the clipboard").arg(root.bind.title), "content_copy");
        }
    }

    RowLayout {
        id: layout

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Tokens.padding.small
        anchors.rightMargin: Tokens.padding.small
        spacing: Tokens.spacing.medium

        StyledRect {
            id: tileItem

            implicitWidth: Math.round(Tokens.font.icon.medium.pointSize * 2.2)
            implicitHeight: implicitWidth
            radius: Tokens.rounding.medium
            color: root.appIcon ? "transparent" : root.tile

            IconImage {
                anchors.fill: parent
                visible: !!root.appIcon
                asynchronous: true
                source: root.appIcon
                implicitSize: parent.width
            }

            MaterialIcon {
                anchors.centerIn: parent
                visible: !root.appIcon
                text: root.bind.icon
                color: root.tileInk
                fill: 1
                fontStyle: Tokens.font.icon.small
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall

                StyledText {
                    Layout.fillWidth: true
                    text: root.bind.title
                    font: Tokens.font.body.medium
                    elide: Text.ElideRight
                }

                FlagIcon {
                    shown: !root.unbound && root.bind.flags.locked
                    icon: "lock"
                }

                FlagIcon {
                    shown: !root.unbound && root.bind.flags.repeat
                    icon: "repeat"
                }

                StyledRect {
                    visible: !!root.bind.missing
                    implicitWidth: missingLabel.implicitWidth + Tokens.padding.small * 2
                    implicitHeight: missingLabel.implicitHeight + Tokens.padding.extraSmall
                    radius: Tokens.rounding.full
                    color: Colours.palette.m3errorContainer

                    StyledText {
                        id: missingLabel

                        anchors.centerIn: parent
                        text: Tr.tr("not installed")
                        color: Colours.palette.m3onErrorContainer
                        font: Tokens.font.label.small
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: text !== ""
                text: root.subtitle
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.small
                elide: Text.ElideRight
            }
        }

        // The main keys, then any alternatives bound to the same action
        Column {
            Layout.alignment: Qt.AlignVCenter
            visible: !root.unbound
            spacing: Tokens.spacing.extraSmall

            Repeater {
                model: root.unbound ? [] : [root.bind.caps ?? [], ...(root.bind.alts ?? [])]

                KeyCombo {
                    required property var modelData

                    anchors.right: parent?.right
                    caps: modelData
                    compact: true
                }
            }
        }

        StyledText {
            visible: root.unbound
            text: Tr.tr("Not bound")
            color: Colours.palette.m3outline
            font: Tokens.font.label.medium
        }
    }

    component FlagIcon: MaterialIcon {
        id: flag

        property bool shown
        property alias icon: flag.text

        visible: shown
        color: Colours.palette.m3outline
        fontStyle: Tokens.font.icon.builders.small.scale(0.85).build()
    }
}
