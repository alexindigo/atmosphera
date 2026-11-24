"""Send one notification whose summary and body carry image markup.

Usage: notification-body-producer.py <http-base-url>. Prints the id, waits for
"close" on stdin, then closes it.
"""
import json
import sys

import dbus

base = sys.argv[1]
api = dbus.Interface(dbus.SessionBus().get_object('org.freedesktop.Notifications', '/org/freedesktop/Notifications'),
                     'org.freedesktop.Notifications')
summary = 'Body markup <img src="%s/summary.png"> summary-marker' % base
body = ('Hello <b>world</b> <img src="%s/body.png" alt="inline art"> and ![md art](%s/md.png) '
        '<table background="%s/background.png"><tr><td>cell</td></tr></table> end-marker') % (base, base, base)
value = int(api.Notify('Image body fixture', dbus.UInt32(0), '', summary, body, dbus.Array([], signature='s'),
                       dbus.Dictionary({}, signature='sv'), dbus.Int32(0)))
print(json.dumps(dict(id=value)), flush=True)
assert sys.stdin.readline().strip() == 'close'
api.CloseNotification(dbus.UInt32(value))
