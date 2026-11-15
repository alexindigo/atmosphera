// Test-only in-process clocks: exclude scheduler/render waits without sampling
// another process or adding work to every pointer event.
#include <QObject>
#include <QQmlExtensionPlugin>
#include <qqml.h>
#include <time.h>

class FrameClock : public QObject {
    Q_OBJECT
public:
    explicit FrameClock(QObject *parent = nullptr) : QObject(parent) {}
    Q_INVOKABLE double cpuMs() const { return milliseconds(CLOCK_THREAD_CPUTIME_ID); }
    Q_INVOKABLE double wallMs() const { return milliseconds(CLOCK_REALTIME); }
private:
    static double milliseconds(clockid_t id) {
        timespec value{};
        if (clock_gettime(id, &value)) qFatal("frame clock unavailable");
        return double(value.tv_sec) * 1000 + double(value.tv_nsec) / 1000000;
    }
};

class FrameClockPlugin : public QQmlExtensionPlugin {
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)
public:
    void registerTypes(const char *uri) override { qmlRegisterType<FrameClock>(uri, 1, 0, "FrameClock"); }
};
#include "filechooser-frame-clock.moc"
