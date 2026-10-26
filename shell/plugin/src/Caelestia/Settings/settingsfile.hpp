#pragma once

#include <qfilesystemwatcher.h>
#include <qjsonobject.h>
#include <qjsonvalue.h>
#include <qobject.h>
#include <qtimer.h>

namespace caelestia::settings {

class SettingsFile : public QObject {
    Q_OBJECT

public:
    enum class LoadResult : quint8 {
        Unchanged,
        Changed,
        ParseError,
        Error,
    };

    explicit SettingsFile(bool watch, QString path, QObject* parent = nullptr);
    ~SettingsFile() override;

    [[nodiscard]] std::optional<QJsonValue> read() const;
    void write(const QJsonValue& json);

    LoadResult load(bool reportErrors = true);

signals:
    void changed(); // Data changed, not file watcher event
    void readFailed(const QString& error);
    void writeFailed(const QString& error);

private:
    QString m_path;
    QStringList m_basePaths;
    QJsonObject m_base;            // The base files merged
    QFileSystemWatcher* m_watcher; // Null when not watching
    QTimer* m_saveDebounce;
    QTimer* m_loadDebounce; // Null when not watching
    int m_loadRetries;
    std::optional<QJsonValue> m_lastData;
    std::optional<QJsonValue> m_pendingWrite;

    QJsonObject readBases();
    void onFileChanged();
    void onDirChanged();

    void initWatcher();
    void scheduleLoad();
    void onLoadDebounced();
    void save();
    void writeNow();
};

} // namespace caelestia::settings
