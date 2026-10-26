#pragma once

#include <qlocalsocket.h>
#include <qobject.h>
#include <qpoint.h>
#include <qqmlintegration.h>
#include <qsharedpointer.h>
#include <qtimer.h>
#include <qvariant.h>

namespace caelestia::services::hypr {

class HyprDevices;

class HyprExtras : public QObject {
    Q_OBJECT
    QML_ELEMENT
    Q_MOC_INCLUDE("hyprdevices.hpp")

    Q_PROPERTY(QVariantHash options READ options NOTIFY optionsChanged)
    Q_PROPERTY(caelestia::services::hypr::HyprDevices* devices READ devices CONSTANT)
    Q_PROPERTY(bool usingLua MEMBER m_usingLua NOTIFY usingLuaChanged)
    // The pointer in Hyprland's global layout coordinates (logical pixels).
    // Only polled while trackCursor is set: fast while it moves, slowly when still.
    Q_PROPERTY(QPointF cursorPos READ cursorPos NOTIFY cursorPosChanged)
    Q_PROPERTY(bool trackCursor READ trackCursor WRITE setTrackCursor NOTIFY trackCursorChanged)

public:
    explicit HyprExtras(QObject* parent = nullptr);

    [[nodiscard]] QVariantHash options() const;
    [[nodiscard]] HyprDevices* devices() const;
    [[nodiscard]] QPointF cursorPos() const;
    [[nodiscard]] bool trackCursor() const;
    void setTrackCursor(bool track);

    Q_INVOKABLE void message(const QString& message);
    Q_INVOKABLE void batchMessage(const QStringList& messages);
    Q_INVOKABLE void applyOptions(const QVariantHash& options);

    Q_INVOKABLE void refreshOptions();
    Q_INVOKABLE void refreshDevices();

signals:
    void optionsChanged();
    void usingLuaChanged();
    void cursorPosChanged();
    void trackCursorChanged();

private:
    using SocketPtr = QSharedPointer<QLocalSocket>;

    QString m_requestSocket;
    QString m_eventSocket;
    QLocalSocket* m_socket;
    bool m_socketValid;
    bool m_usingLua = false;

    QVariantHash m_options;
    HyprDevices* const m_devices;

    SocketPtr m_optionsRefresh;
    SocketPtr m_devicesRefresh;

    QPointF m_cursorPos;
    bool m_trackCursor = false;
    int m_cursorStill = 0;
    QTimer* const m_cursorTimer;
    SocketPtr m_cursorRequest;

    void pollCursor();

    void socketError(QLocalSocket::LocalSocketError error) const;
    void socketStateChanged(QLocalSocket::LocalSocketState state);
    void readEvent();
    void handleEvent(const QString& event);

    SocketPtr makeRequestJson(const QString& request, const std::function<void(bool, QJsonDocument)>& callback);
    SocketPtr makeRequest(const QString& request, const std::function<void(bool, QByteArray)>& callback);
};

} // namespace caelestia::services::hypr
