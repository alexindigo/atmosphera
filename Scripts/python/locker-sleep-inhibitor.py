#!/usr/bin/env python3
"""Hold logind's actual delay-inhibitor fd; the QML owner supplies secure state.

The fd is acquired before PrepareForSleep, closed after secure confirmation,
and reacquired on resume. Logind's configured window is observed, never extended.
stdin EOF closes it, so shell death cannot leak an inhibitor. No lock/unlock API.
"""
import json
import os
import secrets
import sys
import time

import dbus
import dbus.mainloop.glib
from gi.repository import GLib


def main():
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SystemBus()
    proxy = bus.get_object('org.freedesktop.login1', '/org/freedesktop/login1')
    manager = dbus.Interface(proxy, 'org.freedesktop.login1.Manager')
    properties = dbus.Interface(proxy, 'org.freedesktop.DBus.Properties')
    max_delay = int(properties.Get('org.freedesktop.login1.Manager', 'InhibitDelayMaxUSec')) / 1_000_000
    state = {'fd': None, 'secure': False, 'opaque': False, 'sleeping': False, 'window': '',
             'started': None, 'expired': False}
    loop = GLib.MainLoop()

    def emit(event, **values):
        print(json.dumps(dict(event=event, monotonic=time.monotonic(), **values)), flush=True)

    def release():
        if state['fd'] is not None:
            os.close(state['fd'])
            state['fd'] = None
            emit('released', secure=state['secure'])

    def acquire():
        if state['fd'] is None:
            state['fd'] = manager.Inhibit('sleep', 'Atmosphera', 'Lock before suspend', 'delay').take()
            emit('acquired', maxDelay=max_delay)

    def prepare(start):
        if state['started'] is not None and state['sleeping'] == bool(start):
            return
        state['sleeping'] = bool(start)
        state['started'] = time.monotonic() if start else None
        state['expired'] = False
        # A pre-window boolean cannot authorize this fd's release. Tokens also
        # fence replies queued before a helper restart or an earlier resume.
        state['secure'] = False
        state['window'] = secrets.token_hex(24) if start else ''
        emit('prepare', sleeping=bool(start), window=state['window'], secure=False)
        if not start:
            acquire()

    def check_window():
        if state['sleeping'] and state['started'] is not None and not state['expired']:
            if time.monotonic() >= state['started'] + max_delay:
                state['expired'] = True
                if not state['secure']:
                    emit('unconfirmed', message='suspend without confirmed secure lock (opaque locker)'
                         if state['opaque'] else 'suspend without confirmed secure lock', maxDelay=max_delay)
                release()
        return True

    def receive(channel, condition):
        # Read bytes rather than a buffered TextIOWrapper: a second complete
        # line may already be buffered without another fd-readability callback.
        if condition & GLib.IO_IN:
            chunk = os.read(sys.stdin.fileno(), 65536)
            if chunk:
                receive.buffer += chunk
                while b'\n' in receive.buffer:
                    line, receive.buffer = receive.buffer.split(b'\n', 1)
                    value = json.loads(line)
                    if not state['sleeping'] or not state['window'] or value.get('window') != state['window']:
                        continue
                    state['secure'] = value.get('secure') is True
                    state['opaque'] = value.get('opaque') is True
                    if state['sleeping'] and state['secure']:
                        release()
                return True
        release()
        loop.quit()
        return False

    receive.buffer = b''
    bus.add_signal_receiver(prepare, signal_name='PrepareForSleep',
                            dbus_interface='org.freedesktop.login1.Manager',
                            bus_name='org.freedesktop.login1', path='/org/freedesktop/login1')
    GLib.io_add_watch(sys.stdin.fileno(), GLib.IO_IN | GLib.IO_HUP | GLib.IO_ERR, receive)
    GLib.timeout_add(50, check_window)
    try:
        acquire()
        # Converge a sleep already in preparation after the subscription exists.
        prepare(bool(properties.Get('org.freedesktop.login1.Manager', 'PreparingForSleep')))
        loop.run()
    finally:
        release()


if __name__ == '__main__':
    main()
