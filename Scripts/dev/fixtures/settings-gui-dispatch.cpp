// Guest-only native dispatcher/poll coverage, based on the I1 instrument.
// Ready/nonblocking batches do not split a continuous busy span.
#include "settings-gui-log.hpp"
#include <dlfcn.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>
#include <cstdio>
#include <cstdlib>

static int traceFd = -1;
static thread_local int depth;
static thread_local bool tracing;
static long long clockNs(clockid_t clock) {
    timespec t{};
    clock_gettime(clock, &t);
    return t.tv_sec * 1000000000LL + t.tv_nsec;
}
static bool mainThread() { return syscall(SYS_gettid) == getpid(); }
static void record(char kind, int arg = 0) {
    if (traceFd < 0 || tracing || !mainThread()) return;
    tracing = true;
    char line[160];
    const int n = snprintf(line, sizeof line, "%c %d %ld %lld %lld %d\n", kind,
                           getpid(), syscall(SYS_gettid), clockNs(CLOCK_MONOTONIC),
                           clockNs(CLOCK_THREAD_CPUTIME_ID), arg);
    if (n <= 0 || n >= int(sizeof line)) _exit(93);
    settingsGuiLogAppend(0, line, n);
    tracing = false;
}
__attribute__((constructor)) static void init() {
    if (const char *path = getenv("ATMOSPHERA_GUI_TRACE"))
        traceFd = 0;
    record('I');
}
using Dispatcher = bool (*)(void *, int);
static bool dispatch(const char *symbol, void *self, int flags, int kind) {
    auto next = reinterpret_cast<Dispatcher>(dlsym(RTLD_NEXT, symbol));
    if (!next) _exit(92);
    if (depth++ == 0) record('E', kind);
    const bool result = next(self, flags);
    if (--depth == 0) record('X', kind);
    return result;
}
extern "C" bool glibEvents(void *, int) asm("_ZN20QEventDispatcherGlib13processEventsE6QFlagsIN10QEventLoop17ProcessEventsFlagEE");
extern "C" bool glibEvents(void *self, int flags) {
    return dispatch("_ZN20QEventDispatcherGlib13processEventsE6QFlagsIN10QEventLoop17ProcessEventsFlagEE", self, flags, 1);
}
extern "C" bool unixEvents(void *, int) asm("_ZN20QEventDispatcherUNIX13processEventsE6QFlagsIN10QEventLoop17ProcessEventsFlagEE");
extern "C" bool unixEvents(void *self, int flags) {
    return dispatch("_ZN20QEventDispatcherUNIX13processEventsE6QFlagsIN10QEventLoop17ProcessEventsFlagEE", self, flags, 2);
}
extern "C" int poll(pollfd *fds, nfds_t count, int timeout) {
    static auto next = reinterpret_cast<int (*)(pollfd *, nfds_t, int)>(dlsym(RTLD_NEXT, "poll"));
    const bool active = depth && mainThread();
    if (active) record(timeout ? 'W' : 'P', timeout);
    const int result = next(fds, count, timeout);
    if (active) record(timeout ? 'R' : 'Q', result);
    return result;
}
extern "C" int ppoll(pollfd *fds, nfds_t count, const timespec *timeout, const sigset_t *mask) {
    static auto next = reinterpret_cast<int (*)(pollfd *, nfds_t, const timespec *, const sigset_t *)>(dlsym(RTLD_NEXT, "ppoll"));
    const bool active = depth && mainThread();
    const bool blocking = !timeout || timeout->tv_sec || timeout->tv_nsec;
    if (active) record(blocking ? 'W' : 'P', 2);
    const int result = next(fds, count, timeout, mask);
    if (active) record(blocking ? 'R' : 'Q', result);
    return result;
}
