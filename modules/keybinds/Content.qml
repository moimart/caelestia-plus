pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.containers
import qs.components.controls
import qs.components.effects
import qs.services
import qs.modules.nexus

// The shortcuts cheatsheet: every active Hyprland/shell bind, grouped the way
// the config groups them, searchable and filterable by who handles it
Item {
    id: root

    required property bool shown
    property string owner // "", "shell", "hyprland" or "app"

    readonly property var shownCategories: Keybinds.filter(search.text, owner)
    readonly property var shownUnbound: {
        if (!GlobalConfig.keybinds.showUnbound || (owner && owner !== "shell"))
            return [];
        const words = search.text.toLowerCase().split(/\s+/).filter(w => w);
        return Keybinds.unbound.filter(u => words.every(w => `${u.title} ${u.name}`.toLowerCase().includes(w)));
    }
    readonly property int shownCount: shownCategories.reduce((n, c) => n + c.binds.length, 0)

    // Masonry: categories go to whichever column is shortest so far
    readonly property int columnCount: Math.max(1, Math.floor((cards.width + Tokens.spacing.medium) / (Tokens.sizes.keybinds.columnWidth + Tokens.spacing.medium)))
    readonly property var columns: {
        const cols = Array.from({
            length: columnCount
        }, () => ({
                    height: 0,
                    items: []
                }));
        const all = shownCategories.map(c => Object.assign({
                unbound: false
            }, c));
        if (shownUnbound.length > 0)
            all.push({
                name: Tr.tr("Shell actions without a key"),
                icon: "keyboard_off",
                binds: shownUnbound,
                unbound: true
            });
        for (const c of all) {
            const col = cols.reduce((a, b) => b.height < a.height ? b : a);
            col.items.push(c);
            col.height += c.binds.reduce((n, b) => n + 1 + (b.alts?.length ?? 0) * 0.6, 0) + 2;
        }
        return cols.map(c => c.items);
    }

    signal closeRequested
    signal hidden

    function focusSearch(): void {
        search.forceActiveFocus();
    }

    onShownChanged: {
        if (shown) {
            search.text = "";
            owner = "";
            Keybinds.ensureLoaded();
            focusSearch();
        }
    }

    // Dim the desktop; clicking outside the sheet closes it
    StyledRect {
        anchors.fill: parent
        color: Qt.alpha(Colours.palette.m3scrim, 0.45)
        opacity: root.shown ? 1 : 0

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.closeRequested()
        }
    }

    Elevation {
        anchors.fill: sheet
        radius: sheet.radius
        opacity: sheet.opacity
        scale: sheet.scale
        level: 3
    }

    StyledRect {
        id: sheet

        anchors.centerIn: parent
        width: Math.min(parent.width - Tokens.padding.extraExtraLarge * 2, Tokens.sizes.keybinds.maxWidth)
        height: Math.min(parent.height - Tokens.padding.extraExtraLarge * 2, header.implicitHeight + body.contentHeight + footer.implicitHeight + Tokens.padding.extraLarge * 2 + Tokens.spacing.large * 2)
        radius: Tokens.rounding.extraLarge
        color: Colours.tPalette.m3surfaceContainerLow

        opacity: root.shown ? 1 : 0
        scale: root.shown ? 1 : 0.94

        onOpacityChanged: {
            if (opacity === 0 && !root.shown)
                root.hidden();
        }

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }

        Behavior on scale {
            Anim {
                type: Anim.DefaultSpatial
            }
        }

        Behavior on height {
            Anim {
                type: Anim.DefaultSpatial
            }
        }

        // Swallow clicks so they don't reach the scrim
        MouseArea {
            anchors.fill: parent
        }

        RowLayout {
            id: header

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.padding.extraLarge
            spacing: Tokens.spacing.large

            StyledRect {
                implicitWidth: Math.round(Tokens.font.icon.large.pointSize * 2.4)
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
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: Tr.tr("Keyboard shortcuts")
                    font: Tokens.font.headline.medium
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: {
                        if (Keybinds.error)
                            return Keybinds.error;
                        if (!Keybinds.loaded)
                            return Tr.tr("Reading your Hyprland config…");
                        return Tr.tr("%1 shortcuts from %2").arg(Keybinds.visibleBinds.length).arg(Keybinds.configFile);
                    }
                    color: Keybinds.error ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                    elide: Text.ElideMiddle
                }
            }

            Row {
                spacing: Tokens.spacing.extraSmall

                Repeater {
                    model: [
                        {
                            owner: "",
                            label: Tr.trCtx("All", "keybind filter"),
                            icon: "select_all"
                        },
                        {
                            owner: "shell",
                            label: Tr.trCtx("Shell", "keybind filter"),
                            icon: "auto_awesome"
                        },
                        {
                            owner: "hyprland",
                            label: "Hyprland",
                            icon: "web_asset"
                        },
                        {
                            owner: "app",
                            label: Tr.trCtx("Apps", "keybind filter"),
                            icon: "apps"
                        }
                    ]

                    IconTextButton {
                        required property var modelData

                        icon: modelData.icon
                        text: modelData.label
                        type: TextButton.Tonal
                        isToggle: true
                        checked: root.owner === modelData.owner
                        onClicked: {
                            root.owner = modelData.owner;
                            root.focusSearch();
                        }
                    }
                }
            }

            SearchBar {
                id: search

                Layout.preferredWidth: Tokens.sizes.keybinds.searchWidth
                placeholderText: Tr.tr("Search shortcuts")

                Keys.onEscapePressed: {
                    if (text)
                        text = "";
                    else
                        root.closeRequested();
                }
            }

            IconButton {
                icon: "refresh"
                type: IconButton.Text
                disabled: Keybinds.loading
                onClicked: Keybinds.reload()
            }

            IconButton {
                icon: "settings"
                type: IconButton.Text
                onClicked: {
                    root.closeRequested();
                    WindowFactory.create(null, {
                        initialPage: PageRegistry.pages.findIndex(p => p.icon === "keyboard")
                    });
                }
            }

            IconButton {
                icon: "close"
                type: IconButton.Text
                onClicked: root.closeRequested()
            }
        }

        StyledFlickable {
            id: body

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: header.bottom
            anchors.bottom: footer.top
            anchors.leftMargin: Tokens.padding.extraLarge
            anchors.rightMargin: Tokens.padding.extraLarge
            anchors.topMargin: Tokens.spacing.large
            anchors.bottomMargin: Tokens.spacing.large

            clip: true
            contentWidth: width
            contentHeight: Math.max(cards.implicitHeight, empty.visible ? empty.implicitHeight : 0)

            StyledScrollBar.vertical: StyledScrollBar {
                flickable: body
            }

            RowLayout {
                id: cards

                width: body.width
                spacing: Tokens.spacing.medium

                Repeater {
                    model: root.columns

                    ColumnLayout {
                        id: col

                        required property var modelData

                        Layout.alignment: Qt.AlignTop
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        spacing: Tokens.spacing.medium

                        Repeater {
                            model: col.modelData

                            CategoryCard {
                                required property var modelData

                                Layout.fillWidth: true
                                name: modelData.name
                                icon: modelData.icon
                                binds: modelData.binds
                                unbound: modelData.unbound
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                id: empty

                anchors.horizontalCenter: parent.horizontalCenter
                y: Tokens.padding.extraExtraLarge
                visible: Keybinds.loaded && root.shownCount === 0 && root.shownUnbound.length === 0
                spacing: Tokens.spacing.small

                MaterialIcon {
                    Layout.alignment: Qt.AlignHCenter
                    text: "search_off"
                    color: Colours.palette.m3outline
                    fontStyle: Tokens.font.icon.extraLarge
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: search.text ? Tr.tr("No shortcuts match \"%1\"").arg(search.text) : Tr.tr("No shortcuts found")
                    color: Colours.palette.m3outline
                    font: Tokens.font.title.medium
                }
            }
        }

        RowLayout {
            id: footer

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: Tokens.padding.extraLarge
            anchors.topMargin: 0
            spacing: Tokens.spacing.large

            Legend {
                colour: Colours.palette.m3primaryContainer
                text: Tr.tr("Shell")
            }

            Legend {
                colour: Colours.palette.m3secondaryContainer
                text: "Hyprland"
            }

            Legend {
                colour: Colours.palette.m3tertiaryContainer
                text: Tr.tr("Apps")
            }

            LegendIcon {
                icon: "lock"
                text: Tr.tr("Works on the lock screen")
            }

            LegendIcon {
                icon: "repeat"
                text: Tr.tr("Repeats when held")
            }

            Item {
                Layout.fillWidth: true
            }

            StyledText {
                text: Keybinds.live ? Tr.tr("Updates when Hyprland reloads · Esc to close") : Tr.tr("Hyprland isn't running; showing the config as written")
                color: Colours.palette.m3outline
                font: Tokens.font.label.small
            }
        }
    }

    component Legend: Row {
        property color colour
        property alias text: label.text

        spacing: Tokens.spacing.extraSmall

        StyledRect {
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: Tokens.font.label.small.pointSize
            implicitHeight: implicitWidth
            radius: Tokens.rounding.extraSmall
            color: parent.colour
        }

        StyledText {
            id: label

            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.small
        }
    }

    component LegendIcon: Row {
        property alias icon: iconLabel.text
        property alias text: label.text

        spacing: Tokens.spacing.extraSmall

        MaterialIcon {
            id: iconLabel

            anchors.verticalCenter: parent.verticalCenter
            color: Colours.palette.m3outline
            fontStyle: Tokens.font.icon.builders.small.scale(0.85).build()
        }

        StyledText {
            id: label

            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.small
        }
    }
}
