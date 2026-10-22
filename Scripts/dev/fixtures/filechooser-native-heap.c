#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <inttypes.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>

/* Test-subject-only checkpoint observer. No allocation interposition or
 * periodic sampling: one fixed-buffer response after an explicit idle GC. */
typedef int (*mallctl_fn)(const char *, void *, size_t *, void *, size_t);
typedef void *(*mallocx_fn)(size_t, int);
typedef void (*dallocx_fn)(void *, int);
static int listener = -1;
static pthread_t worker;
static void *held;
static const size_t canary_bytes = 2 * 1024 * 1024;

static int read_stats(uint64_t *allocated, uint64_t *active,
                      uint64_t *resident, const char **version) {
    mallctl_fn ctl = (mallctl_fn)dlsym(RTLD_DEFAULT, "mallctl");
    if (!ctl) return ENOSYS;
    uint64_t epoch = 1;
    size_t length = sizeof(epoch);
    int error = ctl("epoch", &epoch, &length, &epoch, sizeof(epoch));
    if (error) return error;
    const char *names[] = {"stats.allocated", "stats.active", "stats.resident"};
    uint64_t *values[] = {allocated, active, resident};
    for (size_t i = 0; i < 3; ++i) {
        size_t value = 0;
        length = sizeof(value);
        error = ctl(names[i], &value, &length, NULL, 0);
        if (error) return error;
        *values[i] = value;
    }
    length = sizeof(*version);
    return ctl("version", version, &length, NULL, 0);
}

static void *serve(void *unused) {
    (void)unused;
    for (;;) {
        int client = accept4(listener, NULL, NULL, SOCK_CLOEXEC);
        if (client < 0) {
            if (errno == EINTR) continue;
            return NULL;
        }
        char command = 0;
        int error = read(client, &command, 1) == 1 ? 0 : EIO;
        if (!error && command == 'A') {
            mallocx_fn allocate = (mallocx_fn)dlsym(RTLD_DEFAULT, "mallocx");
            if (!allocate || held) error = EINVAL;
            else {
                held = allocate(canary_bytes, 0);
                if (!held) error = ENOMEM;
                else memset(held, 0x5a, canary_bytes);
            }
        } else if (!error && command == 'F') {
            dallocx_fn release = (dallocx_fn)dlsym(RTLD_DEFAULT, "dallocx");
            if (!release || !held) error = EINVAL;
            else { release(held, 0); held = NULL; }
        } else if (!error && command != 'S') error = EINVAL;
        uint64_t allocated = 0, active = 0, resident = 0;
        const char *version = "";
        if (!error) error = read_stats(&allocated, &active, &resident, &version);
        char response[1024];
        int length = snprintf(response, sizeof(response),
            "{\"error\":%d,\"pid\":%ld,\"exec_env_cleared\":%s,\"allocated_bytes\":%" PRIu64
            ",\"active_bytes\":%" PRIu64 ",\"resident_bytes\":%" PRIu64
            ",\"canary_held\":%s,\"allocator_version\":\"%s\"}\n",
            error, (long)getpid(), (!getenv("LD_PRELOAD") && !getenv("FILECHOOSER_NATIVE_SOCKET")) ? "true" : "false",
            allocated, active, resident, held ? "true" : "false", version);
        if (length > 0 && (size_t)length < sizeof(response)) {
            size_t offset = 0;
            while (offset < (size_t)length) {
                ssize_t count = send(client, response + offset, length - offset, MSG_NOSIGNAL);
                if (count < 0 && errno == EINTR) continue;
                if (count <= 0) break;
                offset += (size_t)count;
            }
        }
        /* EOF proves this accepted FD was closed before the caller meters FDs. */
        close(client);
    }
}

__attribute__((constructor)) static void start_observer(void) {
    const char *path = getenv("FILECHOOSER_NATIVE_SOCKET");
    if (!path) return;
    struct sockaddr_un address = {.sun_family = AF_UNIX};
    if (strlen(path) >= sizeof(address.sun_path)) _exit(90);
    strcpy(address.sun_path, path);
    /* Qt's child helpers must not start another observer at this socket. */
    unsetenv("LD_PRELOAD");
    unsetenv("FILECHOOSER_NATIVE_SOCKET");
    listener = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (listener < 0) _exit(91);
    unlink(address.sun_path);
    if (bind(listener, (struct sockaddr *)&address, sizeof(address)) ||
        chmod(address.sun_path, 0600) || listen(listener, 4) ||
        pthread_create(&worker, NULL, serve, NULL)) _exit(92);
}

__attribute__((destructor)) static void stop_observer(void) {
    if (listener < 0) return;
    shutdown(listener, SHUT_RDWR);
    close(listener);
    pthread_join(worker, NULL);
}
