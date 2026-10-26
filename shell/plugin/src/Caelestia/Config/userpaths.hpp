#pragma once

#include <qstandardpaths.h>
#include <qstring.h>

#include "settings/objectnode.hpp"
#include "common.hpp"

namespace caelestia::config {

using Qt::StringLiterals::operator""_s;

class UserPaths : public settings::ObjectNode {
    CONFIG_NODE(UserPaths, settings::ObjectNode)

    CONFIG_GLOBAL_PROPERTY(
        QString, wallpaperDir, QStandardPaths::writableLocation(QStandardPaths::PicturesLocation) + u"/Wallpapers"_s)
    CONFIG_GLOBAL_PROPERTY(QString, videoWallpaperDir,
        QStandardPaths::writableLocation(QStandardPaths::HomeLocation) + u"/VideoWallpapers"_s)
    CONFIG_GLOBAL_PROPERTY(
        QString, lyricsDir, QStandardPaths::writableLocation(QStandardPaths::MusicLocation) + u"/Lyrics/"_s)
    // Profile picture shown on the lock screen and dashboard; an image or a video (played on loop)
    CONFIG_GLOBAL_PROPERTY(QString, face, u"~/.face"_s)
    CONFIG_PROPERTY(QString, sessionGif, u"root:/assets/kurukuru.gif"_s)
    CONFIG_PROPERTY(QString, mediaGif, u"root:/assets/bongocat.gif"_s)
    CONFIG_PROPERTY(QString, noNotifsPic, u"root:/assets/dino.png"_s)
    CONFIG_PROPERTY(QString, lockNoNotifsPic, u"root:/assets/dino.png"_s)
};

} // namespace caelestia::config
