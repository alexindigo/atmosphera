/* Guest-only opaque lock fixture. Delay surfaces, never authentication.
 * Protocol: wayland-protocols/staging/ext-session-lock/ext-session-lock-v1.xml.
 * Registry/keyboard/PAM reference: ~/Sources/swaywm-swaylock/{main,seat,pam}.c.
 * No owner handshake and no synthetic secure/authentication publication.
 */
#define _GNU_SOURCE
#include <assert.h>
#include <fcntl.h>
#include <poll.h>
#include <security/pam_appl.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#include <wayland-client.h>
#include <xkbcommon/xkbcommon.h>
#include "session-lock-client.h"

static struct wl_display *display;
static struct wl_compositor *compositor;
static struct wl_shm *shm;
static struct ext_session_lock_manager_v1 *manager;
static struct ext_session_lock_v1 *lock;
static struct wl_output *outputs[16];
static unsigned output_count;
static struct xkb_context *xkb;
static struct xkb_state *keys;
static bool secure, authenticated, mapped;
static char password[256];
static size_t password_length;

static void event(const char *name) {
    struct timespec now;
    assert(clock_gettime(CLOCK_MONOTONIC, &now) == 0);
    printf("{\"event\":\"%s\",\"monotonic\":%.9f}\n", name,
        now.tv_sec + now.tv_nsec / 1e9);
    fflush(stdout);
}

static int converse(int count, const struct pam_message **messages,
        struct pam_response **responses, void *data) {
    (void)data;
    struct pam_response *reply = calloc(count, sizeof(*reply));
    if (!reply) return PAM_BUF_ERR;
    for (int i = 0; i < count; i++) {
        int style = messages[i]->msg_style;
        if (style == PAM_PROMPT_ECHO_OFF) reply[i].resp = strdup(password);
        else if (style == PAM_PROMPT_ECHO_ON) reply[i].resp = strdup(getenv("USER"));
        else if (style != PAM_TEXT_INFO && style != PAM_ERROR_MSG) {
            for (int j = 0; j < i; j++) free(reply[j].resp);
            free(reply);
            return PAM_CONV_ERR;
        }
    }
    *responses = reply;
    return PAM_SUCCESS;
}

