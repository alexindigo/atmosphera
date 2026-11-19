#!/usr/bin/env python3
"""Independent guest-only Locker1 counterpart.

Version 1 variants spawn the shipped standalone emergency lock (which must not
take this service's name). The version 2 `capable` variant is a reference
implementation of docs/locker1-contract.md: its native ext-session-lock client
reports actual `locked`, PAM and protocol-unlock events, and only those emit
Secured/Unlocked. The Fixture interface exists only for stale-evidence proofs.
"""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import time

import dbus
import dbus.mainloop.glib
import dbus.service
from gi.repository import GLib


IFACE = 'app.atmosphera.Locker1'
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--variant', choices=('normal', 'error', 'no-engagement', 'disappearing', 'capable'), required=True)
parser.add_argument('--work', type=Path, required=True)
parser.add_argument('--native-client', type=Path)
args = parser.parse_args()
assert os.environ['USER'] == 'tester'
assert args.work.resolve().is_relative_to('/home/tester/Projects/locker')
assert Path(os.environ['TMPDIR']).resolve().is_relative_to('/home/tester/Projects/locker')
assert (args.variant == 'capable') == (args.native_client is not None)
dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
bus = dbus.SessionBus()
loop = GLib.MainLoop()
calls = 0
child = None
native = {'secure': False, 'authenticated': False}
requests = {}


def record(name, value):
    with (args.work / 'events.jsonl').open('a') as stream:
        stream.write(json.dumps({'event': name, 'value': value, 'monotonic': time.monotonic()}) + '\n')


class Locker(dbus.service.Object):
    def join(self, request_id):
        global calls, child
        calls += 1
        (args.work / 'calls.json').write_text(json.dumps({'calls': calls, 'monotonic': time.monotonic()}))
        if args.variant == 'error':
            raise dbus.exceptions.DBusException('fixture method failure', name='app.atmosphera.Fixture.Error')
        if args.variant == 'normal' and child is None:
            environment = {key: value for key, value in os.environ.items() if not key.startswith('ATMOSPHERA_LOCK_')}
            child = subprocess.Popen(['qs', '-c', 'atmosphera-emergency-lock'], env=environment)
        if args.variant == 'disappearing':
            GLib.timeout_add(50, lambda: loop.quit())
        if args.variant != 'capable':
            return
        if request_id is not None and not re.fullmatch(r'[A-Za-z0-9._:-]{1,128}', request_id):
            raise dbus.exceptions.DBusException('invalid request ID', name='app.atmosphera.Locker1.Error.InvalidRequest')
        if native['authenticated']:
            raise dbus.exceptions.DBusException('lock is ending', name='app.atmosphera.Locker1.Error.Ended')
        if child is None:
            start_native()
        if request_id is not None and request_id not in requests:
            requests[request_id] = 'secure' if native['secure'] else 'pending'
            record('request', request_id)
            if requests[request_id] == 'secure':
                GLib.idle_add(lambda: (self.Secured(request_id), False)[1])

    @dbus.service.method(IFACE, in_signature='', out_signature='')
    def Lock(self):
        self.join(None)

    @dbus.service.method(IFACE, in_signature='s', out_signature='')
    def LockRequest(self, request_id):
        if args.variant != 'capable':
            raise dbus.exceptions.DBusException('unknown method', name='org.freedesktop.DBus.Error.UnknownMethod')
        self.join(str(request_id))

    @dbus.service.method(IFACE, in_signature='s', out_signature='s')
    def RequestState(self, request_id):
        if args.variant != 'capable':
            raise dbus.exceptions.DBusException('unknown method', name='org.freedesktop.DBus.Error.UnknownMethod')
        record('request-state', str(request_id))
        return requests.get(str(request_id), 'unknown')

    @dbus.service.signal(IFACE, signature='s')
    def Secured(self, request_id):
        record('Secured', request_id)

    @dbus.service.signal(IFACE, signature='s')
    def Unlocked(self, request_id):
        record('Unlocked', request_id)

    @dbus.service.method(dbus.PROPERTIES_IFACE, in_signature='ss', out_signature='v')
    def Get(self, interface, name):
        if args.variant == 'capable' and interface == IFACE and name == 'Version':
            return dbus.Int32(2)
        raise dbus.exceptions.DBusException('no such property', name='org.freedesktop.DBus.Error.UnknownProperty')

    @dbus.service.method(dbus.PROPERTIES_IFACE, in_signature='s', out_signature='a{sv}')
    def GetAll(self, interface):
        return {'Version': dbus.Int32(2)} if args.variant == 'capable' and interface == IFACE else {}

    # Test-only stale-evidence hooks, on a separate interface.
    @dbus.service.method('app.atmosphera.Fixture', in_signature='ss', out_signature='')
    def Emit(self, kind, request_id):
        record('fixture-emit', [str(kind), str(request_id)])
        (self.Secured if kind == 'Secured' else self.Unlocked)(str(request_id))


pending = b''


def native_event(fd, condition):
    # Raw reads: one readiness callback can carry several events, and a
    # buffered readline would strand later lines in a Python-side buffer.
    global child, pending
    chunk = os.read(fd, 4096)
    pending += chunk
    while b'\n' in pending:
        line, pending = pending.split(b'\n', 1)
        native_line(line.decode())
    if chunk:
        return True
    else:
        status = child.wait()
        record('native-exit', status)
        for request_id, state in list(requests.items()):
            if native['authenticated'] and status == 0 and state == 'secure':
                # Exit 0 follows unlock_and_destroy plus a display round trip.
                requests[request_id] = 'unlocked'
                service.Unlocked(request_id)
            elif state in ('pending', 'secure'):
                requests[request_id] = 'failed'
        child = None
        return False


def native_line(line):
    event = json.loads(line)['event']
    record('native', event)
    if event == 'locked':
        native['secure'] = True
        for request_id, state in list(requests.items()):
            if state == 'pending':
                requests[request_id] = 'secure'
                service.Secured(request_id)
    elif event == 'authenticated-unlock':
        native['authenticated'] = True


def start_native():
    global child
    # The client maps surfaces at once when its release path exists.
    child = subprocess.Popen([str(args.native_client), str(args.work)], stdout=subprocess.PIPE)
    record('native-start', child.pid)
    GLib.io_add_watch(child.stdout.fileno(), GLib.PRIORITY_DEFAULT, GLib.IO_IN | GLib.IO_HUP, native_event)


name = dbus.service.BusName('app.atmosphera.Locker', bus=bus, do_not_queue=True)
service = Locker(bus, '/app/atmosphera/Locker')
(args.work / 'ready.json').write_text(json.dumps({'pid': os.getpid(), 'owner': bus.get_unique_name()}))
loop.run()
(args.work / 'voluntary-exit.json').write_text(json.dumps({'monotonic': time.monotonic()}))
