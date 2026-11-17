/* Persistent, guest-only virtual pointer. Commands: move x y w h; button code down. */
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <wayland-client.h>
#include "virtual-pointer-client.h"

static struct zwlr_virtual_pointer_manager_v1 *manager;
static void global(void *data, struct wl_registry *registry, uint32_t name,
                   const char *interface, uint32_t version) {
    (void)data; (void)version;
    if (!strcmp(interface, "zwlr_virtual_pointer_manager_v1"))
        manager = wl_registry_bind(registry, name, &zwlr_virtual_pointer_manager_v1_interface, 1);
}
static void removed(void *data, struct wl_registry *registry, uint32_t name) {
    (void)data; (void)registry; (void)name;
}
static uint32_t milliseconds(void) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (uint32_t)((uint64_t)now.tv_sec * 1000 + now.tv_nsec / 1000000);
}
int main(void) {
    struct wl_display *display = wl_display_connect(NULL);
    if (!display) return 1;
    struct wl_registry *registry = wl_display_get_registry(display);
    const struct wl_registry_listener listener = {global, removed};
    wl_registry_add_listener(registry, &listener, NULL);
    if (wl_display_roundtrip(display) < 0 || !manager) return 2;
    struct zwlr_virtual_pointer_v1 *pointer = zwlr_virtual_pointer_manager_v1_create_virtual_pointer(manager, NULL);
    char line[128], extra;
    puts("READY"); fflush(stdout);
    while (fgets(line, sizeof(line), stdin)) {
        unsigned x, y, w, h, code, down;
        if (sscanf(line, "move %u %u %u %u %c", &x, &y, &w, &h, &extra) == 4 && w && h && x < w && y < h)
            zwlr_virtual_pointer_v1_motion_absolute(pointer, milliseconds(), x, y, w, h);
        else if (sscanf(line, "button %u %u %c", &code, &down, &extra) == 2 && down <= 1)
            zwlr_virtual_pointer_v1_button(pointer, milliseconds(), code, down);
        else return 3;
        zwlr_virtual_pointer_v1_frame(pointer);
        if (wl_display_roundtrip(display) < 0) return 4;
        puts("OK"); fflush(stdout);
    }
    zwlr_virtual_pointer_v1_destroy(pointer);
    zwlr_virtual_pointer_manager_v1_destroy(manager);
    wl_display_roundtrip(display);
    wl_display_disconnect(display);
    return 0;
}
