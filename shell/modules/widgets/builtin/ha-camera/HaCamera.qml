import QtQuick
import qs.components.ha

// A Home Assistant camera on the desktop; settings: instance, entity, name, interval
HaCameraView {
    property var settings: ({})

    instance: settings.instance ?? ""
    entityId: settings.entity ?? ""
    name: settings.name ?? ""
    interval: settings.interval ?? 5
}
