#pragma once

#include "settings/objectnode.hpp"
#include "common.hpp"

namespace caelestia::config {

// Desktop widgets (widget plugins placed on the desktop)
class WidgetsConfig : public settings::ObjectNode {
    CONFIG_NODE(WidgetsConfig, settings::ObjectNode)

    CONFIG_PROPERTY(bool, enabled, true)
    // Snap widgets to this many pixels while placing them (0 to disable)
    CONFIG_PROPERTY(int, gridSize, 8)
};

} // namespace caelestia::config
