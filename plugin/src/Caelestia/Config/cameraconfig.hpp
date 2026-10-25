#pragma once

#include <qstring.h>

#include "settings/objectnode.hpp"
#include "common.hpp"

namespace caelestia::config {

using Qt::StringLiterals::operator""_s;

// Reacting to whether you're at the desk (webcam face detection)
class CameraPresence : public settings::ObjectNode {
    CONFIG_NODE(CameraPresence, settings::ObjectNode)

    CONFIG_PROPERTY(bool, enabled, true)
    // Seconds without input before the camera starts checking
    CONFIG_PROPERTY(int, checkAfter, 60)
    // Seconds between checks while idle
    CONFIG_PROPERTY(int, interval, 20)
    // Checks in a row without a face before you count as away
    CONFIG_PROPERTY(int, awayAfter, 3)
    CONFIG_PROPERTY(bool, lockWhenAway, true)
    // Hold off idle actions while you're there but not typing (reading, watching)
    CONFIG_PROPERTY(bool, keepAwake, true)
    // While locked: wake the screen and start face unlock when you sit back down
    CONFIG_PROPERTY(bool, wakeOnReturn, true)
    CONFIG_PROPERTY(int, lockedInterval, 6)
};

// The webcam as a light sensor
class CameraLight : public settings::ObjectNode {
    CONFIG_NODE(CameraLight, settings::ObjectNode)

    CONFIG_PROPERTY(bool, enabled, false)
    // Seconds between readings
    CONFIG_PROPERTY(int, interval, 300)
    CONFIG_PROPERTY(bool, adjustBrightness, true)
    CONFIG_PROPERTY(qreal, minBrightness, 0.3)
    CONFIG_PROPERTY(qreal, maxBrightness, 1.0)
    // Camera light level (0-1, see the reading in Nexus) of a dark and a bright room
    CONFIG_PROPERTY(qreal, darkLevel, 0.15)
    CONFIG_PROPERTY(qreal, brightLevel, 0.5)
    // Switch the scheme to dark below darkLevel and to light above brightLevel
    CONFIG_PROPERTY(bool, switchScheme, false)
};

// Hand gestures. Actions: "media.toggle", "media.next", "media.previous",
// "media.stop", "none", or any shell command
class CameraGestures : public settings::ObjectNode {
    CONFIG_NODE(CameraGestures, settings::ObjectNode)

    CONFIG_PROPERTY(bool, enabled, false)
    CONFIG_PROPERTY(QString, palm, u"media.toggle"_s)
    CONFIG_PROPERTY(QString, swipeLeft, u"media.previous"_s)
    CONFIG_PROPERTY(QString, swipeRight, u"media.next"_s)
    CONFIG_PROPERTY(QString, thumbsUp, u"none"_s)
    CONFIG_PROPERTY(QString, thumbsDown, u"none"_s)
};

// A photo after repeated wrong passwords on the lock screen
class CameraSnapshots : public settings::ObjectNode {
    CONFIG_NODE(CameraSnapshots, settings::ObjectNode)

    CONFIG_PROPERTY(bool, enabled, true)
    CONFIG_PROPERTY(int, afterFailures, 3)
    CONFIG_PROPERTY(QString, dir, u"~/Pictures/Unlock attempts"_s)
};

class CameraConfig : public settings::ObjectNode {
    CONFIG_NODE(CameraConfig, settings::ObjectNode)

    CONFIG_PROPERTY(bool, enabled, true)
    CONFIG_PROPERTY(QString, device, u"/dev/video0"_s)
    // caelestia-camerad to run; empty for the packaged one
    CONFIG_PROPERTY(QString, daemon, u""_s)
    CONFIG_SUBOBJECT(CameraPresence, presence)
    CONFIG_SUBOBJECT(CameraLight, light)
    CONFIG_SUBOBJECT(CameraGestures, gestures)
    CONFIG_SUBOBJECT(CameraSnapshots, snapshots)
};

} // namespace caelestia::config
