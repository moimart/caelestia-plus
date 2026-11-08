#pragma once

#include <qdbusconnection.h>
#include <qdbusunixfiledescriptor.h>
#include <qobject.h>
#include <qqmlintegration.h>
#include <qstring.h>
#include <qstringlist.h>
#include <qvariant.h>

#include <optional>

namespace caelestia::services {

class SessionManager : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    // Holds logind's idle and sleep inhibitors (Keep awake). Dropped by the
    // system if the shell dies.
    Q_PROPERTY(bool holdSleep READ holdSleep WRITE setHoldSleep NOTIFY holdSleepChanged)

public:
    explicit SessionManager(QObject* parent = nullptr);

    [[nodiscard]] bool holdSleep() const;
    void setHoldSleep(bool hold);

    Q_INVOKABLE void logout();
    Q_INVOKABLE void suspend();
    Q_INVOKABLE void suspendThenHibernate();
    Q_INVOKABLE void hibernate();
    Q_INVOKABLE void poweroff();
    Q_INVOKABLE void reboot();

    Q_INVOKABLE bool exec(const QStringList& command);

signals:
    void holdSleepChanged();
    void aboutToSleep();
    void resumed();
    void lockRequested();
    void unlockRequested();

private slots:
    void handlePrepareForSleep(bool sleep);
    void handleLockRequested();
    void handleUnlockRequested();

private:
    [[nodiscard]] static std::optional<QDBusConnection> getSystemBus();
    [[nodiscard]] static bool queryHibernateAvailable();
    void call(const QString& path, const QString& iface, const QString& method, const QVariantList& args = {});
    void callManager(const QString& method);
    void callSession(const QString& method);

    QString m_sessionPath;
    bool m_holdSleep = false;
    QDBusUnixFileDescriptor m_sleepHold;
};

} // namespace caelestia::services
