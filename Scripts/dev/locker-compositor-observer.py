#!/usr/bin/env python3
"""Continuous guest-only lock evidence; never requests or releases a lock.

Subscribe to compositor-originated logind changes before publishing ready.
Retain the user journal with source monotonic timestamps and exact unit samples.
Framebuffers are captured separately from Ark at the runner's barriers, not via
Wayland screencopy. EOF on stdin or SIGTERM closes this observer and its journal.
"""
import argparse
import json
import os
from pathlib import Path
import signal
import stat
import subprocess
import sys
import time
import re
from datetime import datetime

from locker_test_support import manage, require_guest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, required=True)
    args = parser.parse_args()
    source, work = require_guest(args.work, Path(__file__).resolve().parents[2])
    import dbus
    import dbus.mainloop.glib
    from gi.repository import GLib
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SystemBus()
    sid = manage(source, {'operation': 'discover'})['session']
    manager = dbus.Interface(bus.get_object('org.freedesktop.login1', '/org/freedesktop/login1'),
                             'org.freedesktop.login1.Manager')
    session_path = str(manager.GetSession(sid))
    session = bus.get_object('org.freedesktop.login1', session_path)
    properties = dbus.Interface(session, 'org.freedesktop.DBus.Properties')
    loop = GLib.MainLoop()
    output = (work / 'events.jsonl').open('x')

    def emit(kind, **values):
        output.write(json.dumps(dict(kind=kind, observed=time.monotonic(), **values)) + '\n')
        output.flush()

    compositor_stream = None
    compositor_identity = None
    compositor_pending = bytearray()
    clock_offset = time.monotonic() - time.time()
    if os.environ.get('NIRI_SOCKET'):
        # This devbase redirects niri stdout/stderr to a regular file rather
        # than the journal. Bind that stream to the process holding the exact
        # discovered compositor socket, not a guessed historical pathname.
        socket_path = os.environ['NIRI_SOCKET']
        assert Path(socket_path).is_socket()
        inodes = {line.split()[6] for line in Path('/proc/net/unix').read_text().splitlines()[1:]
                  if len(line.split()) >= 8 and line.split()[7] == socket_path}
        matches = []
        for process in Path('/proc').glob('[0-9]*'):
            try:
                if (process / 'exe').resolve().name != 'niri':
                    continue
                if not any(link.readlink().as_posix() in {'socket:[' + inode + ']' for inode in inodes}
                           for link in (process / 'fd').iterdir()):
                    continue
                matches.append(process)
            except (PermissionError, FileNotFoundError, ProcessLookupError):
                continue
        assert len(matches) == 1, 'cannot identify the exact niri compositor socket owner'
        process = matches[0]
        fd = process / 'fd/1'
        if stat.S_ISREG(fd.stat().st_mode):
            compositor_stream = fd.open('rb')
            compositor_stream.seek(0, os.SEEK_END)
            identity = os.fstat(compositor_stream.fileno())
            compositor_identity = {'pid': int(process.name),
                'start': (process / 'stat').read_text().split(') ', 1)[1].split()[19],
                'file': str(fd.readlink()), 'inode': identity.st_ino, 'device': identity.st_dev,
                'offset': compositor_stream.tell(), 'socket': socket_path}
            emit('compositor-source', **compositor_identity)

    def consume_compositor():
        if compositor_stream is None:
            return True
        process = Path('/proc') / str(compositor_identity['pid'])
        assert (process / 'stat').read_text().split(') ', 1)[1].split()[19] == compositor_identity['start'], 'compositor identity changed'
        compositor_pending.extend(compositor_stream.read())
        while b'\n' in compositor_pending:
            line, _, remainder = compositor_pending.partition(b'\n')
            compositor_pending[:] = remainder
            message = re.sub(r'\x1b\[[0-9;]*m', '', line.decode(errors='replace'))
            timestamp = re.match(r'^(\d{4}-\d\d-\d\dT\S+)', message)
            source = datetime.fromisoformat(timestamp[1]).timestamp() + clock_offset if timestamp else None
            emit('compositor-log', message=message, sourceMonotonic=source)
        return True

    def read_compositor():
        try:
            return consume_compositor()
        except Exception as error:
            emit('observer-error', message='compositor log: ' + str(error))
            loop.quit()
            return False

    def changed(interface, values, invalidated):
        if str(interface) == 'org.freedesktop.login1.Session' and 'LockedHint' in values:
            emit('locked-hint', locked=bool(values['LockedHint']))

    bus.add_signal_receiver(changed, signal_name='PropertiesChanged',
                            dbus_interface='org.freedesktop.DBus.Properties',
                            bus_name='org.freedesktop.login1', path=session_path)
    emit('initial', locked=bool(properties.Get('org.freedesktop.login1.Session', 'LockedHint')), session=sid)
    journal_errors = (work / 'journal-stderr.txt').open('w')
    journal = subprocess.Popen(['journalctl', '--user', '-b', '--follow', '--lines=0', '--output=json', '--no-pager'],
                               stdout=subprocess.PIPE, stderr=journal_errors)
    pending = bytearray()

    def consume_journal(chunk):
        pending.extend(chunk)
        while b'\n' in pending:
            line, _, remainder = pending.partition(b'\n')
            pending[:] = remainder
            record = json.loads(line)
            message = record.get('MESSAGE', '')
            if not isinstance(message, str) or 'wl_keyboard' in message:
                continue
            unit = record.get('_SYSTEMD_USER_UNIT', '')
            if (record.get('_COMM') == 'niri' or unit.startswith(('atmosphera-lockscreen-', 'atmosphera-emergency-lock-', 'atmosphera-lock-', 'locker-orphan-proof-'))):
                emit('journal', sourceMonotonic=int(record['__MONOTONIC_TIMESTAMP']) / 1_000_000,
                     invocation=record.get('_SYSTEMD_INVOCATION_ID', ''), unit=unit, message=message)

    def read_journal(channel, condition):
        if condition & GLib.IO_IN:
            chunk = os.read(journal.stdout.fileno(), 262144)
            if chunk:
                consume_journal(chunk)
                return True
        if condition & (GLib.IO_HUP | GLib.IO_ERR):
            emit('observer-error', message='journal follower exited unexpectedly')
            loop.quit()
            return False
        return True

    def sample():
        try:
            emit('units', view=manage(source, {'operation': 'inspect', 'session': sid}))
        except Exception as error:
            emit('observer-error', message=str(error))
            loop.quit()
            return False
        return True

    def closed(channel, condition):
        if condition & GLib.IO_IN:
            if os.read(sys.stdin.fileno(), 4096):
                return True
        loop.quit()
        return False

    GLib.io_add_watch(journal.stdout.fileno(), GLib.IO_IN | GLib.IO_HUP | GLib.IO_ERR, read_journal)
    GLib.io_add_watch(sys.stdin.fileno(), GLib.IO_IN | GLib.IO_HUP | GLib.IO_ERR, closed)
    GLib.timeout_add(500, sample)
    GLib.timeout_add(50, read_compositor)
    signal.signal(signal.SIGTERM, lambda *_: loop.quit())
    try:
        sample()
        (work / 'ready.json').write_text(json.dumps({'session': sid, 'monotonic': time.monotonic(), 'pid': os.getpid(),
                                                    'compositor': compositor_identity}))
        loop.run()
        sample()
    finally:
        journal.terminate()
        # journalctl flushes buffered records on termination. Waiting without
        # draining its pipe can deadlock once that final batch fills the pipe.
        remaining, _ = journal.communicate(timeout=10)
        consume_journal(remaining)
        read_compositor()
        if compositor_stream is not None:
            compositor_stream.close()
        journal_errors.close()
        emit('end')
        output.close()


if __name__ == '__main__':
    main()
