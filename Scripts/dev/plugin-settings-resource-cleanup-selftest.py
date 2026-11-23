#!/usr/bin/env python3
"""Fault injection at the actual driver boundary; no guest services or accounts."""
from contextlib import ExitStack
import importlib.util
from io import BytesIO
import shutil
import sys
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
    def test_guard_capture_refusal_reaps_direct_child(self):
        for name in ('host-assets-regression', 'niri-lifetime-regression', 'changed-lint', 'registry'):
            with self.subTest(driver=name), tempfile.TemporaryDirectory() as tmp, ExitStack() as stubs:
                module = load('plugin-settings-' + (name if name != 'registry' else 'host-assets-regression'))
                root = Path(tmp)
                args = SimpleNamespace(source=root/'source', plugins=root/'plugins', work_root=root/'work',
                                       output=root/'out', guest_profile=None, baseline_source=None, baseline_plugins=None)
                for path in (args.source, args.plugins, args.work_root, args.output): path.mkdir()
                profile = SimpleNamespace(child_environment=lambda _: {}, work_base=root, journal_base=root,
                                          runtime_base=root, prepare_roots=lambda: None)
                events, logs = [], []
                failure = SetupFailure('guard capture refused')

                def spawn(*argv, stdout, **kwargs):
                    events.append('spawn'); logs.append(stdout)
                    return SimpleNamespace(terminate=lambda: events.append('terminate'),
                                           wait=lambda **kw: events.append('wait'))

                def refuse(_proc):
                    events.append('guard')
                    raise failure

                stubs.enter_context(patch('subprocess.Popen', side_effect=spawn))
                stubs.enter_context(patch('guest_profile.OwnedProcessGuard', side_effect=refuse))
                with self.assertRaises(SetupFailure) as raised:
                    if name == 'host-assets-regression':
                        module.run_fixture(profile, args.source, args.work_root, args.output, root/'fixture', installed=True)
                    elif name == 'registry':
                        stubs.enter_context(patch.object(module, 'final_steps', return_value=[('stub', ['never-exec'], root, 1)]))
                        module.run_registry_case(args, profile, 'test-case', [], lambda _: None)
                    elif name == 'niri-lifetime-regression':
                        (args.work_root/'bin').mkdir()
                        module.python_children(args, args.work_root, args.output)
                    else:
                        args.work_root = root/'lint-work'; args.output = root/'lint-out'
                        stubs.enter_context(patch('argparse.ArgumentParser.parse_args', return_value=args))
                        stubs.enter_context(patch.object(module, 'activate_profile', return_value=profile))
                        stubs.enter_context(patch.object(module, 'changed', return_value=['a.qml']))
                        stubs.enter_context(patch.object(module, 'load', return_value=SimpleNamespace(qs_imports=lambda _: ())))
                        module.main()
                self.assertIs(raised.exception, failure)
                self.assertEqual(events, ['spawn', 'guard', 'terminate', 'wait'])
                self.assertTrue(logs[0].closed)

    def test_private_bus_setup_failure_reaps_process_and_log(self):
        lanes = {'automatic-lifecycle': ('private-monitor',), 'device-lifecycle': ('gpu-test',),
                 'device-native': ('noctalia-supergfxctl', 'instance')}
        for name, call in lanes.items():
            with self.subTest(driver=name), tempfile.TemporaryDirectory() as tmp, ExitStack() as stubs:
                driver = load('plugin-settings-' + name + '-regression')
                root = Path(tmp)
                args = SimpleNamespace(work_root=root/'work', output=root/'out', source=root/'shell', plugins=root/'plugins',
                                       control=None, original_plugins=None)
                for path in (args.work_root, args.output, args.source, args.plugins): path.mkdir()
                events, logs = [], []
                failure = SetupFailure('post-start bus setup failed')
                proc = SimpleNamespace(pid=1 << 30, terminate=lambda: events.append('terminate'),
                                       wait=lambda **kw: events.append('wait'))

                def spawn(*argv, stdout, **kwargs):
                    events.append('spawn'); logs.append(stdout); self.addCleanup(stdout.close)
                    socket = Path(argv[0][-1].split('=', 2)[-1]); socket.touch()
                    return proc

                def copy(_source, dest, **kwargs):
                    dest.mkdir(parents=True)

                write, read = Path.write_text, Path.read_text

                def write_path(path, *argv, **kwargs):
                    if path.name == 'peer.py': raise failure
                    return write(path, *argv, **kwargs)

                def read_path(path, *argv, **kwargs):
                    if path == Path('/proc')/str(proc.pid)/'stat': raise failure
                    return read(path, *argv, **kwargs)

                for obj, attr, fn in ((shutil, 'copytree', copy), (Path, 'write_text', write_path),
                                      (Path, 'read_text', read_path)):
                    stubs.enter_context(patch.object(obj, attr, fn))
                stubs.enter_context(patch('subprocess.Popen', side_effect=spawn))
                stubs.enter_context(patch('guest_profile.OwnedProcessGuard', return_value=proc))
                with self.assertRaises(SetupFailure) as raised:
                    driver.run(args, SimpleNamespace(work_base=root), *call)
                self.assertIs(raised.exception, failure)
                self.assertEqual(events, ['spawn', 'terminate', 'wait'])
                self.assertTrue(logs[0].closed)

    def test_lock_journal_failure_cannot_skip_credential_or_recovery(self):
        driver = load('plugin-settings-lock-focus-regression')
        failure = CleanupFailure('optional native journal unavailable')
        events = []

        def capture():
            events.append('capture')
            raise failure

        with self.assertRaises(CleanupFailure) as raised:
            with driver.variant_cleanup(capture=capture, credential_or_recovery=lambda: events.append('credential'),
                                        finish_background=lambda: events.append('background'),
                                        background_owner=SimpleNamespace(close=lambda: events.append('reap')),
                                        remove_configs=lambda: events.append('configs'), verify=lambda: events.append('verify')):
                pass
        self.assertIs(raised.exception, failure)
        self.assertEqual(events, ['capture', 'credential', 'background', 'reap', 'configs', 'verify'])

    def test_hermes_server_failure_drains_exact_child_worker_and_logs(self):
        for capture_fails in (True, False):
            with self.subTest(capture_fails=capture_fails), tempfile.TemporaryDirectory() as tmp, ExitStack() as stubs:
                driver = load('plugin-settings-hermes-child-regression')
                root = Path(tmp)
                args = SimpleNamespace(work_root=root/'work', output=root/'out', source=root/'shell',
                                       plugins=root/'plugins', guest_profile=None, main_destruction=False)
                script = args.plugins/'hermes-agent/scripts/hermes_bridge.py'
                script.parent.mkdir(parents=True)
                script.write_text('httpd.command_runner = run_owned_command')
                events, logs = [], []
                setup = SetupFailure('Hermes post-spawn setup')
                wait_error = CleanupFailure('Hermes server wait')
                parent, child = {'pid': 100}, {'pid': 101, 'argv': []}

                def spawn(*args, stdout, stderr, **kwargs):
                    logs.extend((stdout, stderr))
                    return SimpleNamespace(pid=parent['pid'], poll=lambda: None,
                                           terminate=lambda: events.append('terminate'), wait=wait)

                def wait(*args, **kwargs):
                    events.append('wait')
                    if not capture_fails: raise wait_error

                def observe(_pid):
                    if capture_fails: raise setup
                    return parent

                def observe_until(_check, message, *args, **kwargs):
                    if message == 'server token': return 'stub'
                    if message == 'actual CLI child': raise setup
                    if message == 'exact synthetic cleanup': return True
                    raise AssertionError(message)

                def cmdline(path):
                    return bytes(args.work_root/'oneshot-complete/literal hermes cli') + b'\0'

                profile = SimpleNamespace(work_base=root, journal_base=root, prepare_roots=lambda: None)
                worker = SimpleNamespace(start=lambda: events.append('start-worker'),
                                         join=lambda **kw: events.append('join-worker'), is_alive=lambda: False)
                for obj, attr, fn in ((driver, 'identity', observe), (driver, 'wait_for', observe_until),
                                      (driver, 'load_record', lambda _: child), (driver, 'alive', lambda _: True),
                                      (Path, 'read_bytes', cmdline), ('os', 'kill', None)):
                    if obj == 'os':
                        stubs.enter_context(patch('os.kill', side_effect=lambda pid, _: events.append(('stop-exact', pid))))
                    else:
                        stubs.enter_context(patch.object(obj, attr, fn))
                stubs.enter_context(patch('argparse.ArgumentParser.parse_args', return_value=args))
                stubs.enter_context(patch.object(driver, 'activate_profile', return_value=profile))
                stubs.enter_context(patch('threading.Thread', return_value=worker))
                stubs.enter_context(patch('subprocess.Popen', side_effect=spawn))
                with self.assertRaises((SetupFailure, CleanupFailure, BaseExceptionGroup)) as raised:
                    driver.main()
                self.assertIs(leaves(raised.exception)[0], setup)
                self.assertEqual(events, ['terminate', 'wait', ('stop-exact', 101)] if capture_fails else
                                 ['start-worker', 'terminate', 'wait', ('stop-exact', 101), 'join-worker'])
                self.assertTrue(all(log.closed for log in logs))

    def test_hermes_pty_wait_failure_drains_pipes_and_exact_child(self):
        driver = load('plugin-settings-hermes-helper-regression')
        with tempfile.TemporaryDirectory() as tmp, ExitStack() as stubs:
            root = Path(tmp)
            args = SimpleNamespace(work_root=root/'work', output=root/'out', original_red=False)
            args.work_root.mkdir(); args.output.mkdir()
            child = {'pid': 101}
            events = []
            failure = CleanupFailure('PTY helper wait failed')

            def spawn(*argv, **kwargs):
                (args.work_root/'parent-race/child.json').write_text('{"pid":101}')
                return process

            def fail_wait(*argv, **kwargs):
                events.append('wait')
                raise failure

            process = SimpleNamespace(stdin=BytesIO(), stdout=BytesIO(), stderr=BytesIO(), poll=lambda: None,
                                      wait=fail_wait, terminate=lambda: events.append('terminate'))
            stubs.enter_context(patch('subprocess.Popen', side_effect=spawn))
            stubs.enter_context(patch('guest_profile.OwnedProcessGuard', return_value=process))
            stubs.enter_context(patch.object(driver, 'cleanup', side_effect=lambda record: events.append(record)))
            stubs.enter_context(patch.object(driver, 'state', return_value='gone'))
            with self.assertRaises((CleanupFailure, AssertionError, BaseExceptionGroup)) as raised:
                driver.run(args, root/'inert-helper', 'parent-race')
            self.assertIn(failure, leaves(raised.exception))
            self.assertEqual(events, ['terminate', 'wait', child])
            self.assertTrue(all(stream.closed for stream in (process.stdin, process.stdout, process.stderr)))
            self.assertTrue((args.output/'parent-race/result.json').is_file())

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

    def test_remaining_http_owners(self):
        lanes = ('http-lifecycle', 'model-lifecycle', 'prayer-lifecycle', 'spotify',
                 'hermes-agent', 'runtime-writers', 'assistant-lifetime')
        for name in lanes:
            with self.subTest(driver=name), tempfile.TemporaryDirectory() as temporary, ExitStack() as stubs:
                events = []
                failure = SetupFailure(name)
                root = Path(temporary)
                args = SimpleNamespace(source=root/'source', plugins=root/'plugins',
                                       work_root=root/'work', output=root/'out',
                                       installed=root/'installed', guest_profile=None,
                                       negative_control=False, original_plugins=None,
                                       lease_key_control=False, environment_precedence=False)
                for directory in (args.source, args.plugins, args.installed):
                    directory.mkdir()
                profile = SimpleNamespace(work_base=root, journal_base=root, prepare_roots=lambda: None)

                class Server:
                    def serve_forever(self):
                        raise AssertionError('inert worker must not serve')

                    @property
                    def server_address(self):
                        raise failure

                    server_port = property(lambda self: self.server_address[1])

                    def shutdown(self):
                        events.append('shutdown')
                        if name == 'assistant-lifetime':
                            raise CleanupFailure('assistant shutdown failed')

                    def server_close(self):
                        events.append('close')

                    def __enter__(self):
                        return self

                    def __exit__(self, *args):
                        self.server_close()

                worker = SimpleNamespace(start=lambda: events.append('start'),
                                         join=lambda **kw: events.append('join'),
                                         is_alive=lambda: False)
                stubs.enter_context(patch('threading.Thread', return_value=worker))
                stubs.enter_context(patch.object(shutil, 'copytree'))
                script = ('settings-plugin-runtime-writers' if name == 'runtime-writers'
                          else 'plugin-settings-' + name + '-regression')
                driver = load(script)
                if name == 'assistant-lifetime':
                    stubs.enter_context(patch.object(driver, 'HTTPServer', return_value=Server()))
                elif name == 'hermes-agent':
                    # The second constructor fails only after the first starts.
                    class PeerBase(Server):
                        def __init__(self, *args):
                            if events:
                                raise failure

                    stubs.enter_context(patch.object(driver, 'Peer', PeerBase))
                else:
                    stubs.enter_context(patch.object(driver, 'ThreadingHTTPServer', return_value=Server()))

                if name in ('model-lifecycle', 'prayer-lifecycle', 'runtime-writers'):
                    if name == 'runtime-writers':
                        stubs.enter_context(patch('subprocess.check_output',
                                                  return_value=b'12f17a02-25e9-474c-9dae-fea092c2d2be'))
                        # Supply an owned synthetic root; fail at the first write to an acquired probe.
                        stubs.enter_context(patch.object(Path, 'is_relative_to', return_value=True))
                        fixture_dir = args.source/'Scripts/dev/fixtures'
                        fixture_dir.mkdir(parents=True)
                        (fixture_dir/'plugin-runtime-writers.qml').write_text('fixture')

                        class FailingProbe:
                            def __enter__(self): return self
                            def __exit__(self, *args): pass
                            def write(self, data): raise failure

                        open_path = Path.open
                        def open_file(path, mode='r', *argv, **kwargs):
                            if mode == 'xb':
                                open_path(path, mode).close()
                                return FailingProbe()
                            return open_path(path, mode, *argv, **kwargs)

                        stubs.enter_context(patch.object(Path, 'open', open_file))
                        stubs.enter_context(patch.object(sys, 'argv', [script, '--source', str(args.source),
                            '--plugins', str(args.plugins), '--installed', str(args.installed),
                            '--work-root', str(args.work_root), '--output', str(args.output)]))
                    else:
                        stubs.enter_context(patch.object(driver.argparse.ArgumentParser, 'parse_args', return_value=args))
                        stubs.enter_context(patch.object(driver, 'activate_profile', return_value=profile))
                        stubs.enter_context(patch.object(driver, '__file__', str(args.source/'Scripts/dev'/ (script+'.py'))))
                    invoke = driver.main
                elif name == 'assistant-lifetime':
                    def invoke():
                        with driver.local_response('chat-http', root):
                            self.fail('injection was not reached')
                else:
                    args.work_root.mkdir(); args.output.mkdir()
                    variant = {'http-lifecycle': 'news', 'spotify': 'shared', 'hermes-agent': 'pending'}[name]
                    def invoke():
                        driver.run(args, profile, variant)

                with self.assertRaises((SetupFailure, CleanupFailure, BaseExceptionGroup)) as raised:
                    invoke()
                self.assertEqual(events, ['start', 'shutdown', 'join', 'close'])
                self.assertIs(leaves(raised.exception)[0], failure)
                self.assertFalse((args.installed/'i5-runtime-writers.qml').exists())

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
