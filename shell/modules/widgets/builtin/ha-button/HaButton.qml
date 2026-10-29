import QtQuick
import qs.components.ha

// A Home Assistant button, scene or script: tap to run on the desktop; settings: instance, entity, name, icon
HaTile {
    property var settings: ({})
    property bool editing

    instance: settings.instance ?? ""
    entityId: settings.entity ?? ""
    name: settings.name ?? ""
    icon: settings.icon ?? ""
    readOnly: editing
}
