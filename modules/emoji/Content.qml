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

// The emoji picker, like macOS's: search as you type, arrows and Enter to
// pick, the categories along the bottom, and skin tones on right-click (or Tab)
Item {
    id: root

    required property bool shown
    // Where to open, in this item's coordinates (the pointer), or null for the centre
    property var anchorPoint: null

    readonly property int columns: 9
    readonly property int cell: 40
    readonly property string query: search.text.trim()

    readonly property var sections: {
        if (query)
            return [
                {
                    name: Tr.tr("Results"),
                    icon: "search",
                    emojis: Emoji.search(query)
                }
            ];
        const all = Emoji.groups.slice();
        if (Emoji.recentEmojis.length > 0)
            all.unshift({
                name: Tr.tr("Frequently used"),
                icon: "schedule",
                emojis: Emoji.recentEmojis
            });
        return all;
    }

    // The grid as list rows: a header per section, then rows of emoji.
    // `flat` is every cell in order, for the keyboard selection.
    readonly property var layout: {
        const rows = [];
        const flat = [];
        const sectionRows = [];
        for (const s of sections) {
            sectionRows.push(rows.length);
            rows.push({
                header: s.name,
                items: [],
                first: flat.length
            });
            for (let i = 0; i < s.emojis.length; i += columns) {
                const items = s.emojis.slice(i, i + columns);
                rows.push({
                    header: "",
                    items: items,
                    first: flat.length
                });
                for (const e of items)
                    flat.push({
                        e: e,
                        row: rows.length - 1
                    });
            }
        }
        return {
            rows: rows,
            flat: flat,
            sectionRows: sectionRows
        };
    }

    property int current: 0
    readonly property var currentEmoji: layout.flat[current]?.e ?? null
    // The skin tone chooser, open over this flat index (-1: closed)
    property int toneFor: -1
    property int toneIndex: 0

    signal closeRequested
    signal hidden

    function pick(e: var): void {
        if (e)
            Emoji.insert(e);
    }

    function move(dx: int, dy: int): void {
        const flat = layout.flat;
        if (flat.length === 0)
            return;
        if (dy === 0) {
            current = Math.max(0, Math.min(flat.length - 1, current + dx));
        } else {
            const rows = layout.rows;
            const r = flat[current].row;
            const col = current - rows[r].first;
            let t = r + dy;
            while (t >= 0 && t < rows.length && rows[t].items.length === 0)
                t += dy;
            if (t < 0 || t >= rows.length)
                return;
            current = rows[t].first + Math.min(col, rows[t].items.length - 1);
        }
        list.positionViewAtIndex(flat[current].row, ListView.Contain);
    }

    function openTones(index: int): void {
        const e = layout.flat[index]?.e;
        if (!e?.v)
            return;
        current = index;
        toneIndex = Emoji.tones[e.e] ?? Emoji.lastTone;
        toneFor = index;
    }

    function jumpTo(section: int): void {
        list.positionViewAtIndex(layout.sectionRows[section], ListView.Beginning);
        current = layout.rows[layout.sectionRows[section]].first;
    }

    onShownChanged: {
        if (shown) {
            search.text = "";
            toneFor = -1;
            current = 0;
            Emoji.ensureLoaded();
            list.positionViewAtBeginning();
            search.forceActiveFocus();
        }
    }
    onQueryChanged: {
        current = 0;
        toneFor = -1;
        list.positionViewAtBeginning();
    }

    // Clicking anywhere else closes it
    MouseArea {
        anchors.fill: parent
        onClicked: root.closeRequested()
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

        readonly property real margin: Tokens.padding.large

        width: root.columns * root.cell + Tokens.padding.large * 2
        height: 440
        x: {
            const p = root.anchorPoint;
            const want = p ? p.x - width / 2 : (root.width - width) / 2;
            return Math.max(margin, Math.min(root.width - width - margin, want));
        }
        y: {
            const p = root.anchorPoint;
            if (!p)
                return (root.height - height) / 2;
            // Below the pointer if it fits, else above
            const below = p.y + 24;
            return below + height + margin <= root.height ? below : Math.max(margin, p.y - 24 - height);
        }
        radius: Tokens.rounding.extraLarge
        color: Colours.tPalette.m3surfaceContainerLow
        transformOrigin: Item.Top

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

        // Swallow clicks so they don't close the picker
        MouseArea {
            anchors.fill: parent
            onClicked: root.toneFor = -1
        }

        SearchBar {
            id: search

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.padding.large
            placeholderText: Tr.tr("Search emoji")

            Keys.onPressed: event => {
                const tones = root.toneFor >= 0;
                switch (event.key) {
                case Qt.Key_Escape:
                    if (tones)
                        root.toneFor = -1;
                    else if (text)
                        text = "";
                    else
                        root.closeRequested();
                    break;
                case Qt.Key_Left:
                case Qt.Key_Right:
                    if (tones)
                        root.toneIndex = (root.toneIndex + (event.key === Qt.Key_Right ? 1 : 5)) % 6;
                    else if (!text || event.modifiers & Qt.ControlModifier)
                        root.move(event.key === Qt.Key_Right ? 1 : -1, 0);
                    else
                        return;
                    break;
                case Qt.Key_Up:
                case Qt.Key_Down:
                    if (!tones)
                        root.move(0, event.key === Qt.Key_Down ? 1 : -1);
                    break;
                case Qt.Key_Tab:
                    if (tones)
                        root.toneFor = -1;
                    else
                        root.openTones(root.current);
                    break;
                case Qt.Key_Return:
                case Qt.Key_Enter:
                    if (tones) {
                        Emoji.setTone(root.currentEmoji, root.toneIndex);
                        root.toneFor = -1;
                    }
                    root.pick(root.currentEmoji);
                    break;
                default:
                    return;
                }
                event.accepted = true;
            }
        }

        StyledListView {
            id: list

            readonly property int topRow: indexAt(0, contentY + 1)
            readonly property int activeSection: {
                const rows = root.layout.sectionRows;
                let s = 0;
                for (let i = 0; i < rows.length; i++)
                    if (rows[i] <= topRow)
                        s = i;
                return s;
            }

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: search.bottom
            anchors.bottom: preview.top
            anchors.leftMargin: Tokens.padding.large
            anchors.rightMargin: Tokens.padding.large
            anchors.topMargin: Tokens.spacing.medium

            clip: true
            model: root.layout.rows
            boundsBehavior: Flickable.StopAtBounds

            delegate: Item {
                id: row

                required property var modelData
                required property int index

                width: list.width
                height: modelData.header ? 28 : root.cell

                StyledText {
                    visible: !!row.modelData.header
                    anchors.left: parent.left
                    anchors.leftMargin: Tokens.spacing.small
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Tokens.spacing.extraSmall
                    text: row.modelData.header
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.medium
                }

                Row {
                    Repeater {
                        model: row.modelData.items

                        Item {
                            id: cellItem

                            required property var modelData
                            required property int index
                            readonly property int flatIndex: row.modelData.first + index
                            readonly property bool selected: root.current === flatIndex

                            width: root.cell
                            height: root.cell

                            StyledRect {
                                anchors.fill: parent
                                anchors.margins: 2
                                radius: Tokens.rounding.medium
                                color: cellItem.selected ? Colours.palette.m3secondaryContainer : "transparent"
                            }

                            Text {
                                anchors.centerIn: parent
                                text: Emoji.toned(cellItem.modelData)
                                font.family: "Noto Color Emoji"
                                font.pixelSize: 26
                                renderType: Text.CurveRendering
                            }

                            // A dot under emoji that come in skin tones
                            StyledRect {
                                visible: !!cellItem.modelData.v
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.margins: 4
                                implicitWidth: 4
                                implicitHeight: 4
                                radius: 2
                                color: Colours.palette.m3outline
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                cursorShape: Qt.PointingHandCursor
                                onEntered: {
                                    if (root.toneFor < 0)
                                        root.current = cellItem.flatIndex;
                                }
                                onPressAndHold: root.openTones(cellItem.flatIndex)
                                onClicked: event => {
                                    if (event.button === Qt.RightButton)
                                        root.openTones(cellItem.flatIndex);
                                    else
                                        root.pick(cellItem.modelData);
                                }
                            }
                        }
                    }
                }
            }

            StyledScrollBar.vertical: StyledScrollBar {
                flickable: list
            }
        }

        StyledText {
            anchors.centerIn: list
            visible: root.layout.flat.length === 0
            text: Emoji.loaded ? Tr.tr("No emoji for “%1”").arg(root.query) : Tr.tr("Loading…")
            color: Colours.palette.m3onSurfaceVariant
        }

        // The selected emoji, big, with its name
        RowLayout {
            id: preview

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: tabs.top
            anchors.leftMargin: Tokens.padding.large
            anchors.rightMargin: Tokens.padding.large
            anchors.bottomMargin: Tokens.spacing.small
            height: 36
            spacing: Tokens.spacing.medium

            Text {
                text: root.currentEmoji ? Emoji.toned(root.currentEmoji) : ""
                font.family: "Noto Color Emoji"
                font.pixelSize: 24
            }

            StyledText {
                Layout.fillWidth: true
                text: root.currentEmoji?.n ?? ""
                color: Colours.palette.m3onSurface
                elide: Text.ElideRight
            }

            StyledText {
                visible: !!root.currentEmoji?.v
                text: Tr.tr("Tab: skin tone")
                color: Colours.palette.m3outline
                font: Tokens.font.label.small
            }
        }

        // The categories; clicking one scrolls to it
        Row {
            id: tabs

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Tokens.padding.medium
            height: 36
            visible: !root.query

            Repeater {
                model: root.sections

                Item {
                    id: tab

                    required property var modelData
                    required property int index
                    readonly property bool active: list.activeSection === index

                    width: Math.floor((sheet.width - Tokens.padding.large * 2) / Math.max(1, root.sections.length))
                    height: tabs.height

                    StyledRect {
                        anchors.centerIn: parent
                        implicitWidth: 32
                        implicitHeight: 32
                        radius: Tokens.rounding.full
                        color: tab.active ? Colours.palette.m3secondaryContainer : "transparent"
                    }

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: tab.modelData.icon
                        color: tab.active ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                        fill: tab.active ? 1 : 0
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.jumpTo(tab.index);
                            search.forceActiveFocus();
                        }
                    }
                }
            }
        }

        // Skin tones for the chosen emoji, above its cell
        StyledRect {
            id: tonePopup

            readonly property int anchorRow: root.toneFor >= 0 ? (root.layout.flat[root.toneFor]?.row ?? -1) : -1
            readonly property Item anchorRowItem: anchorRow >= 0 ? list.itemAtIndex(anchorRow) : null
            readonly property point at: anchorRowItem ? Qt.point(list.x + (root.toneFor - root.layout.rows[anchorRow].first) * root.cell, list.y + anchorRowItem.y - list.contentY) : Qt.point(0, 0)

            visible: !!anchorRowItem
            z: 2
            width: toneRow.implicitWidth + Tokens.padding.small * 2
            height: root.cell + Tokens.padding.small * 2
            x: Math.max(Tokens.padding.small, Math.min(sheet.width - width - Tokens.padding.small, at.x + root.cell / 2 - width / 2))
            y: at.y > height + Tokens.padding.small ? at.y - height - 2 : at.y + root.cell + 2
            radius: Tokens.rounding.large
            color: Colours.palette.m3surfaceContainerHigh

            Elevation {
                anchors.fill: parent
                radius: parent.radius
                level: 2
                z: -1
            }

            Row {
                id: toneRow

                anchors.centerIn: parent

                Repeater {
                    model: root.currentEmoji?.v ? [root.currentEmoji.e, ...root.currentEmoji.v] : []

                    Item {
                        id: tone

                        required property string modelData
                        required property int index

                        width: root.cell
                        height: root.cell

                        StyledRect {
                            anchors.fill: parent
                            anchors.margins: 2
                            radius: Tokens.rounding.medium
                            color: root.toneIndex === tone.index ? Colours.palette.m3secondaryContainer : "transparent"
                        }

                        Text {
                            anchors.centerIn: parent
                            text: tone.modelData
                            font.family: "Noto Color Emoji"
                            font.pixelSize: 26
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: root.toneIndex = tone.index
                            onClicked: {
                                const e = root.currentEmoji;
                                Emoji.setTone(e, tone.index);
                                root.toneFor = -1;
                                root.pick(e);
                            }
                        }
                    }
                }
            }
        }
    }
}
