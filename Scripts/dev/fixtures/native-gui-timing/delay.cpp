// One explicit control only. The helper preempts a runnable GUI; it never
// fabricates an idle wait by sleeping the subject before an already-ready poll.
#include <dlfcn.h>
#include <poll.h>
#include <signal.h>
#include <sys/socket.h>
#include <sys/syscall.h>
#include <sys/un.h>
#include <unistd.h>
#include <cstdlib>
#include <cstring>
#include <cstdio>

static void preemptReady(pollfd *fds, nfds_t count, bool permitted) {
    const char *flag = getenv("READY_POLL_CONTROL");
    if (getpid() != syscall(SYS_gettid) || !flag || strcmp(flag, "1")) return;
    const bool ready = !strcmp(getenv("READY_POLL_MODE"), "ready");
    if (count != 1 || (syscall(SYS_poll, fds, count, 0) > 0) != ready || !permitted) _exit(94);
    const int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    sockaddr_un address{};
    address.sun_family = AF_UNIX;
    const char *path = getenv("READY_POLL_SOCKET");
    if (!path || strlen(path) >= sizeof(address.sun_path)) _exit(95);
    strcpy(address.sun_path, path);
    if (connect(fd, reinterpret_cast<sockaddr *>(&address), sizeof(address))) _exit(96);
    char message[48], ancillary[CMSG_SPACE(sizeof(int))]{};
    const int length = snprintf(message, sizeof(message), "%d\n", getpid());
    iovec vector{message, size_t(length)};
    msghdr header{};
    header.msg_iov = &vector;
    header.msg_iovlen = 1;
    header.msg_control = ancillary;
    header.msg_controllen = sizeof(ancillary);
    cmsghdr *right = CMSG_FIRSTHDR(&header);
    right->cmsg_level = SOL_SOCKET;
    right->cmsg_type = SCM_RIGHTS;
    right->cmsg_len = CMSG_LEN(sizeof(int));
    memcpy(CMSG_DATA(right), &fds[0].fd, sizeof(int));
    if (sendmsg(fd, &header, 0) != length) _exit(97);
    close(fd);
}
extern "C" int poll(pollfd *fds, nfds_t count, int timeout) {
    static auto next = reinterpret_cast<int (*)(pollfd *, nfds_t, int)>(dlsym(RTLD_NEXT, "poll"));
    preemptReady(fds, count, timeout > 0);
    return next(fds, count, timeout);
}
extern "C" int ppoll(pollfd *fds, nfds_t count, const timespec *timeout, const sigset_t *mask) {
    static auto next = reinterpret_cast<int (*)(pollfd *, nfds_t, const timespec *, const sigset_t *)>(dlsym(RTLD_NEXT, "ppoll"));
    preemptReady(fds, count, !timeout || timeout->tv_sec || timeout->tv_nsec);
    return next(fds, count, timeout, mask);
}
