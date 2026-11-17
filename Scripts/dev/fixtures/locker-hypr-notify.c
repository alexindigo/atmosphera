/* Read-only guest evidence. Never binds ext-session-lock or requests a lock.
 * Registry/listener pattern: locker-opaque-delayed.c. Wire semantics:
 * Hyprland v0.56.2 src/protocols/LockNotify.cpp and the adjacent protocol XML.
 */
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <wayland-client.h>
#include "hypr-notify-client.h"

static struct hyprland_lock_notifier_v1 *manager;
static bool active;

static void emit(const char *kind) {
    struct timespec now;
    assert(clock_gettime(CLOCK_MONOTONIC, &now) == 0);
    printf("{\"kind\":\"%s\",\"locked\":%s,\"sourceMonotonic\":%.9f}\n",
        kind, active ? "true" : "false", now.tv_sec + now.tv_nsec / 1e9);
    fflush(stdout);
}
static void locked(void *data, struct hyprland_lock_notification_v1 *notification) {
    (void)data; (void)notification;
    assert(!active);
    active = true;
    emit("compositor-lock");
}
static void unlocked(void *data, struct hyprland_lock_notification_v1 *notification) {
    (void)data; (void)notification;
    assert(active);
    active = false;
    emit("compositor-lock");
}
static const struct hyprland_lock_notification_v1_listener listener = {
    .locked = locked, .unlocked = unlocked,
};
static void global(void *data, struct wl_registry *registry, uint32_t name,
        const char *interface, uint32_t version) {
    (void)data; (void)version;
    if (!strcmp(interface, hyprland_lock_notifier_v1_interface.name))
        manager = wl_registry_bind(registry, name, &hyprland_lock_notifier_v1_interface, 1);
}
static void removed(void *d, struct wl_registry *r, uint32_t n) {(void)d; (void)r; (void)n;}
static const struct wl_registry_listener registry_listener = {.global = global, .global_remove = removed};

int main(void) {
    struct wl_display *display = wl_display_connect(NULL);
    assert(display);
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    assert(wl_display_roundtrip(display) >= 0 && manager);
    struct hyprland_lock_notification_v1 *notification = hyprland_lock_notifier_v1_get_lock_notification(manager);
    hyprland_lock_notification_v1_add_listener(notification, &listener, NULL);
    /* The server sends locked immediately for an already locked session. */
    assert(wl_display_roundtrip(display) >= 0);
    emit("compositor-initial");
    while (wl_display_dispatch(display) >= 0) {}
    return 1;
}
