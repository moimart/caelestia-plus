#pragma once

#include <qstring.h>
#include <qstringlist.h>

#include "settings/objectnode.hpp"
#include "common.hpp"

namespace caelestia::config {

using Qt::StringLiterals::operator""_s;

// The Microsoft Surface Dial (services/SurfaceDial.qml). Pressing it cycles
// through modes; turning it acts in the current one.
class SurfaceDialConfig : public settings::ObjectNode {
    CONFIG_NODE(SurfaceDialConfig, settings::ObjectNode)

    CONFIG_PROPERTY(bool, enabled, true)
    // The modes a press cycles through, in order: "volume" (system volume),
    // "zoom" (Hyprland's cursor zoom), "appScroll" (scrolls what's under the
    // pointer), "layoutScroll" (Hyprland's scrolling layout, a column at a
    // time), and "ha:<id>" for each Home Assistant dial control (the entities
    // in home-assistant.json's dialControls: a light's brightness, a player's
    // volume, a cover's position...; Nexus → Home Assistant adds them)
    CONFIG_PROPERTY(QStringList, modes,
        (QStringList { u"volume"_s, u"zoom"_s, u"appScroll"_s, u"layoutScroll"_s }))
    // A toast when the mode changes, and when the dial connects or goes away
    CONFIG_PROPERTY(bool, toasts, true)
    // Percent per step
    CONFIG_PROPERTY(int, volumeStep, 2)
    CONFIG_PROPERTY(qreal, zoomStep, 0.5)
    CONFIG_PROPERTY(qreal, maxZoom, 10)
    // Wheel notches per step
    CONFIG_PROPERTY(int, scrollSpeed, 1)
    // Scrolling layout: 0 moves a column at a time, more moves this many pixels
    CONFIG_PROPERTY(int, layoutPixels, 0)
};

} // namespace caelestia::config