static void keymap(void *data, struct wl_keyboard *keyboard, uint32_t format,
        int32_t fd, uint32_t size) {
    (void)data; (void)keyboard;
    assert(format == WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1);
    char *map = mmap(NULL, size, PROT_READ, MAP_PRIVATE, fd, 0);
    assert(map != MAP_FAILED);
    struct xkb_keymap *keymap = xkb_keymap_new_from_string(xkb, map,
        XKB_KEYMAP_FORMAT_TEXT_V1, XKB_KEYMAP_COMPILE_NO_FLAGS);
    assert(keymap);
    xkb_state_unref(keys);
    keys = xkb_state_new(keymap);
    assert(keys);
    xkb_keymap_unref(keymap);
    munmap(map, size);
    close(fd);
}
static void enter(void *d, struct wl_keyboard *k, uint32_t s, struct wl_surface *w, struct wl_array *a) {
    (void)d; (void)k; (void)s; (void)w; (void)a;
    event("keyboard-focus");
}
static void leave(void *d, struct wl_keyboard *k, uint32_t s, struct wl_surface *w) {
    (void)d; (void)k; (void)s; (void)w;
}
static void modifiers(void *d, struct wl_keyboard *k, uint32_t s,
        uint32_t depressed, uint32_t latched, uint32_t locked, uint32_t group) {
    (void)d; (void)k; (void)s;
    if (keys) xkb_state_update_mask(keys, depressed, latched, locked, 0, 0, group);
}
static void key(void *d, struct wl_keyboard *k, uint32_t serial, uint32_t time,
        uint32_t code, uint32_t state) {
    (void)d; (void)k; (void)serial; (void)time;
    if (!keys || !secure || state != WL_KEYBOARD_KEY_STATE_PRESSED) return;
    xkb_keysym_t sym = xkb_state_key_get_one_sym(keys, code + 8);
    if (sym == XKB_KEY_Return) {
        pam_handle_t *handle = NULL;
        struct pam_conv conversation = {converse, NULL};
        int result = pam_start("login", getenv("USER"), &conversation, &handle);
        if (result == PAM_SUCCESS) result = pam_authenticate(handle, 0);
        if (handle) pam_end(handle, result);
        explicit_bzero(password, sizeof(password));
        password_length = 0;
        event(result == PAM_SUCCESS ? "pam-success" : "pam-failure");
        authenticated = result == PAM_SUCCESS;
    } else if (sym == XKB_KEY_BackSpace) {
        if (password_length) password[--password_length] = 0;
    } else {
        uint32_t value = xkb_state_key_get_utf32(keys, code + 8);
        if (value >= 32 && value < 127 && password_length < sizeof(password) - 1)
            password[password_length++] = value;
    }
}
static const struct wl_keyboard_listener keyboard_listener = {
    .keymap = keymap, .enter = enter, .leave = leave, .key = key, .modifiers = modifiers,
};
static void capabilities(void *d, struct wl_seat *seat, uint32_t flags) {
    (void)d;
    if (flags & WL_SEAT_CAPABILITY_KEYBOARD)
        wl_keyboard_add_listener(wl_seat_get_keyboard(seat), &keyboard_listener, NULL);
}
static const struct wl_seat_listener seat_listener = {.capabilities = capabilities};
static void global(void *d, struct wl_registry *registry, uint32_t name,
        const char *interface, uint32_t version) {
    (void)d; (void)version;
    if (!strcmp(interface, "wl_compositor")) compositor = wl_registry_bind(registry, name, &wl_compositor_interface, 1);
    else if (!strcmp(interface, "wl_shm")) shm = wl_registry_bind(registry, name, &wl_shm_interface, 1);
    else if (!strcmp(interface, "wl_seat")) {
        struct wl_seat *seat = wl_registry_bind(registry, name, &wl_seat_interface, 1);
        wl_seat_add_listener(seat, &seat_listener, NULL);
    } else if (!strcmp(interface, "wl_output")) {
        assert(output_count < 16);
        outputs[output_count++] = wl_registry_bind(registry, name, &wl_output_interface, 1);
    } else if (!strcmp(interface, ext_session_lock_manager_v1_interface.name))
        manager = wl_registry_bind(registry, name, &ext_session_lock_manager_v1_interface, 1);
}
static void removed(void *d, struct wl_registry *r, uint32_t n) {(void)d; (void)r; (void)n;}
static const struct wl_registry_listener registry_listener = {.global = global, .global_remove = removed};
static void locked(void *d, struct ext_session_lock_v1 *l) {(void)d; (void)l; secure = true; event("locked");}
static void finished(void *d, struct ext_session_lock_v1 *l) {(void)d; (void)l; event("finished"); exit(2);}
static const struct ext_session_lock_v1_listener lock_listener = {.locked = locked, .finished = finished};
static void configure(void *data, struct ext_session_lock_surface_v1 *surface,
        uint32_t serial, uint32_t width, uint32_t height) {
    assert(width && height && width <= 8192 && height <= 8192);
    size_t size = (size_t)width * height * 4;
    int fd = memfd_create("locker-opaque-surface", MFD_CLOEXEC);
    assert(fd >= 0 && ftruncate(fd, size) == 0);
    uint32_t *pixels = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    assert(pixels != MAP_FAILED);
    for (size_t i = 0; i < size / 4; i++) pixels[i] = 0xff101820;
    struct wl_shm_pool *pool = wl_shm_create_pool(shm, fd, size);
    struct wl_buffer *buffer = wl_shm_pool_create_buffer(pool, 0, width, height, width * 4, WL_SHM_FORMAT_XRGB8888);
    ext_session_lock_surface_v1_ack_configure(surface, serial);
    wl_surface_attach(data, buffer, 0, 0);
    wl_surface_damage(data, 0, 0, width, height);
    wl_surface_commit(data);
    wl_shm_pool_destroy(pool);
    munmap(pixels, size);
    close(fd);
    event("surface-committed");
}
static const struct ext_session_lock_surface_v1_listener surface_listener = {.configure = configure};

int main(int argc, char **argv) {
    assert(argc == 2 && getenv("USER"));
    display = wl_display_connect(NULL);
    assert(display);
    xkb = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
    assert(xkb);
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    assert(wl_display_roundtrip(display) >= 0);
    assert(manager && compositor && shm && output_count);
    lock = ext_session_lock_manager_v1_lock(manager);
    ext_session_lock_v1_add_listener(lock, &lock_listener, NULL);
    assert(wl_display_flush(display) >= 0);
    event("requested-without-surfaces");
    while (!authenticated) {
        assert(wl_display_dispatch_pending(display) >= 0);
        if (!mapped && access(argv[1], F_OK) == 0) {
            for (unsigned i = 0; i < output_count; i++) {
                struct wl_surface *surface = wl_compositor_create_surface(compositor);
                struct ext_session_lock_surface_v1 *role = ext_session_lock_v1_get_lock_surface(lock, surface, outputs[i]);
                ext_session_lock_surface_v1_add_listener(role, &surface_listener, surface);
            }
            mapped = true;
        }
        assert(wl_display_flush(display) >= 0);
        struct pollfd descriptor = {wl_display_get_fd(display), POLLIN, 0};
        int ready = poll(&descriptor, 1, 20);
        assert(ready >= 0);
        if (ready) assert(wl_display_dispatch(display) >= 0);
    }
    assert(secure);
    event("authenticated-unlock");
    ext_session_lock_v1_unlock_and_destroy(lock);
    assert(wl_display_roundtrip(display) >= 0);
    wl_display_disconnect(display);
    return 0;
}
