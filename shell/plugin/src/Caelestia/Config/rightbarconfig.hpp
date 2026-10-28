#pragma once

#include <qstring.h>
#include <qstringlist.h>

#include "settings/objectnode.hpp"
#include "common.hpp"

namespace caelestia::config {

using Qt::StringLiterals::operator""_s;

// A second bar on the right edge, as thick as the left one: volume and
// brightness controls that are always there, and buttons that run actions (built-in ones like a
// screenshot or a screen recording, or your own action plugins)
class RightBarConfig : public settings::ObjectNode {
    CONFIG_NODE(RightBarConfig, settings::ObjectNode)

    CONFIG_PROPERTY(bool, enabled, false)
    // The output volume slider, always shown
    CONFIG_PROPERTY(bool, volume, true)
    // A slider for the microphone as well
    CONFIG_PROPERTY(bool, microphone, false)
    // A slider for this display's brightness, where it can be set (DDC, a backlight)
    CONFIG_PROPERTY(bool, brightness, true)
    // The action buttons, top to bottom, by id (see Settings → Panels → Right bar)
    CONFIG_PROPERTY(QStringList, actions, (QStringList{ u"screenshot"_s, u"recordRegion"_s }))
};

} // namespace caelestia::config
