"""Actual private-bus D-Bus producer; no real accounts or guest notification bus."""
import json
from pathlib import Path
import sys

import dbus

root = Path(sys.argv[1])
bus = dbus.SessionBus()
api = dbus.Interface(bus.get_object('org.freedesktop.Notifications', '/org/freedesktop/Notifications'),
                     'org.freedesktop.Notifications')
ids = []
for index, color in enumerate(((230, 30, 50, 255), (20, 210, 70, 255), (30, 60, 230, 255), (230, 30, 50, 255))):
    pixels = bytearray(bytes(color) * (64 * 64))
    pixels[:4] = bytes((0, 0, 0, 0))
    data = dbus.Struct((dbus.Int32(64), dbus.Int32(64), dbus.Int32(256), dbus.Boolean(True), dbus.Int32(8), dbus.Int32(4),
                        dbus.ByteArray(pixels)), signature='iiibiiay')
    replacement = ids[0] if index in (1, 2) else 0
    result = int(api.Notify('Same app', dbus.UInt32(replacement), '', 'Same summary', 'Same body',
                           dbus.Array([], signature='s'), dbus.Dictionary({'image-data': data}, signature='sv'), dbus.Int32(0)))
    ids.append(result)
for name in ('ephemeral.webp', "literal '[x]: é.dat", 'ephemeral.png'):
    path = root / name
    result = int(api.Notify('Same app', dbus.UInt32(0), '', 'Same summary', 'Same body', dbus.Array([], signature='s'),
                           dbus.Dictionary({'image-path': path.as_uri()}, signature='sv'), dbus.Int32(0)))
    ids.append(result)
    # Notify has returned: admission must already own the exact bytes.
    path.unlink()
    if name == 'ephemeral.webp':
        # Identical URL and labels, different bytes and independent admission.
        path.write_bytes((root / 'frame-1.png').read_bytes())
        ids.append(int(api.Notify('Same app', dbus.UInt32(0), '', 'Same summary', 'Same body', dbus.Array([], signature='s'),
                                  dbus.Dictionary({'image-path': path.as_uri()}, signature='sv'), dbus.Int32(0))))
        path.unlink()
for value in set(ids):
    api.CloseNotification(dbus.UInt32(value))
print(json.dumps(dict(ids=ids)))
