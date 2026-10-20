/* Test-only persistent keyboard for the private file chooser compositor.
 * Commands arrive over a private Unix socket; the Wayland keyboard, keymap
 * state and connection have one owner for the entire session. No evdev/uinput.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <poll.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>
#include <wayland-client.h>
#include <xkbcommon/xkbcommon.h>
#include <xkbcommon/xkbcommon-keysyms.h>
#include "virtual-keyboard-client.h"

static struct wl_display *display;
static struct wl_seat *seat;
static struct zwp_virtual_keyboard_manager_v1 *manager;
static struct zwp_virtual_keyboard_v1 *keyboard;
static struct xkb_context *context;
static struct xkb_keymap *base_map, *active_map;
static struct xkb_state *state;

static void fail(const char *message) {
    fprintf(stderr, "filechooser-input: %s (%s)\n", message, strerror(errno));
    exit(1);
}

static void global(void *data, struct wl_registry *registry, uint32_t name,
                   const char *interface, uint32_t version) {
    (void)data; (void)version;
    if (!strcmp(interface, "wl_seat") && !seat)
        seat = wl_registry_bind(registry, name, &wl_seat_interface, 1);
    else if (!strcmp(interface, "zwp_virtual_keyboard_manager_v1"))
        manager = wl_registry_bind(registry, name, &zwp_virtual_keyboard_manager_v1_interface, 1);
}

static void removed(void *data, struct wl_registry *registry, uint32_t name) {
    (void)data; (void)registry; (void)name;
}

static uint32_t milliseconds(void) {
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now)) fail("clock_gettime");
    return (uint32_t)((uint64_t)now.tv_sec * 1000 + now.tv_nsec / 1000000);
}

static void set_map(struct xkb_keymap *map) {
    if (map == active_map) return;
    char *text = xkb_keymap_get_as_string(map, XKB_KEYMAP_FORMAT_TEXT_V1);
    if (!text) fail("serialize keymap");
    char *path = NULL;
    if (!getenv("TMPDIR") || asprintf(&path, "%s/keyboard-keymap-XXXXXX", getenv("TMPDIR")) < 0)
        fail("disk-backed keymap path");
    int fd = mkstemp(path);
    if (fd < 0) fail("create keymap");
    if (unlink(path)) fail("unlink keymap");
    free(path);
    size_t size = strlen(text) + 1, offset = 0;
    while (offset < size) {
        ssize_t written = write(fd, text + offset, size - offset);
        if (written < 0 && errno == EINTR) continue;
        if (written <= 0) fail("write keymap");
        offset += (size_t)written;
    }
    zwp_virtual_keyboard_v1_keymap(keyboard, WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1, fd, (uint32_t)size);
    close(fd); free(text);
    if (state) xkb_state_unref(state);
    if (active_map) xkb_keymap_unref(active_map);
    active_map = xkb_keymap_ref(map);
    state = xkb_state_new(map);
    if (!state) fail("create keyboard state");
    zwp_virtual_keyboard_v1_modifiers(keyboard, 0, 0, 0, 0);
}

static void key(uint32_t code, uint32_t down) {
    xkb_state_update_key(state, code + 8, down ? XKB_KEY_DOWN : XKB_KEY_UP);
    zwp_virtual_keyboard_v1_modifiers(keyboard,
        xkb_state_serialize_mods(state, XKB_STATE_MODS_DEPRESSED),
        xkb_state_serialize_mods(state, XKB_STATE_MODS_LATCHED),
        xkb_state_serialize_mods(state, XKB_STATE_MODS_LOCKED),
        xkb_state_serialize_layout(state, XKB_STATE_LAYOUT_EFFECTIVE));
    zwp_virtual_keyboard_v1_key(keyboard, milliseconds(), code, down);
}

static bool keys(char *input) {
    unsigned codes[2048], values[2048];
    size_t count = 0;
    char *saved = NULL;
    for (char *token = strtok_r(input, " \n", &saved); token; token = strtok_r(NULL, " \n", &saved)) {
        char extra;
        if (count == 2048 || sscanf(token, "%u:%u%c", &codes[count], &values[count], &extra) != 2 ||
            codes[count] > 247 || values[count] > 1) return false;
        count++;
    }
    bool held[248] = {false};
    for (size_t i = 0; i < count; i++) {
        if (held[codes[i]] == (bool)values[i]) return false;
        held[codes[i]] = values[i];
    }
    memset(held, 0, sizeof(held));
    set_map(base_map);
    for (size_t i = 0; i < count; i++) {
        key(codes[i], values[i]);
        held[codes[i]] = values[i];
    }
    /* Match CLI input semantics: a command never leaves a modifier held. */
    for (unsigned i = 0; i < 248; i++) if (held[i]) key(i, 0);
    return true;
}

static bool text(char *input) {
    char *saved = NULL;
    for (char *token = strtok_r(input, " \n", &saved); token; token = strtok_r(NULL, " \n", &saved)) {
        char *end = NULL;
        unsigned long unicode = strtoul(token, &end, 16);
        if (!*token || *end || unicode > 0x10ffff || (unicode >= 0xd800 && unicode <= 0xdfff)) return false;
        xkb_keysym_t symbol = xkb_utf32_to_keysym((uint32_t)unicode);
        if (unicode == '\n' || unicode == '\r') symbol = XKB_KEY_Return;
        if (unicode == '\t') symbol = XKB_KEY_Tab;
        if (unicode == '\b') symbol = XKB_KEY_BackSpace;
        if (symbol == XKB_KEY_NoSymbol) return false;
        char *definition = NULL;
        if (asprintf(&definition, "xkb_keymap { xkb_keycodes { minimum=8; maximum=9; <TXT>=9; }; "
                     "xkb_types { type \"ONE_LEVEL\" { modifiers=None; level_name[Level1]=\"Any\"; }; }; "
                     "xkb_compatibility {}; xkb_symbols { key <TXT> { type=\"ONE_LEVEL\", [0x%08x] }; }; };", symbol) < 0)
            fail("text keymap allocation");
        struct xkb_keymap *map = xkb_keymap_new_from_string(context, definition, XKB_KEYMAP_FORMAT_TEXT_V1, XKB_KEYMAP_COMPILE_NO_FLAGS);
        free(definition);
        if (!map) return false;
        set_map(map);
        xkb_keymap_unref(map);
        key(1, 1); key(1, 0);
    }
    return true;
}

