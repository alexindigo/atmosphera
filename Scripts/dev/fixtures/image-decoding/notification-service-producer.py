"""Private actual NotificationService producer, with explicit fixture handshakes."""
import base64
import json
import os
from pathlib import Path
import sys
import time

import dbus

root = Path(sys.argv[1])
bus = dbus.SessionBus()
api = dbus.Interface(bus.get_object('org.freedesktop.Notifications', '/org/freedesktop/Notifications'),
                     'org.freedesktop.Notifications')
if len(sys.argv) < 3:
    path = root / 'service-ephemeral.webp'
    value = int(api.Notify('Image service fixture', dbus.UInt32(0), '', 'Retired file', 'Producer-owned bytes',
                          dbus.Array([], signature='s'), dbus.Dictionary({'image-path': path.as_uri()}, signature='sv'), dbus.Int32(0)))
    path.unlink()
    print(json.dumps(dict(id=value)), flush=True)
    assert sys.stdin.readline().strip() == 'close'
    api.CloseNotification(dbus.UInt32(value))
else:
    ids = []
    def exchange(kind, name, **extra):
        print(json.dumps(dict(kind=kind, name=name, **extra)), flush=True)
        assert sys.stdin.readline().strip() == 'next'

    def notify(name, summary=None, source=None, color=None, replacement=0, transient=False, app_icon='', wait=True):
        exchange('prepare', name)
        hints = {'transient': dbus.Boolean(transient)}
        if source:
            hints['image-path'] = source
        if color:
            pixels = bytearray(bytes(color) * (64 * 64))
            pixels[:4] = bytes((0, 0, 0, 0))
            hints['image-data'] = dbus.Struct((dbus.Int32(64), dbus.Int32(64), dbus.Int32(256), dbus.Boolean(True),
                dbus.Int32(8), dbus.Int32(4), dbus.ByteArray(pixels)), signature='iiibiiay')
        value = int(api.Notify('Image service fixture', dbus.UInt32(replacement), app_icon, summary or name,
            'Producer-owned bytes', dbus.Array(['default', 'Open'], signature='s'), dbus.Dictionary(hints, signature='sv'), dbus.Int32(0)))
        ids.append(value)
        if source and source.startswith('file:'):
            from urllib.parse import unquote, urlparse
            path = Path(unquote(urlparse(source).path))
            if path.exists():
                path.unlink()
        if wait:
            exchange('shown', name, id=value)
        return value

    red, green, blue = (230, 30, 50, 255), (20, 210, 70, 255), (30, 60, 230, 255)
    file = root / 'service-ephemeral.webp'
    first = notify('file', 'Same labels', source=file.as_uri())
    notify('metadata-only', 'Updated metadata', source=file.as_uri(), replacement=first)
    notify('replace-green', 'Same labels', color=green, replacement=first)
    notify('replace-blue', 'Same labels', color=blue, replacement=first)
    notify('collision', 'Same labels', color=red)
    api.CloseNotification(dbus.UInt32(first))
    file.write_bytes((root / 'frame-1.png').read_bytes())
    notify('compact', source=file.as_uri())
    notify('data', app_icon='data:image/jpeg;base64,' + base64.b64encode((root / 'Still.webp').read_bytes()).decode())
    notify('no-art')
    notify('missing', source=(root / 'missing.webp').as_uri())
    corrupt = root / 'service-corrupt.webp'
    corrupt.write_bytes((root / 'Corrupt.webp').read_bytes())
    notify('corrupt', source=corrupt.as_uri())
    notify('hidden', color=green)
    notify('dnd', color=blue)
    notify('transient', color=red, transient=True)
    notify('blocked', color=green)
    notify('no-owner', color=blue, transient=True)
    notify('pending-clear', color=red)
    notify('pending-dismiss', color=green, transient=True)
    notify('pending-remove', color=blue)
    slow = notify('slow-start', app_icon=os.environ['IMAGE_SERVICE_URL'], wait=False)
    deadline = time.monotonic() + 8
    while not (root / 'http-started').exists() and time.monotonic() < deadline:
        time.sleep(.02)
    assert (root / 'http-started').is_file(), 'Actual held HTTP request did not start'
    notify('slow-superseded', color=blue, replacement=slow)
    historical = notify('history-held', app_icon=os.environ['IMAGE_SERVICE_URL'].replace('/held.jpg', '/history.jpg'), wait=False)
    deadline = time.monotonic() + 8
    while not (root / 'http-history-started').exists() and time.monotonic() < deadline:
        time.sleep(.02)
    assert (root / 'http-history-started').is_file(), 'Actual history HTTP request did not start'
    notify('transient-replacement', color=green, replacement=historical, transient=True, wait=False)
    (root / 'http-history-release').write_text('release\n')
    exchange('shown', 'transient-replacement', id=historical)
    notify('blocked-replacement', summary='blocked policy', color=blue, replacement=historical)
    notify('shared-one', color=red)
    notify('shared-two', color=red)
    exchange('control', 'shared-remove')
    notify('overflow-trigger', color=green)
    same_icon = root / 'same-provider.png'
    same_icon.write_bytes((root / 'frame-0.png').read_bytes())
    icon_url = 'image://icon/fixture-same-provider/same-provider.png?path=' + str(root).lstrip('/')
    old = notify('same-provider-first', app_icon=icon_url)
    new_icon = root / 'same-provider-new.png'
    new_icon.write_bytes((root / 'frame-2.png').read_bytes())
    new_icon.replace(same_icon)
    notify('same-provider-replacement', replacement=old, app_icon=icon_url)
    notify('same-provider-new', app_icon=icon_url)
    api.CloseNotification(dbus.UInt32(old))
    exchange('control', 'clear-with-popup')
    notify('cold-provider', color=blue)
    file.write_bytes((root / 'Still.webp').read_bytes())
    notify('cold-file', source=file.as_uri())
    for value in set(ids):
        api.CloseNotification(dbus.UInt32(value))
    exchange('control', 'closed')
