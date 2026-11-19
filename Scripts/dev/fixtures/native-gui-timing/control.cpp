#include <QQmlExtensionPlugin>
#include <qqml.h>
#include <QVariantMap>
#include <poll.h>
#include <sys/eventfd.h>
#include <time.h>
#include <unistd.h>

static qint64 now(clockid_t clock) {
    timespec value{};
    clock_gettime(clock, &value);
    return value.tv_sec * 1000000000LL + value.tv_nsec;
}
class ReadyControl : public QObject {
    Q_OBJECT
public:
    Q_INVOKABLE QVariantMap run(bool usePpoll, bool ready) {
        const int fd = eventfd(ready ? 1 : 0, EFD_NONBLOCK | EFD_CLOEXEC);
        if (fd < 0) qFatal("control eventfd creation failed");
        pollfd descriptor{fd, POLLIN, 0};
        qputenv("READY_POLL_CONTROL", "1");
        const auto wall = now(CLOCK_MONOTONIC), cpu = now(CLOCK_THREAD_CPUTIME_ID);
        const timespec timeout{1, 0};
        const int result = usePpoll ? ::ppoll(&descriptor, 1, &timeout, nullptr) : ::poll(&descriptor, 1, 1000);
        const auto end = now(CLOCK_MONOTONIC), cpuEnd = now(CLOCK_THREAD_CPUTIME_ID);
        qunsetenv("READY_POLL_CONTROL");
        close(fd);
        return {{"beginNs", QString::number(wall)}, {"endNs", QString::number(end)},
                {"wallMs", (end-wall)/1e6}, {"cpuMs", (cpuEnd-cpu)/1e6},
                {"result", result}, {"ready", bool(descriptor.revents & POLLIN)}};
    }
};
class ReadyPlugin : public QQmlExtensionPlugin {
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)
public:
    void registerTypes(const char *uri) override { qmlRegisterType<ReadyControl>(uri, 1, 0, "ReadyControl"); }
};
#include "control.moc"
