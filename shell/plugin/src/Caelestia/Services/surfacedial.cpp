#include "surfacedial.hpp"

#include <qdir.h>
#include <qfile.h>
#include <qfilesystemwatcher.h>
#include <qloggingcategory.h>
#include <qqmlengine.h>
#include <qsocketnotifier.h>
#include <qtimer.h>

#include <cerrno>
#include <cstring>
#include <fcntl.h>
#include <linux/input.h>
#include <linux/uinput.h>
#include <sys/ioctl.h>
#include <unistd.h>

Q_LOGGING_CATEGORY(lcDial, "caelestia.services.surfacedial", QtInfoMsg)

namespace caelestia::services {

using Qt::StringLiterals::operator""_s;

namespace {

constexpr auto k_deviceName = "Surface Dial System Multi Axis";
// The dial's button
constexpr int k_button = BTN_0;
// Tries after the node appears, while udev hasn't given us access yet
constexpr int k_maxRetries = 10;

QString nameOf(const QString& node) {
    QFile file(u"/sys/class/input/"_s + node + u"/device/name"_s);
    if (!file.open(QIODevice::ReadOnly)) {
        return {};
    }
    return QString::fromUtf8(file.readAll()).trimmed();
}

} // namespace

SurfaceDial* SurfaceDial::instance() {
    static SurfaceDial s_instance;
    return &s_instance;
}

SurfaceDial* SurfaceDial::create(QQmlEngine* engine, QJSEngine* jsEngine) {
    Q_UNUSED(engine);
    Q_UNUSED(jsEngine);

    QQmlEngine::setObjectOwnership(instance(), QQmlEngine::CppOwnership);
    return instance();
}

SurfaceDial::SurfaceDial(QObject* parent)
    : QObject(parent)
    , m_rescan(new QTimer(this)) {
    m_rescan->setSingleShot(true);
    m_rescan->setInterval(300);
    connect(m_rescan, &QTimer::timeout, this, &SurfaceDial::scan);
}

SurfaceDial::~SurfaceDial() {
    close();
    if (m_wheelFd >= 0) {
        ioctl(m_wheelFd, UI_DEV_DESTROY);
        ::close(m_wheelFd);
    }
}

bool SurfaceDial::enabled() const {
    return m_enabled;
}

void SurfaceDial::setEnabled(bool enabled) {
    if (m_enabled == enabled) {
        return;
    }
    m_enabled = enabled;
    emit enabledChanged();

    if (enabled) {
        // New nodes under /dev/input: the dial waking up (or anything else)
        m_watcher = new QFileSystemWatcher({ u"/dev/input"_s }, this);
        connect(m_watcher, &QFileSystemWatcher::directoryChanged, this, [this] {
            if (m_fd < 0) {
                m_retries = 0;
                m_rescan->start();
            }
        });
        scan();
    } else {
        delete m_watcher;
        m_watcher = nullptr;
        m_rescan->stop();
        close();
        setError({});
    }
}

bool SurfaceDial::connected() const {
    return m_fd >= 0;
}

QString SurfaceDial::error() const {
    return m_error;
}

void SurfaceDial::setError(const QString& error) {
    if (m_error != error) {
        m_error = error;
        emit errorChanged();
    }
}

void SurfaceDial::scan() {
    if (!m_enabled || m_fd >= 0) {
        return;
    }

    const auto nodes = QDir(u"/sys/class/input"_s).entryList({ u"event*"_s }, QDir::Dirs | QDir::System);
    for (const auto& node : nodes) {
        if (nameOf(node) == QLatin1StringView(k_deviceName)) {
            if (open(node)) {
                return;
            }
            // There, but not ours yet (udev still applying uaccess): look again
            if (++m_retries <= k_maxRetries) {
                m_rescan->start();
            }
            return;
        }
    }
}

bool SurfaceDial::open(const QString& node) {
    const auto path = (u"/dev/input/"_s + node).toLocal8Bit();
    const int fd = ::open(path.constData(), O_RDONLY | O_NONBLOCK | O_CLOEXEC);
    if (fd < 0) {
        const int err = errno;
        setError(err == EACCES ? u"No access to %1: is the udev rule installed?"_s.arg(QString::fromLocal8Bit(path))
                               : QString::fromLocal8Bit(std::strerror(err)));
        return false;
    }

    // Ours alone: otherwise libinput turns rotation into scrolling as well
    if (ioctl(fd, EVIOCGRAB, 1) < 0) {
        qCWarning(lcDial) << "Couldn't grab the dial (another program has it?):" << std::strerror(errno);
        setError(u"Another program is using the dial"_s);
        ::close(fd);
        return false;
    }

    m_fd = fd;
    m_notifier = new QSocketNotifier(fd, QSocketNotifier::Read, this);
    connect(m_notifier, &QSocketNotifier::activated, this, &SurfaceDial::readEvents);

    qCInfo(lcDial) << "Surface Dial connected at" << QString::fromLocal8Bit(path);
    setError({});
    emit connectedChanged();
    return true;
}

void SurfaceDial::close() {
    if (m_fd < 0) {
        return;
    }
    delete m_notifier;
    m_notifier = nullptr;
    ioctl(m_fd, EVIOCGRAB, 0);
    ::close(m_fd);
    m_fd = -1;
    qCInfo(lcDial) << "Surface Dial disconnected";
    emit connectedChanged();
}

void SurfaceDial::readEvents() {
    input_event events[64];
    for (;;) {
        const auto n = ::read(m_fd, events, sizeof(events));
        if (n < 0) {
            if (errno == EAGAIN || errno == EINTR) {
                return;
            }
            // ENODEV: the dial went to sleep or away
            close();
            return;
        }
        if (n == 0) {
            close();
            return;
        }

        const auto count = static_cast<size_t>(n) / sizeof(input_event);
        for (size_t i = 0; i < count; ++i) {
            const auto& ev = events[i];
            if (ev.type == EV_REL && ev.code == REL_DIAL && ev.value != 0) {
                emit rotated(ev.value);
            } else if (ev.type == EV_KEY && ev.code == k_button) {
                if (ev.value == 1) {
                    emit pressed();
                } else if (ev.value == 0) {
                    emit released();
                }
            }
        }
    }
}

bool SurfaceDial::ensureWheel() {
    if (m_wheelFd >= 0) {
        return true;
    }
    if (m_wheelFailed) {
        return false;
    }

    const int fd = ::open("/dev/uinput", O_WRONLY | O_NONBLOCK | O_CLOEXEC);
    if (fd < 0) {
        qCWarning(lcDial) << "No virtual wheel: can't open /dev/uinput:" << std::strerror(errno);
        m_wheelFailed = true;
        return false;
    }

    uinput_setup setup {};
    setup.id.bustype = BUS_VIRTUAL;
    setup.id.vendor = 0x045e; // Microsoft, like the dial
    setup.id.product = 0x091b;
    std::strncpy(setup.name, "Caelestia Surface Dial wheel", UINPUT_MAX_NAME_SIZE - 1);

    const bool ok = ioctl(fd, UI_SET_EVBIT, EV_REL) == 0 && ioctl(fd, UI_SET_RELBIT, REL_WHEEL) == 0 &&
                    ioctl(fd, UI_SET_RELBIT, REL_WHEEL_HI_RES) == 0 && ioctl(fd, UI_DEV_SETUP, &setup) == 0 &&
                    ioctl(fd, UI_DEV_CREATE) == 0;
    if (!ok) {
        qCWarning(lcDial) << "No virtual wheel: uinput setup failed:" << std::strerror(errno);
        ::close(fd);
        m_wheelFailed = true;
        return false;
    }

    m_wheelFd = fd;
    return true;
}

void SurfaceDial::scroll(int notches) {
    if (notches == 0 || !ensureWheel()) {
        return;
    }

    const auto event = [](unsigned short type, unsigned short code, int value) {
        input_event ev {};
        ev.type = type;
        ev.code = code;
        ev.value = value;
        return ev;
    };
    const input_event events[] = {
        event(EV_REL, REL_WHEEL, notches),
        event(EV_REL, REL_WHEEL_HI_RES, notches * 120),
        event(EV_SYN, SYN_REPORT, 0),
    };
    if (::write(m_wheelFd, events, sizeof(events)) < 0) {
        qCWarning(lcDial) << "Virtual wheel write failed:" << std::strerror(errno);
    }
}

} // namespace caelestia::services
