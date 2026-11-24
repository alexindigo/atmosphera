// Test-only native I/O delay. Call the real fsync after one measured delay;
// never change the installed library, evidence bytes or durability outcome.
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

int fsync(int fd) {
    int (*actual)(int) = dlsym(RTLD_NEXT, "fsync");
    const char *marker = getenv("PHA_SYNC_MARKER");
    const char *milliseconds = getenv("PHA_SYNC_DELAY_MS");
    char link[64], path[4096];
    snprintf(link, sizeof(link), "/proc/self/fd/%d", fd);
    ssize_t length = readlink(link, path, sizeof(path) - 1);
    if (length > 0) {
        path[length] = 0;
        if (marker && milliseconds && strstr(path, "/cache/settings-conflicts/") &&
            length >= 6 && strcmp(path + length - 6, "/bytes") == 0 && unlink(marker) == 0) {
            long ms = strtol(milliseconds, NULL, 10);
            struct timespec now, delay = {ms / 1000, ms % 1000 * 1000000};
            clock_gettime(CLOCK_REALTIME, &now);
            fprintf(stderr, "PHA_SYNC_DELAY start=%lld.%09ld ms=%ld\n", (long long)now.tv_sec, now.tv_nsec, ms);
            while (nanosleep(&delay, &delay) != 0 && errno == EINTR) {}
            clock_gettime(CLOCK_REALTIME, &now);
            fprintf(stderr, "PHA_SYNC_DELAY end=%lld.%09ld\n", (long long)now.tv_sec, now.tv_nsec);
        }
    }
    return actual(fd);
}
