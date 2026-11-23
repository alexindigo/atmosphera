#!/usr/bin/env python3
"""Real MPRIS protocol peers on a private, disk-backed guest session bus."""
import json
from pathlib import Path
import subprocess
import time

import gi
gi.require_version('Gio', '2.0')
from gi.repository import Gio, GLib

ROOT = 'org.mpris.MediaPlayer2'
PLAYER = ROOT + '.Player'
PATH = '/org/mpris/MediaPlayer2'


class Peer:
    def __init__(self, fixture, label, resources):
        self.fixture, self.label = fixture, label
        self.bus = Gio.DBusConnection.new_for_address_sync(fixture.address,
            Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION, None, None)
        resources.defer(self.bus.close_sync, None)
        self.props = {
            ROOT: dict(Identity=('s', 'query-' + label), DesktopEntry=('s', 'query-' + label), CanQuit=('b', False), CanRaise=('b', False), HasTrackList=('b', False), SupportedUriSchemes=('as', []), SupportedMimeTypes=('as', [])),
            PLAYER: dict(PlaybackStatus=('s', 'Playing'), LoopStatus=('s', 'None'), Rate=('d', 1.0), Shuffle=('b', False), Volume=('d', 1.0), Position=('x', 5000000), MinimumRate=('d', 1.0), MaximumRate=('d', 1.0),
                         **{key: ('b', True) for key in ('CanGoNext', 'CanGoPrevious', 'CanPlay', 'CanPause', 'CanSeek', 'CanControl')})}
        self.props[PLAYER]['Metadata'] = ('a{sv}', self.metadata(label))
        for interface, props in self.props.items():
            methods = ''.join('<method name="' + name + '"/>' for name in (('Raise', 'Quit') if interface == ROOT else ('Next', 'Previous', 'Pause', 'PlayPause', 'Stop', 'Play')))
            xml = '<node><interface name="' + interface + '">' + methods
            xml += ''.join('<property name="' + name + '" type="' + signature + '" access="read"/>' for name, (signature, _) in props.items())
            xml += '</interface></node>'
            info = Gio.DBusNodeInfo.new_for_xml(xml).interfaces[0]
            self.bus.register_object(PATH, info, self.method, self.get, None)
        response = self.bus.call_sync('org.freedesktop.DBus', '/org/freedesktop/DBus', 'org.freedesktop.DBus', 'RequestName', GLib.Variant('(su)', (ROOT + '.query_' + label, 4)), None, Gio.DBusCallFlags.NONE, 3000, None)
        if response.unpack() != (1,):
            raise RuntimeError('private player name unavailable')

    def metadata(self, label):
        return {'mpris:trackid': GLib.Variant('o', '/track/' + self.label), 'mpris:length': GLib.Variant('x', 60000000),
                'xesam:title': GLib.Variant('s', label + ' track'), 'xesam:artist': GLib.Variant('as', ['controlled']),
                'xesam:asText': GLib.Variant('s', '[00:00.00]' + label + ' lyric\n[01:00.00]' + label + ' next')}

    def get(self, _bus, _sender, _path, interface, name):
        signature, value = self.props[interface][name]
        return GLib.Variant(signature, value)

    def change(self, values):
        changed = {}
        for name, value in values.items():
            signature = self.props[PLAYER][name][0]
            self.props[PLAYER][name] = signature, value
            changed[name] = GLib.Variant(signature, value)
        self.bus.emit_signal(None, PATH, 'org.freedesktop.DBus.Properties', 'PropertiesChanged', GLib.Variant('(sa{sv}as)', (PLAYER, changed, [])))

    def method(self, _bus, _sender, _path, interface, method, _params, invocation):
        self.fixture.record(player=self.label, interface=interface, method=method)
        if method == 'Pause':
            self.change(dict(PlaybackStatus='Paused'))
        elif method == 'Play':
            self.change(dict(PlaybackStatus='Playing'))
        invocation.return_value(GLib.Variant('()', ()))


class Fixture:
    def __init__(self, case, runtime, resources, **process_options):
        self.case = case
        self.address = 'unix:path=' + str(runtime / 'mpris-bus')
        log = resources.open(case / 'bus.log', 'w')
        daemon = resources.spawn(['dbus-daemon', '--session', '--nofork', '--address=' + self.address],
                                 stdout=log, stderr=subprocess.STDOUT, **process_options)
        deadline = time.monotonic() + 5
        while not (runtime / 'mpris-bus').exists():
            if daemon.poll() is not None or time.monotonic() > deadline:
                raise RuntimeError('private disk bus did not become ready')
            time.sleep(0.02)
        self.peers = {label: Peer(self, label, resources) for label in ('base', 'old', 'new')}
        loop = GLib.MainLoop()
        resources.defer(GLib.source_remove, GLib.timeout_add(20, self.control))
        resources.thread(loop.run, stop=lambda: GLib.idle_add(loop.quit))

    def record(self, **row):
        with (self.case / 'mpris.jsonl').open('a') as stream:
            stream.write(json.dumps(row) + '\n')

    def control(self):
        if (self.case / 'mpris-old-event').exists() and (self.case / 'mpris-old-event-done').read_text() != 'delivered':
            self.peers['old'].change(dict(Metadata=self.peers['old'].metadata('obsolete')))
            self.record(player='old', event='late-metadata')
            (self.case / 'mpris-old-event-done').write_text('delivered')
        return True
