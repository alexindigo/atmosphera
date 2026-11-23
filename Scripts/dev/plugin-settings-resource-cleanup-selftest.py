#!/usr/bin/env python3
"""Fault injection at the actual driver boundary; no guest services or accounts."""
from contextlib import ExitStack
import importlib.util
import shutil
import tempfile
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from fixture_resources import FixtureResources

class SetupFailure(Exception):
    pass


class CleanupFailure(Exception):
    pass


def load(name):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).parent / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def leaves(error):
    if isinstance(error, BaseExceptionGroup):
        return [leaf for member in error.exceptions for leaf in leaves(member)]
    return [error]


class CleanupTests(unittest.TestCase):
    def socket_driver(self, name, driver_args, close_fails=False, start_fails=False):
        driver = load('plugin-settings-' + name + '-regression')
        events = []
        setup_error = SetupFailure('post-start setup')
        cleanup_error = CleanupFailure('server shutdown')

        class Endpoint:
            def serve_forever(self):
                raise AssertionError('inert worker must not actually serve')

            def shutdown(self):
                events.append('shutdown')
                if close_fails:
                    raise cleanup_error

            finish = shutdown

            def server_close(self):
                events.append('close')

            @property
            def server_address(self):
                events.append('setup')
                raise setup_error

        class Worker:
            def start(self):
                events.append('start')
                if start_fails:
                    raise setup_error

            def join(self, **kwargs):
                events.append('join')

            def is_alive(self):
                return False

        with tempfile.TemporaryDirectory() as temporary, ExitStack() as stubs:
            root = Path(temporary)
            args = SimpleNamespace(work_root=root/'work', output=root/'output', source=root/'shell',
                                   plugins=root/'plugins', original_plugins=None, shared_reader=False,
                                   control=None, expect_handoff_red=False)
            for directory in (args.work_root, args.output, args.source, args.plugins):
                directory.mkdir()
            dest = args.plugins/'hassio'
            dest.mkdir()
            (dest/'manifest.json').write_text('{"metadata":{"defaultSettings":{}}}')
            stubs.enter_context(patch('threading.Thread', return_value=Worker()))
            if name.startswith('obs'):
                obs = driver.obs if name.endswith('lifetime') else driver
                stubs.enter_context(patch.object(obs, 'ObsEndpoint', return_value=Endpoint()))
                stubs.enter_context(patch.object(obs, 'seed', return_value=root))
                stubs.enter_context(patch.object(shutil, 'copy2'))
            elif name == 'query-lifecycle':
                stubs.enter_context(patch.object(driver, 'HassEndpoint', return_value=Endpoint()))
            elif name == 'http':
                stubs.enter_context(patch.object(driver, 'ThreadingHTTPServer', return_value=Endpoint()))
            elif name == 'sticky':
                fixture = args.plugins/'sticky-notes'/'utils'
                fixture.mkdir(parents=True)
                (fixture/'gistSync.js').write_text('var API_BASE_URL = "https://api.github.com";')
                Endpoint.server_port = property(lambda self: self.server_address[1])
                stubs.enter_context(patch.object(driver, 'ThreadingHTTPServer', return_value=Endpoint()))
            with self.assertRaises((SetupFailure, BaseExceptionGroup)) as raised:
                driver.run(args, None, *driver_args)

        self.assertEqual(events, ['start', 'close'] if start_fails else
                         ['start', 'setup', 'shutdown', 'join', 'close'])
        if close_fails:
            self.assertIn(cleanup_error, leaves(raised.exception))
        else:
            self.assertIs(raised.exception, setup_error)
        self.assertIs(leaves(raised.exception)[0], setup_error)

    def test_post_start_setup(self):
        for name, args in (('obs', ('shared',)), ('obs-lifetime', ('typed',)),
                           ('query-lifecycle', ('hassio',)), ('sticky', ('shared', 'native')),
                           ('http', ('news', 'shared'))):
            with self.subTest(driver=name):
                self.socket_driver(name, args)

    def test_obs_preserves_primary_and_drains_remaining_cleanup(self):
        self.socket_driver('obs-lifetime', ('typed',), close_fails=True)

    def test_obs_bind_is_closed_when_start_fails(self):
        self.socket_driver('obs-lifetime', ('typed',), start_fails=True)

    def private_bus_driver(self, name, setup_fails):
        driver = load('fixtures/plugin-settings-' + name + '-peer')
        events = []
        logs = []
        setup_error = SetupFailure('private bus connection failed')
        close_error = CleanupFailure('private bus close_sync failed')

        def close(_cancellable):
            events.append('close')
            if events.count('close') == 1:
                raise close_error

        def connect(*args):
            events.append('connect')
            if setup_fails:
                raise setup_error
            return SimpleNamespace(close_sync=close, register_object=lambda *args: None,
                                    call_sync=lambda *args: SimpleNamespace(unpack=lambda: (1,)))

        def start(*args, stdout, **kwargs):
            events.append('spawn')
            self.assertFalse(stdout.closed)
            logs.append(stdout)
            self.addCleanup(stdout.close)
            return SimpleNamespace(wait=lambda **kw: events.append('reap'))

        def guard(_process):
            events.append('guard')
            return SimpleNamespace(terminate=lambda: events.append('terminate'))

        flags = SimpleNamespace(AUTHENTICATION_CLIENT=1, MESSAGE_BUS_CONNECTION=2)
        gio = SimpleNamespace(DBusConnection=SimpleNamespace(new_for_address_sync=connect),
                              DBusConnectionFlags=flags, DBusCallFlags=SimpleNamespace(NONE=0),
                              DBusNodeInfo=SimpleNamespace(new_for_xml=lambda _: SimpleNamespace(interfaces=[None])))
        loop = SimpleNamespace(run=lambda: None, quit=lambda: events.append('quit'))
        glib = SimpleNamespace(Variant=lambda *args: None, MainLoop=lambda: loop,
                               idle_add=lambda callback: callback(), timeout_add=lambda *args: 1,
                               source_remove=lambda _: None)
        worker = SimpleNamespace(start=lambda: events.append('start'),
                                 join=lambda **kw: events.append('join'), is_alive=lambda: False)

        with tempfile.TemporaryDirectory() as temporary:
            case = Path(temporary)
            (case / (name + '-bus')).touch()
            with patch.object(driver, 'Gio', gio), patch.object(driver, 'GLib', glib), \
                 patch('subprocess.Popen', side_effect=start), patch('threading.Thread', return_value=worker):
                with self.assertRaises((SetupFailure, CleanupFailure, BaseExceptionGroup)) as raised:
                    with FixtureResources() as resources:
                        driver.Fixture(case, case, resources, guard_factory=guard)

        self.assertIs(leaves(raised.exception)[0], setup_error if setup_fails else close_error)
        self.assertEqual(events[-2:], ['terminate', 'reap'])
        self.assertEqual(len(logs), 1)
        self.assertTrue(logs[0].closed)
        if not setup_fails:
            self.assertIn('join', events)
            self.assertEqual(events.count('close'), 1 if name == 'upower' else 3)

    def test_private_bus_connection_failure_and_close_failure(self):
        for name in ('upower', 'mpris'):
            for setup_fails in (True, False):
                with self.subTest(bus=name, setup_fails=setup_fails):
                    self.private_bus_driver(name, setup_fails)


if __name__ == '__main__':
    unittest.main()
