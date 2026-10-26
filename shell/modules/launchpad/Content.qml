pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.containers
import qs.components.controls
import qs.components.effects
import qs.services
import qs.modules.launcher.services

// The app grid: pages of apps, A to Z, that typing filters. Arrows move the
// selection (across pages too), Enter launches it, the wheel or a drag turns
// the page, and Escape clears the search or closes.
Item {
    id: root

    required property bool shown

    readonly property string query: search.text.trim()
    // The launcher's apps (its hidden apps, fuzzy setting and usage counts),
    // alphabetical until you type, then best match first
    readonly property var apps: query ? Apps.search(query) : Apps.search("").sort((a, b) => a.name.localeCompare(b.name))

    readonly property int cellWidth: 148
    readonly property int cellHeight: 136
    readonly property int columns: Math.max(4, Math.min(8, Math.floor(Math.min(width * 0.7, 1400) / cellWidth)))
    readonly property int rows: Math.max(2, Math.min(5, Math.floor((height * 0.8 - 160) / cellHeight)))
    readonly property int perPage: columns * rows
    readonly property var pages: {
        const out = [];
        for (let i = 0; i < apps.length; i += perPage)
            out.push(apps.slice(i, i + perPage));
        return out;
    }

    property int current: 0
    // The selection shows once you type or use the arrows, like Launchpad's
    property bool keyboard: false

    signal closeRequested
    signal hidden

    function launch(entry: DesktopEntry): void {
        if (!entry)
            return;
        Apps.launch(entry);
        closeRequested();
    }

    function select(index: int): void {
        if (apps.length === 0)
            return;
        current = Math.max(0, Math.min(apps.length - 1, index));
        keyboard = true;
        pager.currentIndex = Math.floor(current / perPage);
    }

    // Up and down stay in the column, within the page
    function moveRow(dy: int): void {
        const page = Math.floor(current / perPage);
        const inPage = current - page * perPage;
        const target = inPage + dy * columns;
        if (target >= 0 && target < perPage && page * perPage + target < apps.length)
            select(page * perPage + target);
        else if (!keyboard)
            select(current);
    }

    function turnPage(delta: int): void {
        const page = Math.max(0, Math.min(pages.length - 1, pager.currentIndex + delta));
        pager.currentIndex = page;
        if (keyboard)
            current = Math.min(apps.length - 1, page * perPage + current % perPage);
    }

    onShownChanged: {
        if (shown) {
            search.text = "";
            current = 0;
            keyboard = false;
            pager.currentIndex = 0;
            pager.positionViewAtBeginning();
            search.forceActiveFocus();
        }
    }
    onQueryChanged: {
        current = 0;
        keyboard = !!query;
        pager.currentIndex = 0;
    }

    // Launchpad dims and blurs what's behind it (Launchpad.qml adds the blur)
    StyledRect {
        anchors.fill: parent
        color: Qt.alpha(Colours.palette.m3scrim, 0.35)
        opacity: root.shown ? 1 : 0

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }

    // Clicking outside the apps closes it
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

        anchors.centerIn: parent
        width: root.columns * root.cellWidth + Tokens.padding.large * 4
        height: search.height + root.rows * root.cellHeight + dots.height + Tokens.padding.large * 4 + Tokens.spacing.large
        radius: Tokens.rounding.extraLarge
        color: Colours.tPalette.m3surfaceContainerLow

        // Zooms out into place, like Launchpad
        opacity: root.shown ? 1 : 0
        scale: root.shown ? 1 : 1.06

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

        // Swallows clicks between the apps, and turns pages with the wheel
        MouseArea {
            property real wheel

            anchors.fill: parent
            onWheel: event => {
                wheel += Math.abs(event.angleDelta.y) > Math.abs(event.angleDelta.x) ? event.angleDelta.y : event.angleDelta.x;
                if (Math.abs(wheel) >= 120 && !wheelCooldown.running) {
                    root.turnPage(wheel < 0 ? 1 : -1);
                    wheel = 0;
                    wheelCooldown.start();
                }
            }

            Timer {
                id: wheelCooldown

                interval: 350
                onTriggered: parent.wheel = 0
            }
        }

        SearchBar {
            id: search

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: Tokens.padding.large * 2
            width: Math.min(420, parent.width - Tokens.padding.large * 4)
            placeholderText: Tr.tr("Search apps")

            Keys.onPressed: event => {
                switch (event.key) {
                case Qt.Key_Escape:
                    if (text)
                        text = "";
                    else
                        root.closeRequested();
                    break;
                case Qt.Key_Left:
                case Qt.Key_Right:
                    root.select(root.keyboard ? root.current + (event.key === Qt.Key_Right ? 1 : -1) : root.current);
                    break;
                case Qt.Key_Up:
                case Qt.Key_Down:
                    root.moveRow(event.key === Qt.Key_Down ? 1 : -1);
                    break;
                case Qt.Key_PageUp:
                case Qt.Key_PageDown:
                    root.turnPage(event.key === Qt.Key_PageDown ? 1 : -1);
                    break;
                case Qt.Key_Return:
                case Qt.Key_Enter:
                    root.launch(root.apps[root.current]);
                    break;
                default:
                    return;
                }
                event.accepted = true;
            }
        }

        ListView {
            id: pager

            anchors.top: search.bottom
            anchors.topMargin: Tokens.spacing.large + Tokens.padding.large
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.columns * root.cellWidth
            height: root.rows * root.cellHeight

            clip: true
            orientation: ListView.Horizontal
            snapMode: ListView.SnapOneItem
            highlightRangeMode: ListView.StrictlyEnforceRange
            highlightMoveDuration: Tokens.anim.durations.normal
            boundsBehavior: Flickable.StopAtBounds
            model: root.pages

            delegate: Grid {
                id: page

                required property var modelData
                required property int index

                width: pager.width
                height: pager.height
                columns: root.columns

                Repeater {
                    model: page.modelData

                    Item {
                        id: cell

                        required property DesktopEntry modelData
                        required property int index
                        readonly property int appIndex: page.index * root.perPage + index
                        readonly property bool selected: root.keyboard && root.current === appIndex

                        width: root.cellWidth
                        height: root.cellHeight

                        StateLayer {
                            anchors.fill: parent
                            anchors.margins: Tokens.padding.small
                            radius: Tokens.rounding.large
                            manualHoverOverride: cell.selected
                            onEntered: root.current = cell.appIndex
                            onClicked: root.launch(cell.modelData)
                        }

                        AppIcon {
                            id: icon

                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                            anchors.topMargin: Tokens.padding.large
                            entry: cell.modelData
                            implicitSize: 72
                            scale: cell.selected ? 1.06 : 1

                            Behavior on scale {
                                Anim {
                                    type: Anim.FastSpatial
                                }
                            }
                        }

                        StyledText {
                            anchors.top: icon.bottom
                            anchors.topMargin: Tokens.spacing.small
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: parent.width - Tokens.padding.large * 2
                            horizontalAlignment: Text.AlignHCenter
                            text: cell.modelData?.name ?? ""
                            color: Colours.palette.m3onSurface
                            font: Tokens.font.body.small
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }

        StyledText {
            anchors.centerIn: pager
            visible: root.apps.length === 0
            text: root.query ? Tr.tr("No apps match “%1”").arg(root.query) : Tr.tr("No apps")
            color: Colours.palette.m3onSurfaceVariant
        }

        // One dot per page; click to go there
        Row {
            id: dots

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Tokens.padding.large
            height: 24
            spacing: Tokens.spacing.small
            opacity: root.pages.length > 1 ? 1 : 0

            Repeater {
                model: root.pages.length

                Item {
                    id: dot

                    required property int index
                    readonly property bool active: pager.currentIndex === index

                    width: 20
                    height: dots.height

                    StyledRect {
                        anchors.centerIn: parent
                        implicitWidth: dot.active ? 10 : 8
                        implicitHeight: implicitWidth
                        radius: Tokens.rounding.full
                        color: dot.active ? Colours.palette.m3primary : Colours.palette.m3outlineVariant

                        Behavior on implicitWidth {
                            Anim {
                                type: Anim.FastSpatial
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.turnPage(dot.index - pager.currentIndex);
                            search.forceActiveFocus();
                        }
                    }
                }
            }
        }
    }
}
