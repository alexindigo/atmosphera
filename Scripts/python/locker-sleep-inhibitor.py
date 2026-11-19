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
             'started': None, 'expired': False, 'failed': False}
    loop = GLib.MainLoop()

    def emit(event, **values):
        print(json.dumps(dict(event=event, monotonic=time.monotonic(), **values)), flush=True)

    def release():
        if state['fd'] is not None:
            closing = time.monotonic()
            os.close(state['fd'])
            state['fd'] = None
            emit('released', secure=state['secure'], closeMonotonic=closing)

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
            try:
                acquire()
            except (dbus.DBusException, OSError) as error:
                # dbus-python otherwise logs a callback exception and keeps an
                # fd-less helper alive. Exit this lifetime so QML withdraws
                # availability and its existing retry timer starts a new one.
                state['failed'] = True
                emit('unavailable', reason=str(error))
                loop.quit()
                return False

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
                    try:
                        value = json.loads(line)
                    except ValueError:
                        emit('ignored', reason='malformed owner state line')
                        continue
                    if not isinstance(value, dict):
                        emit('ignored', reason='non-object owner state line')
                        continue
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
        try:
            acquire()
        except dbus.DBusException as error:
            if error.get_dbus_name() != 'org.freedesktop.login1.OperationInProgress':
                raise
            # A helper started during sleep cannot get a delay fd. It still
            # owes the owner the active window, without pretending to hold one.
            # If sleep ended during the call, prepare(false) reacquires normally.
            emit('unavailable', reason=str(error))
        # Converge a sleep already in preparation after the subscription exists.
        if prepare(bool(properties.Get('org.freedesktop.login1.Manager', 'PreparingForSleep'))) is not False:
            loop.run()
    finally:
        release()
    return 1 if state['failed'] else 0


if __name__ == '__main__':
    raise SystemExit(main())