int main(int argc, char **argv) {
    if (argc != 2) fail("expected private socket path");
    const char *root = getenv("FILECHOOSER_ISOLATION");
    const char *runtime = getenv("XDG_RUNTIME_DIR");
    const char *own_namespace = getenv("FILECHOOSER_PID_NAMESPACE");
    const char *parent_namespace = getenv("FILECHOOSER_PARENT_PID_NAMESPACE");
    char actual_namespace[128];
    ssize_t namespace_size = readlink("/proc/self/ns/pid", actual_namespace, sizeof(actual_namespace) - 1);
    if (!root || !runtime || !own_namespace || !parent_namespace || namespace_size < 0)
        fail("requires the private session runner");
    actual_namespace[namespace_size] = '\0';
    if (strcmp(actual_namespace, own_namespace) || !strcmp(own_namespace, parent_namespace) ||
        !getenv("WAYLAND_DISPLAY") || strcmp(getenv("WAYLAND_DISPLAY"), "wayland-1") || getenv("WAYLAND_SOCKET"))
        fail("requires the private PID namespace and display");
    char *expected_runtime = NULL, *expected_socket = NULL;
    if (asprintf(&expected_runtime, "%s/run", root) < 0 || asprintf(&expected_socket, "%s/run/input.sock", root) < 0)
        fail("private endpoint allocation");
    if (strcmp(runtime, expected_runtime) || strcmp(argv[1], expected_socket)) fail("private endpoint mismatch");
    free(expected_runtime); free(expected_socket);
    display = wl_display_connect(NULL);
    if (!display) fail("connect private display");
    struct wl_registry *registry = wl_display_get_registry(display);
    const struct wl_registry_listener listener = {global, removed};
    wl_registry_add_listener(registry, &listener, NULL);
    if (wl_display_roundtrip(display) < 0 || !seat || !manager) fail("private keyboard protocol unavailable");
    keyboard = zwp_virtual_keyboard_manager_v1_create_virtual_keyboard(manager, seat);
    context = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
    if (!context) fail("create XKB context");
    const struct xkb_rule_names names = {.layout = "us"};
    base_map = xkb_keymap_new_from_names2(context, &names, XKB_KEYMAP_FORMAT_TEXT_V1, XKB_KEYMAP_COMPILE_NO_FLAGS);
    if (!base_map) fail("compile base keymap");
    set_map(base_map);
    if (wl_display_roundtrip(display) < 0) fail("publish initial keymap");

    struct sockaddr_un address = {.sun_family = AF_UNIX};
    if (strlen(argv[1]) >= sizeof(address.sun_path)) fail("private socket path too long");
    strcpy(address.sun_path, argv[1]);
    int server = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (server < 0 || bind(server, (struct sockaddr *)&address, sizeof(address)) || listen(server, 8)) fail("private input socket");
    struct pollfd fds[] = {{server, POLLIN, 0}, {wl_display_get_fd(display), POLLIN, 0}};
    bool stopping = false;
    while (!stopping) {
        if (wl_display_flush(display) < 0 && errno != EAGAIN) fail("flush keyboard");
        if (poll(fds, 2, -1) < 0) { if (errno == EINTR) continue; fail("poll input"); }
        if (fds[1].revents && wl_display_dispatch(display) < 0) fail("private display disconnected");
        if (!(fds[0].revents & POLLIN)) continue;
        int client = accept4(server, NULL, NULL, SOCK_CLOEXEC);
        if (client < 0) fail("accept input command");
        struct timeval limit = {.tv_sec = 5};
        if (setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &limit, sizeof(limit))) fail("command read timeout");
        FILE *stream = fdopen(client, "r");
        if (!stream) fail("command stream");
        char *line = NULL;
        size_t capacity = 0;
        ssize_t length = getline(&line, &capacity, stream);
        bool ok = false;
        if (length >= 0 && length <= 1024 * 1024) {
            if (!strcmp(line, "ping\n")) ok = true;
            else if (!strcmp(line, "stop\n")) ok = stopping = true;
            else if (!strncmp(line, "key ", 4)) ok = keys(line + 4);
            else if (!strncmp(line, "text ", 5)) ok = text(line + 5);
        }
        if (wl_display_roundtrip(display) < 0) fail("dispatch input command");
        if (dprintf(client, "%s\n", ok ? "OK" : "ERROR invalid input command") < 0) fail("command response");
        fclose(stream); free(line);
    }
    close(server); unlink(argv[1]);
    zwp_virtual_keyboard_v1_destroy(keyboard);
    wl_display_roundtrip(display);
    xkb_state_unref(state); xkb_keymap_unref(active_map); xkb_keymap_unref(base_map); xkb_context_unref(context);
    wl_proxy_destroy((struct wl_proxy *)manager); wl_seat_destroy(seat); wl_registry_destroy(registry);
    wl_display_disconnect(display);
    return 0;
}
