#!/usr/bin/env python3
"""Controlled UPower protocol on a private bus, not physical battery evidence."""
import json
import subprocess
import threading
import time

import gi
gi.require_version('Gio', '2.0')
from gi.repository import Gio, GLib

SERVICE = 'org.freedesktop.UPower'
ROOT = '/org/freedesktop/UPower'
DEVICE = SERVICE + '.Device'


class Fixture:
    def __init__(self, case, runtime, guard_factory):
        self.case = case
        self.address = 'unix:path=' + str(runtime / 'upower-bus')
        self.log = (case / 'bus.log').open('w')
        self.daemon = subprocess.Popen(['dbus-daemon', '--session', '--nofork', '--address=' + self.address], stdout=self.log, stderr=subprocess.STDOUT, start_new_session=True)
        self.guard = guard_factory(self.daemon)
        deadline = time.monotonic() + 5
        while not (runtime / 'upower-bus').exists():
            if self.daemon.poll() is not None or time.monotonic() > deadline:
                raise RuntimeError('private battery bus not ready')
            time.sleep(.02)
        self.bus = Gio.DBusConnection.new_for_address_sync(self.address, Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION, None, None)
        self.props = {}
        self.labels = ('DisplayDevice', 'BAT0', 'BAT1')
        for label in self.labels:
            self.props[ROOT + '/devices/' + label] = dict(NativePath=('s', label), Model=('s', 'Controlled ' + label), Type=('u', 2), PowerSupply=('b', True),
                Energy=('d', 30.), EnergyFull=('d', 60.), EnergyRate=('d', 17. if label == 'BAT0' else 0.), TimeToEmpty=('x', 3600 if label == 'BAT0' else 0),
                TimeToFull=('x', 0), Percentage=('d', 65. if label == 'BAT0' else 25.), IsPresent=('b', True), State=('u', 2), Capacity=('d', 0. if label == 'BAT1' else 91.), IconName=('s', 'battery'))
        self.props[ROOT] = dict(OnBattery=('b', True), DaemonVersion=('s', 'controlled'))
        for path, props in self.props.items():
            interface = SERVICE if path == ROOT else DEVICE
            methods = ('<method name="EnumerateDevices"><arg direction="out" type="ao"/></method><method name="GetDisplayDevice"><arg direction="out" type="o"/></method>'
                       '<signal name="DeviceAdded"><arg type="o"/></signal><signal name="DeviceRemoved"><arg type="o"/></signal>') if path == ROOT else ''
            xml = '<node><interface name="' + interface + '">' + methods + ''.join('<property name="' + name + '" type="' + signature + '" access="read"/>' for name, (signature, _) in props.items()) + '</interface></node>'
            self.bus.register_object(path, Gio.DBusNodeInfo.new_for_xml(xml).interfaces[0], self.method, self.get, None)
        result = self.bus.call_sync('org.freedesktop.DBus', '/org/freedesktop/DBus', 'org.freedesktop.DBus', 'RequestName', GLib.Variant('(su)', (SERVICE, 4)), None, Gio.DBusCallFlags.NONE, 3000, None)
        if result.unpack() != (1,):
            raise RuntimeError('private UPower name unavailable')
        self.loop = GLib.MainLoop()
        self.thread = threading.Thread(target=self.loop.run); self.thread.start()

    def get(self, _bus, _sender, path, interface, name):
        signature, value = self.props[path][name]
        return GLib.Variant(signature, value)

    def method(self, _bus, _sender, path, interface, method, _params, invocation):
        with (self.case / 'upower.jsonl').open('a') as stream:
            stream.write(json.dumps(dict(path=path, interface=interface, method=method)) + '\n')
        if method == 'EnumerateDevices':
            invocation.return_value(GLib.Variant('(ao)', ([ROOT + '/devices/' + label for label in self.labels],)))
        elif method == 'GetDisplayDevice':
            invocation.return_value(GLib.Variant('(o)', (ROOT + '/devices/DisplayDevice',)))
        else:
            invocation.return_dbus_error('org.freedesktop.DBus.Error.UnknownMethod', method)

    def finish(self):
        self.bus.close_sync(None)
        self.loop.quit(); self.thread.join(timeout=5)
        self.guard.terminate(); self.daemon.wait(timeout=5); self.log.close()
