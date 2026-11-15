// Guest-only workload timestamps, on the native trace / evdev monotonic clock.
#include <QQmlExtensionPlugin>
#include <qqml.h>
#include <time.h>

class TimingClock : public QObject {
    Q_OBJECT
public:
    Q_INVOKABLE QString nowNs() const {
        timespec value{};
        if (clock_gettime(CLOCK_MONOTONIC, &value)) qFatal("monotonic clock failed");
        return QString::number(value.tv_sec * 1000000000LL + value.tv_nsec);
    }
};
class TimingPlugin : public QQmlExtensionPlugin {
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)
public:
    void registerTypes(const char *uri) override { qmlRegisterType<TimingClock>(uri, 1, 0, "TimingClock"); }
};
#include "clock.moc"
