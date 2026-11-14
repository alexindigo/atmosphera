// Guest-only capture: no opens, writes, closes or queue waits in GUI callbacks.
#include "settings-gui-log.hpp"
#include <atomic>
#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <pthread.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>

namespace {
constexpr size_t capacity = 32768, payload = 1024, block = 65536;
struct Item { int sink; size_t bytes; char data[payload]; };
Item queue[capacity];
std::atomic<size_t> published{}, consumed{};
std::atomic<bool> ready{}, closing{};
pthread_t writer;
bool active = false;
size_t peak = 0, records[3]{}, bytes[3]{};
const char *paths[3]{};

void writeAll(int fd, const char *data, size_t count) {
    while (count) {
        const auto n = syscall(SYS_write, fd, data, count);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) _exit(113);
        data += n;
        count -= n;
    }
}

void *drain(void *) {
    pthread_setname_np(pthread_self(), "gui-trace-drain");
    int fds[3]{-1, -1, -1};
    size_t used[3]{};
    char buffers[3][block];
    for (int i = 0; i < 3; ++i) {
        if (!paths[i]) continue;
        fds[i] = open(paths[i], O_WRONLY | O_CREAT | O_APPEND, 0600);
        if (fds[i] < 0) _exit(114);
    }
    ready.store(true, std::memory_order_release);
    auto flush = [&](int sink) {
        if (used[sink]) writeAll(fds[sink], buffers[sink], used[sink]);
        used[sink] = 0;
    };
    size_t cursor = 0;
    while (!closing.load(std::memory_order_acquire) || cursor < published.load(std::memory_order_acquire)) {
        const auto available = published.load(std::memory_order_acquire);
        while (cursor < available) {
            auto &item = queue[cursor % capacity];
            const int sink = item.sink;
            if (fds[sink] < 0) _exit(115);
            if (used[sink] + item.bytes > block) flush(sink);
            memcpy(buffers[sink] + used[sink], item.data, item.bytes);
            used[sink] += item.bytes;
            bytes[sink] += item.bytes;
            records[sink]++;
            consumed.store(++cursor, std::memory_order_release);
        }
        for (int i = 0; i < 3; ++i) flush(i);
        if (cursor == published.load(std::memory_order_acquire)) {
            timespec delay{0, 1000000};
            nanosleep(&delay, nullptr);
        }
    }
    for (int i = 0; i < 3; ++i) {
        flush(i);
        if (fds[i] >= 0 && close(fds[i])) _exit(116);
    }
    if (paths[0]) {
        char name[2048];
        const int length = snprintf(name, sizeof name, "%s.async-%d.json", paths[0], getpid());
        if (length < 0 || length >= int(sizeof name)) _exit(117);
        const int fd = open(name, O_WRONLY | O_CREAT | O_EXCL, 0600);
        if (fd < 0) _exit(117);
        char text[1024];
        const int n = snprintf(text, sizeof text,
            "{\"pid\":%d,\"published\":%zu,\"drained\":%zu,\"queuePeak\":%zu,\"capacity\":%zu,\"dropped\":0,"
            "\"traceRecords\":%zu,\"scopeRecords\":%zu,\"diagnosticRecords\":%zu,"
            "\"traceBytes\":%zu,\"scopeBytes\":%zu,\"diagnosticBytes\":%zu}\n",
            getpid(), published.load(), cursor, peak, capacity,
            records[0], records[1], records[2], bytes[0], bytes[1], bytes[2]);
        if (n < 0 || n >= int(sizeof text)) _exit(117);
        writeAll(fd, text, n);
        if (close(fd)) _exit(116);
    }
    return nullptr;
}

__attribute__((constructor(150))) void initialize() {
    paths[0] = getenv("ATMOSPHERA_GUI_TRACE");
    paths[1] = getenv("ATMOSPHERA_SETTINGS_SCOPES");
    paths[2] = getenv("ATMOSPHERA_IO_TRACE");
    if (!paths[0] && !paths[1] && !paths[2]) return;
    char executable[1024]{};
    if (readlink("/proc/self/exe", executable, sizeof executable - 1) < 0) _exit(118);
    const char *base = strrchr(executable, '/');
    base = base ? base + 1 : executable;
    // LD_PRELOAD may also reach timeout or QProcess children: they do not own capture.
    active = strcmp(base, "quickshell") == 0 || strcmp(base, "qs") == 0;
    if (!active) return;
    memset(queue, 0, sizeof queue); // Prefault before any measured event-loop work.
    if (pthread_create(&writer, nullptr, drain, nullptr)) _exit(119);
    while (!ready.load(std::memory_order_acquire)) {
        timespec delay{0, 1000000};
        nanosleep(&delay, nullptr);
    }
}

__attribute__((destructor)) void finish() {
    if (!active) return;
    closing.store(true, std::memory_order_release);
    if (pthread_join(writer, nullptr)) _exit(120);
}
}

void settingsGuiLogAppend(int sink, const char *data, size_t count) {
    if (!active) return;
    if (sink < 0 || sink > 2 || !paths[sink] || count > payload) _exit(121);
    const auto head = published.load(std::memory_order_relaxed);
    const auto tail = consumed.load(std::memory_order_acquire);
    // A finite preallocated queue must invalidate overflow, never block or drop GUI records.
    if (head - tail >= capacity) _exit(122);
    if (head - tail + 1 > peak) peak = head - tail + 1;
    auto &item = queue[head % capacity];
    item.sink = sink;
    item.bytes = count;
    memcpy(item.data, data, count);
    published.store(head + 1, std::memory_order_release);
}
