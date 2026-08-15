#!/usr/bin/env python3
"""app.atmosphera.HwController — tiny privileged D-Bus helper.

Translates userland intent into system-state writes. Deliberately minimal:
hard allowlist of methods, typed arguments, no config files, no state, no
eval. The shell owns policy; this process owns the root-only sysfs write.

API (system bus):
  name:      app.atmosphera.HwController
  path:      /app/atmosphera/HwController
  interface: app.atmosphera.HwController
  methods:   SetTurbo(b: enabled) — CPU turbo/boost toggle
"""

import os
import sys

import dbus
import dbus.mainloop.glib
import dbus.service
from gi.repository import GLib

BUS_NAME = "app.atmosphera.HwController"
OBJECT_PATH = "/app/atmosphera/HwController"
IFACE = "app.atmosphera.HwController"
POLKIT_ACTION = "app.atmosphera.hwcontroller.setturbo"

PSTATE_NO_TURBO = "/sys/devices/system/cpu/intel_pstate/no_turbo"
CPUFREQ_BOOST = "/sys/devices/system/cpu/cpufreq/boost"


def _polkit_allowed(sender):
    """Ask polkit whether the caller (unique bus name) may run the action.

    flags=0 — never spawn an auth dialog from a background helper; the
    policy's allow_active=yes covers the active session silently.
    """
    try:
        bus = dbus.SystemBus()
        authority = bus.get_object("org.freedesktop.PolicyKit1",
                                   "/org/freedesktop/PolicyKit1/Authority")
        iface = dbus.Interface(authority, "org.freedesktop.PolicyKit1.Authority")
        subject = ("system-bus-name", {"name": sender})
        result = iface.CheckAuthorization(subject, POLKIT_ACTION, {},
                                          dbus.UInt32(0), "", timeout=5)
        is_authorized = bool(result[0])
        return is_authorized
    except Exception as exc:  # polkit down/broken → deny
        print(f"polkit check failed: {exc}", file=sys.stderr)
        return False


class HwController(dbus.service.Object):
    @dbus.service.method(IFACE, in_signature="b", out_signature="",
                         sender_keyword="sender")
    def SetTurbo(self, enabled, sender=None):
        if not sender or not _polkit_allowed(sender):
            raise dbus.exceptions.DBusException(
                "not authorized to set turbo state",
                name="org.freedesktop.DBus.Error.AccessDenied")
        try:
            if os.path.exists(PSTATE_NO_TURBO):
                # no_turbo is inverted: 0 = turbo on, 1 = turbo off
                with open(PSTATE_NO_TURBO, "w", encoding="ascii") as fh:
                    fh.write("0" if enabled else "1")
            elif os.path.exists(CPUFREQ_BOOST):
                with open(CPUFREQ_BOOST, "w", encoding="ascii") as fh:
                    fh.write("1" if enabled else "0")
            else:
                raise dbus.exceptions.DBusException(
                    "no turbo/boost sysfs node on this platform",
                    name="org.freedesktop.DBus.Error.NotSupported")
        except PermissionError as exc:
            raise dbus.exceptions.DBusException(
                str(exc), name="org.freedesktop.DBus.Error.AccessDenied")
        print(f"SetTurbo({bool(enabled)}) ok", flush=True)


def main():
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SystemBus()
    # Keep a reference! An unreferenced BusName gets GC'd, the name is
    # released, and the mainloop exits instantly (service "deactivated").
    _name = dbus.service.BusName(BUS_NAME, bus=bus, do_not_queue=True)
    HwController(bus, OBJECT_PATH)
    print(f"{BUS_NAME} ready", flush=True)
    GLib.MainLoop().run()


if __name__ == "__main__":
    main()
