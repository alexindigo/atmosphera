#!/usr/bin/env python3
"""Independent guest-only Locker1 counterpart; no secure-ack extension."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time

import dbus
import dbus.mainloop.glib
import dbus.service
from gi.repository import GLib


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--variant', choices=('normal', 'error', 'no-engagement', 'disappearing'), required=True)
parser.add_argument('--work', type=Path, required=True)
args = parser.parse_args()
assert os.environ['USER'] == 'tester'
assert args.work.resolve().is_relative_to('/home/tester/Projects/locker')
assert Path(os.environ['TMPDIR']).resolve().is_relative_to('/home/tester/Projects/locker')
dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
bus = dbus.SessionBus()
loop = GLib.MainLoop()
calls = 0
child = None


class Locker(dbus.service.Object):
    @dbus.service.method('app.atmosphera.Locker1', in_signature='', out_signature='')
    def Lock(self):
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


name = dbus.service.BusName('app.atmosphera.Locker', bus=bus, do_not_queue=True)
service = Locker(bus, '/app/atmosphera/Locker')
(args.work / 'ready.json').write_text(json.dumps({'pid': os.getpid(), 'owner': bus.get_unique_name()}))
loop.run()
(args.work / 'voluntary-exit.json').write_text(json.dumps({'monotonic': time.monotonic()}))
