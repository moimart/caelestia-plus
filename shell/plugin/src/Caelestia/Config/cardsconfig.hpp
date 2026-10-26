#pragma once

#include <qstring.h>

#include "settings/objectnode.hpp"
#include "common.hpp"

namespace caelestia::config {

using Qt::StringLiterals::operator""_s;

// Window cards: two windows paired into one that flips over to show the other
class CardsConfig : public settings::ObjectNode {
    CONFIG_NODE(CardsConfig, settings::ObjectNode)

    CONFIG_PROPERTY(bool, enabled, true)
    // Length of a flip in milliseconds
    CONFIG_PROPERTY(int, duration, 600)
    // Camera distance as a multiple of the card's width; smaller is more dramatic
    CONFIG_PROPERTY(qreal, perspective, 2.2)
    // How far the card shrinks mid-flip, as if lifted off the desk (0 to disable)
    CONFIG_PROPERTY(qreal, lift, 0.08)
    // Which way the card turns: "left" or "right"
    CONFIG_PROPERTY(QString, direction, u"right"_s)
};

} // namespace caelestia::config
