pragma Singleton

import QtQuick
import Quickshell
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.services
import qs.modules.nexus

Singleton {
    id: root

    function create(parent: Item, props: var): void {
        nexusComp.createObject(parent ?? dummy, props);
    }

    QtObject {
        id: dummy
    }

    Component {
        id: nexusComp

        FloatingWindow {
            id: win

            // Page to open on, as an index into PageRegistry.pages
            property int initialPage: -1
            // A sub-page of it to open too (its index in the page's StackPage)
            property int initialSubPage: -1

            color: Colours.tPalette.m3surface
            surfaceFormat.opaque: false

            onVisibleChanged: {
                if (!visible)
                    destroy();
            }

            implicitWidth: nexus.implicitWidth
            implicitHeight: nexus.implicitHeight

            minimumSize.width: contentItem.Tokens.sizes.nexus.minWidth
            minimumSize.height: contentItem.Tokens.sizes.nexus.minHeight

            contentItem.Config.screen: screen.name
            contentItem.Tokens.screen: screen.name

            title: Tr.tr("Nexus — %1").arg(PageRegistry.pages[nexus.nState.currentPageIdx].label)

            Nexus {
                id: nexus

                anchors.fill: parent
                nState.screen: win.screen
                nState.isWindow: true
                onClose: win.destroy()
                Component.onCompleted: {
                    if (win.initialPage >= 0)
                        nState.currentPageIdx = win.initialPage;
                    if (win.initialSubPage >= 0)
                        Qt.callLater(() => nState.openSubPage(win.initialSubPage));
                }
            }

            Behavior on color {
                CAnim {}
            }
        }
    }
}
