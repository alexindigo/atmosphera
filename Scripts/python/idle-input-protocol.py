#!/usr/bin/env python3
"""Require genuine input-only idle notification, before Quickshell's v1 fallback.

Uses the runtime's libwayland-client registry, with no optional Python packages
or wayland-info dependency. The caller supplies a finite process deadline.
"""
import ctypes as C
import sys


def supported():
    lib = C.CDLL('libwayland-client.so.0')
    lib.wl_display_connect.argtypes = [C.c_char_p]
    lib.wl_display_connect.restype = C.c_void_p
    lib.wl_display_disconnect.argtypes = [C.c_void_p]
    lib.wl_display_roundtrip.argtypes = [C.c_void_p]
    lib.wl_display_roundtrip.restype = C.c_int
    lib.wl_proxy_get_version.argtypes = [C.c_void_p]
    lib.wl_proxy_get_version.restype = C.c_uint32
    lib.wl_proxy_marshal_flags.argtypes = [C.c_void_p, C.c_uint32, C.c_void_p, C.c_uint32, C.c_uint32]
    lib.wl_proxy_marshal_flags.restype = C.c_void_p
    lib.wl_proxy_add_listener.argtypes = [C.c_void_p, C.c_void_p, C.c_void_p]
    lib.wl_proxy_add_listener.restype = C.c_int
    lib.wl_proxy_destroy.argtypes = [C.c_void_p]
    global_fn = C.CFUNCTYPE(None, C.c_void_p, C.c_void_p, C.c_uint32, C.c_char_p, C.c_uint32)
    remove_fn = C.CFUNCTYPE(None, C.c_void_p, C.c_void_p, C.c_uint32)
    class Listener(C.Structure):
        _fields_ = [('global_event', global_fn), ('remove_event', remove_fn)]
    versions = []
    @global_fn
    def on_global(_data, _registry, _name, interface, version):
        if interface == b'ext_idle_notifier_v1':
            versions.append(version)
    @remove_fn
    def on_remove(_data, _registry, _name):
        pass
    listener = Listener(on_global, on_remove)
    display = lib.wl_display_connect(None)
    if not display:
        return False
    registry = None
    try:
        # wl_display.get_registry is opcode 1, wl_registry is a constructor.
        interface = C.addressof(C.c_byte.in_dll(lib, 'wl_registry_interface'))
        registry = lib.wl_proxy_marshal_flags(display, 1, interface,
            lib.wl_proxy_get_version(display), 0, C.c_void_p())
        if not registry or lib.wl_proxy_add_listener(registry, C.byref(listener), None) != 0:
            return False
        return lib.wl_display_roundtrip(display) >= 0 and any(v >= 2 for v in versions)
    finally:
        if registry:
            lib.wl_proxy_destroy(registry)
        lib.wl_display_disconnect(display)


if __name__ == '__main__':
    try:
        ok = supported()
    except (OSError, AttributeError) as error:
        print(str(error), file=sys.stderr)
        ok = False
    if not ok:
        print('Compositor does not provide input-only idle notification (version 2).', file=sys.stderr)
    sys.exit(0 if ok else 1)
