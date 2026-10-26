pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.components.keybinds
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    title: Tr.tr("Keyboard shortcuts")

    Component.onCompleted: Keybinds.ensureLoaded()

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // Hero: what the panel is and how to open it
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
                    color: Colours.palette.m3primaryContainer

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: "keyboard"
                        color: Colours.palette.m3onPrimaryContainer
                        fill: 1
                        fontStyle: Tokens.font.icon.large
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.extraSmall

                    StyledText {
                        Layout.fillWidth: true
                        text: Keybinds.loaded ? Tr.tr("%1 shortcuts").arg(Keybinds.visibleBinds.length) : Tr.tr("Reading your Hyprland config…")
                        font: Tokens.font.title.medium
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Keybinds.error || Tr.tr("Read from %1 and the files it loads, so the list follows your config").arg(Keybinds.configFile || "hyprland.lua")
                        color: Keybinds.error ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.small
                        wrapMode: Text.WordWrap
                    }

                    RowLayout {
                        Layout.topMargin: Tokens.spacing.small
                        spacing: Tokens.spacing.small

                        StyledText {
                            text: Keybinds.panelBind ? Tr.tr("Open with") : Tr.tr("No key opens the panel yet. Bind hl.dsp.global(\"caelestia:keybinds\")")
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.label.medium
                        }

                        KeyCombo {
                            visible: !!Keybinds.panelBind
                            caps: Keybinds.panelBind?.caps ?? []
                            compact: true
                        }
                    }
                }

                IconTextButton {
                    icon: "open_in_full"
                    text: Tr.tr("Open")
                    onClicked: Keybinds.panelOpen = true
                }
            }
        }

        SectionHeader {
            text: Tr.tr("Panel")
        }

        ToggleRow {
            first: true
            text: Tr.trCtx("Enabled", "toggle label")
            checked: GlobalConfig.keybinds.enabled
            onToggled: GlobalConfig.keybinds.enabled = checked
        }

        ToggleRow {
            text: Tr.tr("Show commands")
            subtext: Tr.tr("The command or dispatcher under each shortcut")
            checked: GlobalConfig.keybinds.showCommands
            onToggled: GlobalConfig.keybinds.showCommands = checked
        }

        ToggleRow {
            text: Tr.tr("Show unbound shell actions")
            subtext: Tr.tr("Shell shortcuts no key is bound to yet; click one to copy a bind for it")
            checked: GlobalConfig.keybinds.showUnbound
            onToggled: GlobalConfig.keybinds.showUnbound = checked
        }

        ToggleRow {
            text: Tr.tr("Show internal binds")
            subtext: Tr.tr("Pass-through binds the shell uses itself, like Caps Lock tracking")
            checked: GlobalConfig.keybinds.showInternal
            onToggled: GlobalConfig.keybinds.showInternal = checked
        }

        TextFieldRow {
            last: true
            label: Tr.tr("Hyprland config")
            subtext: Tr.tr("Leave empty to use ~/.config/hypr/hyprland.lua (or .conf)")
            value: GlobalConfig.keybinds.configPath
            placeholderText: Tr.tr("Automatic")
            onEditingFinished: value => GlobalConfig.keybinds.configPath = value.trim()
        }

        // Every shortcut, grouped like the config
        Repeater {
            model: Keybinds.categories

            ColumnLayout {
                id: category

                required property var modelData

                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall / 2

                SectionHeader {
                    text: category.modelData.name
                }

                Repeater {
                    model: category.modelData.binds

                    ConnectedRect {
                        id: rowRect

                        required property var modelData
                        required property int index

                        Layout.fillWidth: true
                        first: index === 0
                        last: index === category.modelData.binds.length - 1
                        implicitHeight: bindRow.implicitHeight + Tokens.padding.small * 2

                        BindRow {
                            id: bindRow

                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: Tokens.padding.medium
                            anchors.rightMargin: Tokens.padding.medium
                            bind: rowRect.modelData
                        }
                    }
                }
            }
        }
    }
}
