pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.components.keybinds
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property var editBind: Keybinds.binds.find(b => /caelestia:widgets|widgets (edit|toggle)/.test(b.detail)) ?? null

    title: Tr.tr("Plugins")

    Component.onCompleted: {
        Widgets.rescan();
        Keybinds.ensureLoaded();
    }

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
                    color: Colours.palette.m3secondaryContainer

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: "widgets"
                        color: Colours.palette.m3onSecondaryContainer
                        fill: 1
                        fontStyle: Tokens.font.icon.large
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.extraSmall

                    StyledText {
                        Layout.fillWidth: true
                        text: Tr.tr("Desktop widgets")
                        font: Tokens.font.title.medium
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Tr.tr("%1 placed · %2 plugins installed").arg(Widgets.instances.length).arg(Widgets.plugins.length)
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.small
                    }

                    RowLayout {
                        Layout.topMargin: Tokens.spacing.small
                        visible: !!root.editBind
                        spacing: Tokens.spacing.small

                        StyledText {
                            text: Tr.tr("Place and resize with")
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.label.medium
                        }

                        KeyCombo {
                            caps: root.editBind?.caps ?? []
                            compact: true
                        }
                    }
                }

                IconTextButton {
                    icon: "open_with"
                    text: Tr.tr("Edit")
                    onClicked: {
                        Widgets.rescan();
                        Widgets.editing = true;
                    }
                }
            }
        }

        SectionHeader {
            text: Tr.tr("Widgets")
        }

        ToggleRow {
            first: true
            text: Tr.trCtx("Enabled", "toggle label")
            subtext: Tr.tr("Show desktop widgets")
            checked: GlobalConfig.widgets.enabled
            onToggled: GlobalConfig.widgets.enabled = checked
        }

        StepperRow {
            last: true
            label: Tr.tr("Grid")
            subtext: Tr.tr("Snap to this many pixels while placing (0 for none)")
            value: GlobalConfig.widgets.gridSize
            from: 0
            to: 64
            stepSize: 4
            onMoved: v => GlobalConfig.widgets.gridSize = v
        }

        SectionHeader {
            text: Tr.tr("Installed plugins")
        }

        Repeater {
            model: Widgets.plugins

            InfoRow {
                required property var modelData
                required property int index

                first: index === 0
                last: index === Widgets.plugins.length - 1
                icon: modelData.icon
                label: modelData.name
                subtext: [modelData.description, modelData.builtin ? Tr.tr("built in") : Paths.shortenHome(modelData.dir)].filter(s => s).join(" · ")
                value: {
                    const n = Widgets.instances.filter(i => i.type === modelData.id).length;
                    return n === 0 ? (modelData.version ? `v${modelData.version}` : "") : Tr.tr("%1 placed").arg(n);
                }
            }
        }

        SectionHeader {
            text: Tr.tr("Your plugins")
        }

        InfoRow {
            first: true
            icon: "folder"
            label: Tr.tr("Plugin folder")
            subtext: Tr.tr("One folder per widget, holding widget.json and its QML file")
            value: Paths.shortenHome(Widgets.userDir)
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.small
            spacing: Tokens.spacing.small

            TextButton {
                text: Tr.tr("Open folder")
                type: TextButton.Tonal
                onClicked: Quickshell.execDetached(["sh", "-c", `mkdir -p "$1" && xdg-open "$1"`, "sh", Widgets.userDir])
            }

            TextButton {
                text: Tr.tr("Rescan")
                type: TextButton.Tonal
                onClicked: Widgets.rescan()
            }

            Item {
                Layout.fillWidth: true
            }

            StyledText {
                text: Tr.tr("How to write one: PLUGINS.md in the shell's repo")
                color: Colours.palette.m3outline
                font: Tokens.font.label.medium
            }
        }
    }
}
