#!/usr/bin/env python3
"""Guest-only controls for fixture publication, observation and cleanup contracts."""
import argparse
import ast
import errno
import json
import os
from pathlib import Path
import runpy
import sys
from types import SimpleNamespace
from unittest.mock import patch

import locker_sleep_support as sleep
import locker_test_support as support


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, required=True)
    args = parser.parse_args()
    source, work = support.require_guest(args.work, Path(__file__).resolve().parents[2])
    rows = []

    def check(name, function):
        try:
            function()
            row = dict(name=name, passed=True)
        except Exception as error:
            row = dict(name=name, passed=False, error=repr(error))
        rows.append(row)
        print(json.dumps(row), flush=True)

    def atomic_fixture(name, expected):
        case = work / name
        case.mkdir()
        (case / 'release').touch()
        (case / 'release-sleep-service').touch()
        writes = []
        original = Path.write_text
        def write(path, text, *args, **kwargs):
            writes.append(path.name)
            return original(path, text, *args, **kwargs)
        script = source / 'Scripts/dev/fixtures' / name
        argv = [str(script), '--work', str(case)]
        if 'memory' in name:
            argv += ['--mib', '1']
        with patch.object(sys, 'argv', argv), patch.object(Path, 'write_text', write):
            runpy.run_path(str(script), run_name='__main__')
        for filename in expected:
            assert json.loads((case / filename).read_text())
            assert filename not in writes, 'final readiness path written before complete publication'

    check('atomic-resident-report', lambda: atomic_fixture('locker-memory-pressure.py', ['resident.json']))
    check('atomic-sleep-reports', lambda: atomic_fixture('locker-sleep-service.py', ['sleep-service-entered.json', 'sleep-service-finished.json']))

    def initial_notification_keeps_same_chunk():
        import importlib.util
        spec = importlib.util.spec_from_file_location('locker_observer', source / 'Scripts/dev/locker-compositor-observer.py')
        observer = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(observer)
        read, write = os.pipe()
        try:
            os.write(write, b'{"kind":"compositor-initial","locked":false}\n{"kind":"compositor-lock","locked":true}\n')
            pending = bytearray()
            initial = observer.read_initial_notification(read, pending, 1)
            assert initial == {'kind': 'compositor-initial', 'locked': False}
            assert json.loads(bytes(pending).splitlines()[0]) == {'kind': 'compositor-lock', 'locked': True}, 'lock record lost'
        finally:
            os.close(read)
            os.close(write)
    check('observer-initial-keeps-same-chunk-lock', initial_notification_keeps_same_chunk)

    def partial_events():
        case = work / 'events'
        case.mkdir()
        harness = sleep.SleepHarness.__new__(sleep.SleepHarness)
        harness.work = case
        (case / 'inhibitor-events.jsonl').write_text('{"value":{"event":"acquired"}}\n{"value":')
        assert harness.events() == [{'value': {'event': 'acquired'}}]
    check('partial-event-tail', partial_events)

    def delayed_release():
        case = work / 'released'
        case.mkdir()
        harness = sleep.SleepHarness.__new__(sleep.SleepHarness)
        harness.work, harness.pid = case, 123
        (case / 'sleep-service-entered.json').write_text('{"monotonic":3}')
        event = {'pid': 123, 'value': {'event': 'released', 'secure': True, 'monotonic': 4, 'closeMonotonic': 2}}
        calls = []
        harness.events = lambda: calls.append(1) or ([] if len(calls) == 1 else [event])
        harness.inhibitors = lambda pid: []
        harness.entered(1)
        assert len(calls) >= 2 and (case / 'inhibitor-ordering.json').exists()
    check('delayed-release-receipt', delayed_release)

    def cleanup(foreign=False):
        case = work / ('foreign-override' if foreign else 'owned-override')
        case.mkdir()
        harness = sleep.SleepHarness.__new__(sleep.SleepHarness)
        harness.work, harness.installed = case, True
        harness.override = case / 'override.conf'
        harness.content, harness.original = 'owned', 'original'
        harness.override.write_text('foreign' if foreign else harness.content)
        commands = []
        def run(command):
            commands.append(command)
            if command[:4] == ['sudo', '-n', 'rm', '--']:
                Path(command[-1]).unlink()
            return SimpleNamespace(stdout='original')
        with patch.object(sleep, 'run', run), patch.object(sleep, 'wait_for', side_effect=TimeoutError('delayed service')):
            try:
                harness.close()
            except TimeoutError:
                pass
            except AssertionError as error:
                assert foreign and str(error) == 'sleep fixture changed ownership'
        assert harness.override.exists() == foreign
        if not foreign:
            assert ['sudo', '-n', 'systemctl', 'daemon-reload'] in commands
    check('cleanup-after-wait-failure', cleanup)
    check('foreign-override-preserved', lambda: cleanup(True))

    def removed_cgroup(code):
        fake = SimpleNamespace(read_text=lambda: (_ for _ in ()).throw(OSError(code, 'removed')))
        with patch.object(Path, 'rglob', return_value=[fake]):
            try:
                result = support.cgroup_pids(work)
            except OSError as error:
                assert code == errno.EACCES and error.errno == code
            else:
                assert code != errno.EACCES and result == []
    for code in (errno.ENOENT, errno.ENODEV, errno.EACCES):
        check('cgroup-errno-' + str(code), lambda code=code: removed_cgroup(code))

    def delays(case, explicit=None):
        path = source / 'Scripts/dev/locker-lifecycle-regression.py'
        node = next(n for n in ast.parse(path.read_text()).body if isinstance(n, ast.FunctionDef) and n.name == 'main')
        statements = []
        for statement in node.body:
            if isinstance(statement, ast.If) and isinstance(statement.test, ast.Attribute) and statement.test.attr == 'real_suspend':
                break
            statements.append(statement)
        env = dict(argparse=argparse, Path=Path, __file__=str(path))
        argv = [str(path), '--case', case, '--work', str(work / 'unused')]
        if explicit:
            argv += ['--delays', explicit]
        with patch.object(sys, 'argv', argv):
            exec(compile(ast.Module(body=statements, type_ignores=[]), str(path), 'exec'), env)
        return env['args'].delays
    def defaults():
        assert delays('suspend') == '0,5,40'
        assert delays('boundary') == '2.9,3.0,3.1,29.9,30.0,30.1'
        assert delays('suspend', '5') == '5'
    check('case-specific-delay-defaults', defaults)

    def unreleased_sleep():
        case = work / 'unreleased-sleep'
        case.mkdir()
        script = source / 'Scripts/dev/fixtures/locker-sleep-service.py'
        with patch.object(sys, 'argv', [str(script), '--work', str(case)]), \
                patch('time.monotonic', side_effect=[0, 0, 61, 62]):
            try:
                runpy.run_path(str(script), run_name='__main__')
            except SystemExit as error:
                assert error.code != 0
            else:
                raise AssertionError('unreleased sleep barrier succeeded')
        assert not json.loads((case / 'sleep-service-finished.json').read_text())['released']
    check('unreleased-sleep-barrier-fails', unreleased_sleep)

    def literal_sleep_paths():
        case = work / 'space $literal %specifier'
        case.mkdir()
        harness = sleep.SleepHarness.__new__(sleep.SleepHarness)
        harness.source, harness.work = case / 'source with spaces', case
        harness.override, harness.installed = case / 'override', False
        harness.original = 'original'
        def run(command):
            return SimpleNamespace(stdout='inactive' if 'ActiveState' in command else
                str(harness.source / 'Scripts/dev/fixtures/locker-sleep-service.py'))
        with patch.object(sleep, 'run', run):
            harness.install()
        text = (case / 'sleep-service-override.conf').read_text()
        assert '"' + str(case).replace('$', '$$').replace('%', '%%') + '"' in text
        assert 'source with spaces/Scripts/dev/fixtures/locker-sleep-service.py"' in text
    check('literal-systemd-sleep-paths', literal_sleep_paths)

    def spectrum_readiness():
        text = (source / 'Quickshell/atmosphera-lockscreen/LockSession.qml').read_text()
        function = '  function registerSpectrumIfWanted() {' + text.split(
            '  function registerSpectrumIfWanted() {', 1)[1].split('\n  }', 1)[0] + '\n  }'
        function = function.replace('Settings.', 'settings.').replace('SpectrumService.', 'spectrum.')
        qml = '''import QtQuick
import Quickshell
ShellRoot {
  property bool _settingsReady: false
  property bool _spectrumRegistered: false
  QtObject { id: client; property bool terminal: false }
  QtObject { id: settings; property var data: ({general: {enableLockScreenMediaControls: true,
    compactLockScreen: false}, audio: {visualizerType: "wave"}}) }
  QtObject { id: spectrum; property int calls: 0; function registerComponent(name) { calls++; } }
''' + function + '''
  Timer { interval: 0; running: true; onTriggered: {
    registerSpectrumIfWanted();
    if (spectrum.calls !== 0) { Qt.exit(1); return; }
    _settingsReady = true;
    registerSpectrumIfWanted(); registerSpectrumIfWanted();
    if (spectrum.calls !== 1) { Qt.exit(2); return; }
    _spectrumRegistered = false; client.terminal = true;
    registerSpectrumIfWanted();
    if (spectrum.calls !== 1) { Qt.exit(3); return; }
    console.log("SPECTRUM_READINESS_PASS"); Qt.quit();
  } }
}
'''
        case = work / 'spectrum'
        case.mkdir()
        (case / 'shell.qml').write_text(qml)
        result = support.run(['qs', '-p', str(case), '--no-color'], env=dict(os.environ, QT_QPA_PLATFORM='offscreen'))
        (case / 'output.txt').write_text(result.stdout + result.stderr)
        assert 'SPECTRUM_READINESS_PASS' in result.stdout + result.stderr
    check('actual-spectrum-registration-settings-terminal-idempotence', spectrum_readiness)

    def pinned_child(exited=False):
        sent, validated, closed = [], [], []
        readiness = [([55], [], [])] if exited else [([], [], []), ([55], [], [])]
        with patch.object(support.os, 'pidfd_open', return_value=55), \
                patch.object(support.select, 'select', side_effect=readiness), \
                patch.object(support.signal, 'pidfd_send_signal', side_effect=lambda *args: sent.append(args)), \
                patch.object(support.os, 'close', side_effect=lambda fd: closed.append(fd)):
            result = support.signal_pinned_child(123, lambda: validated.append(True))
        assert result != exited and closed == [55]
        assert validated == ([] if exited else [True])
        assert sent == ([] if exited else [(55, support.signal.SIGKILL)])
    check('pam-child-signaled-through-pidfd', pinned_child)
    check('exited-pam-child-never-signaled', lambda: pinned_child(True))

    def independent_password_restore():
        path = source / 'Scripts/dev/locker-owner-proof.py'
        tree = ast.parse(path.read_text())
        node = next(n for n in ast.walk(tree) if isinstance(n, ast.Try) and n.finalbody
            and isinstance(n.finalbody[0], ast.Assign)
            and any(isinstance(x, ast.Name) and x.id == 'hint' for x in n.finalbody[0].targets))
        credential, shadow = work / 'controlled-credential', work / 'controlled-shadow'
        credential.touch(); shadow.touch()
        restored = []
        def run(command, **kwargs):
            if command[:3] == ['sudo', '-n', 'chpasswd']:
                restored.append(True)
            return SimpleNamespace(stdout='no' if command[0] == 'loginctl' else 'foreign')
        env = dict(owner=None, sentinel_identity='owned', sentinel_unit='controlled.service', run=run,
            sid='fixture', current={'descriptor': {'phase': 'settled'}}, unlocked=True,
            wlroots_desktop=lambda: False, compositor_locked=lambda *args: False,
            original_hash='controlled-not-a-password', credential=credential, original_shadow=shadow, work=work)
        raised = None
        try:
            exec(compile(ast.Module(body=[node], type_ignores=[]), str(path), 'exec'), env)
        except AssertionError as error:
            raised = error
        assert raised is not None and 'sentinel invocation replaced' in str(raised), 'sentinel ownership failure not exercised'
        assert restored == [True] and not credential.exists() and not shadow.exists()
    check('sentinel-failure-still-restores-safe-password', independent_password_restore)

    def option_cleanup(locked=False):
        path = source / 'Scripts/dev/locker-lifecycle-regression.py'
        tree = ast.parse(path.read_text())
        node = next(n for n in ast.walk(tree) if isinstance(n, ast.Try) and len(n.finalbody) == 1
            and isinstance(n.finalbody[0], ast.If)
            and isinstance(n.finalbody[0].test, ast.Compare)
            and isinstance(n.finalbody[0].test.left, ast.Name) and n.finalbody[0].test.left.id == 'name')
        case = work / ('locked-option' if locked else 'safe-option')
        case.mkdir()
        restores = []
        def manage(driver, job):
            return {'session': 'fixture'} if job['operation'] == 'discover' else {
                'descriptor': {'phase': 'settled'}, 'units': {'real': {'gone': True}}}
        env = dict(name='primary', option_during={'primary': True}, driver=source, work=case,
            manage=manage, compositor_locked=lambda *args: locked, original_option={'int': 0, 'set': False},
            restore_hypr_option=lambda original: restores.append(original), json=json)
        exec(compile(ast.Module(body=node.finalbody, type_ignores=[]), str(path), 'exec'), env)
        result = json.loads((case / 'primary-option-cleanup.json').read_text())
        assert result['restored'] != locked and bool(restores) != locked
    check('safe-failure-restores-hyprland-option', option_cleanup)
    check('locked-failure-retains-hyprland-recovery-option', lambda: option_cleanup(True))
    (work / 'result.json').write_text(json.dumps(rows, indent=2))
    return 0 if all(row['passed'] for row in rows) else 1


if __name__ == '__main__':
    raise SystemExit(main())
