#pragma once

#include <qobject.h>
#include <qqmlintegration.h>
#include <qstring.h>

class QFileSystemWatcher;
class QSocketNotifier;
class QTimer;

namespace caelestia::services {

// The Microsoft Surface Dial, read straight from its evdev node.
//
// The dial is a Bluetooth HID device: the kernel gives it an input node
// ("Surface Dial System Multi Axis") while it's awake and drops it when it
// sleeps. This watches /dev/input for it (inotify, so no polling), grabs it so
// nothing else turns its rotation into scrolling, and reports rotation and the
// button. Reading is event driven: an idle dial costs nothing.
//
// Access comes from a udev uaccess rule (assets/udev/70-caelestia-surface-dial.rules),
// which also opens /dev/uinput for scroll(): a virtual wheel for the
// "scroll the app under the pointer" mode.
//
// What rotation does is up to QML (services/SurfaceDial.qml).
class SurfaceDial : public QObject {
    Q_OBJECT
    // services/SurfaceDial.qml is the SurfaceDial QML uses
    QML_NAMED_ELEMENT(DialDevice)
    QML_SINGLETON

    // Watch for the dial and grab it. Off: let go of it (another program can have it)
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged)
    Q_PROPERTY(bool connected READ connected NOTIFY connectedChanged)
    // Why the dial can't be used, when it's there but not readable
    Q_PROPERTY(QString error READ error NOTIFY errorChanged)

public:
    static SurfaceDial* instance();
    static SurfaceDial* create(QQmlEngine* engine, QJSEngine* jsEngine);
    ~SurfaceDial() override;

    [[nodiscard]] bool enabled() const;
    void setEnabled(bool enabled);
    [[nodiscard]] bool connected() const;
    [[nodiscard]] QString error() const;

    // Scrolls whatever is under the pointer by this many wheel notches
    // (positive: up), through a virtual wheel made on first use
    Q_INVOKABLE void scroll(int notches);

signals:
    void enabledChanged();
    void connectedChanged();
    void errorChanged();

    // Rotation, in the dial's own steps: only the sign is reliable (positive
    // is clockwise); how fast it's turned shows as how often this comes
    void rotated(int delta);
    void pressed();
    void released();

private:
    explicit SurfaceDial(QObject* parent = nullptr);

    void scan();
    bool open(const QString& node);
    void close();
    void readEvents();
    void setError(const QString& error);
    bool ensureWheel();

    bool m_enabled = false;
    QString m_error;

    int m_fd = -1;
    QSocketNotifier* m_notifier = nullptr;
    QFileSystemWatcher* m_watcher = nullptr;
    // udev sets the node's permissions a moment after it appears
    QTimer* m_rescan = nullptr;
    int m_retries = 0;

    int m_wheelFd = -1;
    bool m_wheelFailed = false;
};

} // namespace caelestia::services
