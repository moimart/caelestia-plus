#pragma once

#include <qstring.h>

#include "settings/objectnode.hpp"
#include "common.hpp"

namespace caelestia::config {

using Qt::StringLiterals::operator""_s;

class KeybindsConfig : public settings::ObjectNode {
    CONFIG_NODE(KeybindsConfig, settings::ObjectNode)

    CONFIG_PROPERTY(bool, enabled, true)
    // Hyprland config to read; empty finds ~/.config/hypr/hyprland.lua (or .conf)
    CONFIG_PROPERTY(QString, configPath, u""_s)
    CONFIG_PROPERTY(bool, showCommands, true)
    CONFIG_PROPERTY(bool, showUnbound, true)
    CONFIG_PROPERTY(bool, showInternal, false)
};

} // namespace caelestia::config
