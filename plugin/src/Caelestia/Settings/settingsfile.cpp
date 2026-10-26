#include "settingsfile.hpp"

#include <qdir.h>
#include <qfile.h>
#include <qfileinfo.h>
#include <qjsonarray.h>
#include <qjsondocument.h>
#include <qjsonobject.h>
#include <qloggingcategory.h>
#include <qsavefile.h>
#include <qstandardpaths.h>

#include <ranges>
#include <utility>

#include "util/i18n.hpp"

namespace {

Q_LOGGING_CATEGORY(lcSettingsFile, "caelestia.settings.file", QtInfoMsg)

} // namespace

namespace caelestia::settings {

using Qt::StringLiterals::operator""_s;
using util::i18n::mark;

namespace {

// Max retries for loads which fail due to malformed JSON, e.g. partial writes
constexpr int k_maxLoadRetries = 3;

// A file under the user's config dir (~/.config/caelestia/shell.json) can have
// base files at the same place under each system config dir
// ($XDG_CONFIG_DIRS, /etc/xdg by default): defaults a package ships, or a host
// profile. They're read first and the user's file goes on top, and only what
// differs from them is written back. Lowest priority first.
QStringList basePathsFor(const QString& path) {
    auto dirs = QStandardPaths::standardLocations(QStandardPaths::GenericConfigLocation);
    if (dirs.isEmpty())
        return {};

    const auto userDir = QDir::cleanPath(dirs.takeFirst()) + u'/';
    const auto absolute = QDir::cleanPath(QFileInfo(path).absoluteFilePath());
    if (!absolute.startsWith(userDir))
        return {};

    const auto relative = absolute.mid(userDir.size());
    QStringList bases;
    for (const auto& dir : std::views::reverse(dirs))
        bases << QDir::cleanPath(dir) + u'/' + relative;
    return bases;
}

// Objects merge key by key; anything else in `over` replaces what's in `base`
QJsonObject merged(QJsonObject base, const QJsonObject& over) {
    for (auto it = over.constBegin(); it != over.constEnd(); ++it) {
        const auto under = base.value(it.key());
        if (under.isObject() && it->isObject())
            base.insert(it.key(), merged(under.toObject(), it->toObject()));
        else
            base.insert(it.key(), *it);
    }
    return base;
}

// What in `full` differs from `base`
QJsonObject without(const QJsonObject& full, const QJsonObject& base) {
    QJsonObject diff;
    for (auto it = full.constBegin(); it != full.constEnd(); ++it) {
        if (!base.contains(it.key())) {
            diff.insert(it.key(), *it);
            continue;
        }
        const auto under = base.value(it.key());
        if (under.isObject() && it->isObject()) {
            const auto sub = without(it->toObject(), under.toObject());
            if (!sub.isEmpty())
                diff.insert(it.key(), sub);
        } else if (*it != under) {
            diff.insert(it.key(), *it);
        }
    }
    return diff;
}

} // namespace

SettingsFile::SettingsFile(bool watch, QString path, QObject* parent)
    : QObject(parent)
    , m_path(std::move(path))
    , m_basePaths(basePathsFor(m_path))
    , m_watcher(watch ? new QFileSystemWatcher(this) : nullptr)
    , m_saveDebounce(new QTimer(this))
    , m_loadDebounce(watch ? new QTimer(this) : nullptr)
    , m_loadRetries(0) {
    m_saveDebounce->setSingleShot(true);
    m_saveDebounce->setInterval(500); // Save at most once every 500ms

    if (!watch)
        return;

    m_loadDebounce->setSingleShot(true);
    m_loadDebounce->setInterval(50); // Coalesce watcher events within 50ms
    QObject::connect(m_loadDebounce, &QTimer::timeout, this, &SettingsFile::onLoadDebounced);

    QObject::connect(m_watcher, &QFileSystemWatcher::fileChanged, this, &SettingsFile::onFileChanged);
    QObject::connect(m_watcher, &QFileSystemWatcher::directoryChanged, this, &SettingsFile::onDirChanged);

    initWatcher();
}

SettingsFile::~SettingsFile() {
    writeNow();
}

std::optional<QJsonValue> SettingsFile::read() const {
    return m_lastData;
}

QJsonObject SettingsFile::readBases() {
    QJsonObject base;
    for (const auto& path : std::as_const(m_basePaths)) {
        QFile file(path);
        if (!file.open(QIODevice::ReadOnly))
            continue;
        QJsonParseError error;
        const auto doc = QJsonDocument::fromJson(file.readAll(), &error);
        if (error.error != QJsonParseError::NoError || !doc.isObject()) {
            qCWarning(lcSettingsFile, "Ignoring base file %s: %s", qUtf8Printable(path),
                qUtf8Printable(error.error != QJsonParseError::NoError ? error.errorString() : u"not an object"_s));
            continue;
        }
        base = merged(base, doc.object());
    }
    return base;
}

void SettingsFile::write(const QJsonValue& json) {
    m_pendingWrite = json;
    save();
}

void SettingsFile::onFileChanged() {
    initWatcher(); // Re-add path in case the file was replaced
    scheduleLoad();
}

void SettingsFile::onDirChanged() {
    // Ignore if the file is already watched
    if (m_watcher->files().contains(m_path))
        return;

    initWatcher();

    if (QFile::exists(m_path))
        scheduleLoad();
}

void SettingsFile::initWatcher() {
    if (!m_watcher)
        return;

    const QFileInfo info(m_path);
    const auto dir = info.absolutePath();

    if (QDir(dir).exists() && !m_watcher->directories().contains(dir))
        m_watcher->addPath(dir);

    if (info.exists() && !m_watcher->files().contains(m_path))
        m_watcher->addPath(m_path);

    // Base files change when a package updates
    for (const auto& path : std::as_const(m_basePaths))
        if (QFile::exists(path) && !m_watcher->files().contains(path))
            m_watcher->addPath(path);
}

void SettingsFile::scheduleLoad() {
    // Ignore if not watching or a load is already pending
    if (!m_loadDebounce || m_loadDebounce->isActive())
        return;

    m_loadRetries = 0;
    m_loadDebounce->start();
}

void SettingsFile::onLoadDebounced() {
    const auto isFinalTry = m_loadRetries >= k_maxLoadRetries;

    if (load(isFinalTry) == LoadResult::ParseError && !isFinalTry) {
        // Likely a partial write, retry after another debounce
        ++m_loadRetries;
        qCDebug(lcSettingsFile, "Retrying load of %s (%d/%d)", qUtf8Printable(m_path), m_loadRetries, k_maxLoadRetries);
        m_loadDebounce->start();
    }
}

SettingsFile::LoadResult SettingsFile::load(bool reportErrors) {
    QFile file(m_path);
    m_base = readBases();

    if (!file.exists() && !m_base.isEmpty()) {
        // Only the base files: they are the whole config
        const QJsonValue json(m_base);
        if (json == m_lastData)
            return LoadResult::Unchanged;
        m_pendingWrite = std::nullopt;
        m_lastData = json;
        emit changed();
        return LoadResult::Changed;
    }

    if (!file.exists()) {
        if (m_lastData) {
            m_lastData = std::nullopt;
            emit changed();
            return LoadResult::Changed;
        }
        return LoadResult::Unchanged;
    }

    if (!file.open(QIODevice::ReadOnly)) {
        qCWarning(lcSettingsFile, "Failed to open %s for reading: %s", qUtf8Printable(m_path),
            qUtf8Printable(file.errorString()));
        emit readFailed(mark(u"Failed to open: %1"_s, { file.errorString() }));
        return LoadResult::Error;
    }

    const auto data = file.readAll();
    file.close();

    QJsonParseError error;
    const auto doc = QJsonDocument::fromJson(data, &error);

    if (error.error != QJsonParseError::NoError) {
        if (reportErrors) {
            qCWarning(lcSettingsFile, "Failed to parse %s as JSON: %s", qUtf8Printable(m_path),
                qUtf8Printable(error.errorString()));
            emit readFailed(mark(u"Failed to parse: %1"_s, { error.errorString() }));
        } else {
            qCDebug(lcSettingsFile, "Failed to parse %s as JSON: %s", qUtf8Printable(m_path),
                qUtf8Printable(error.errorString()));
        }
        return LoadResult::ParseError;
    }

    auto json = doc.isObject() ? QJsonValue(doc.object()) : QJsonValue(doc.array());
    if (!m_base.isEmpty() && json.isObject())
        json = merged(m_base, json.toObject());

    if (json == m_lastData)
        return LoadResult::Unchanged;

    // Clear pending write, stuff loaded from file should take precedence
    m_pendingWrite = std::nullopt;

    m_lastData = json;
    emit changed();

    qCDebug(lcSettingsFile) << "Read JSON from" << m_path;
    qCDebug(lcSettingsFile) << " " << json;

    return LoadResult::Changed;
}

void SettingsFile::save() {
    if (!m_pendingWrite)
        return;

    if (m_saveDebounce->isActive()) {
        // Queue save for debounce end
        QObject::connect(m_saveDebounce, &QTimer::timeout, this, &SettingsFile::save,
            // NOLINTNEXTLINE(clang-analyzer-optin.core.EnumCastOutOfRange) ConnectionType is OR-able by design
            static_cast<Qt::ConnectionType>(Qt::UniqueConnection | Qt::SingleShotConnection));
        return;
    }

    // Debounce regardless of whether the save actually succeeded
    m_saveDebounce->start();
    writeNow();
}

void SettingsFile::writeNow() {
    if (!m_pendingWrite)
        return;

    const auto json = *m_pendingWrite;
    // Only what differs from the base files goes in the user's file
    const auto own = !m_base.isEmpty() && json.isObject() ? QJsonValue(without(json.toObject(), m_base)) : json;
    const auto data = (own.isObject() ? QJsonDocument(own.toObject()) : QJsonDocument(own.toArray())).toJson();
    m_pendingWrite = std::nullopt;

    const auto dir = QFileInfo(m_path).absolutePath();

    if (!QDir().mkpath(dir)) {
        qCWarning(lcSettingsFile) << "Failed to create dir" << dir;
        emit writeFailed(mark(u"Failed to create parent directory"_s));
        return;
    }

    // Write atomically
    QSaveFile file(m_path);

    if (!file.open(QIODevice::WriteOnly)) {
        qCWarning(lcSettingsFile, "Failed to open %s for writing: %s", qUtf8Printable(m_path),
            qUtf8Printable(file.errorString()));
        emit writeFailed(mark(u"Failed to open: %1"_s, { file.errorString() }));
        return;
    }

    file.write(data);

    if (!file.commit()) {
        qCWarning(lcSettingsFile, "Failed to write %s: %s", qUtf8Printable(m_path), qUtf8Printable(file.errorString()));
        emit writeFailed(mark(u"Failed to write: %1"_s, { file.errorString() }));
        return;
    }

    m_lastData = json;
    qCDebug(lcSettingsFile) << "Saved" << m_path;

    initWatcher(); // The file may have just been created, or replaced by the rename
}

} // namespace caelestia::settings
