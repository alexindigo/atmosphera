#!/usr/bin/env python3
"""Assigned-guest plugin destruction, publication and reload consumers."""
import argparse
from contextlib import closing
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import shutil
import subprocess
import time

from guest_profile import activate_profile
from native_settings_controls import prepare
from probe_files import ProbeFiles
from presentation_harness import run_harness


CASES = ('destruction', 'closed-api', 'panel-slot', 'placement', 'reload-held',
         'placement-held', 'manual-unsaved', 'failed-save', 'editor-discard',
         'editor-unload', 'editor-apply-held', 'editor-instance-discard', 'editor-instance-reset',
           'editor-preview-lifetime', 'popup-apply-held', 'popup-close-held', 'popup-open-refused',
           'placement-retry-scope', 'placement-retry-current', 'placement-retry-superseded', 'placement-retry-external')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('source', 'plugins', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--native-source', type=Path)
    parser.add_argument('--lint', action='store_true')
    parser.add_argument('--case', choices=CASES + ('all',), default='all')
    args = parser.parse_args()
    source, plugins, output = (p.resolve() for p in (args.source, args.plugins, args.output))
    profile = activate_profile(Path('/home/tester/Projects/atcq/tools/ark/guest-profiles/atmosphera-configqml-settings.json'))
    assert profile.uuid == '12f17a02-25e9-474c-9dae-fea092c2d2be' and not profile.console.records
    build, contract = prepare((args.native_source or source).resolve())
    output.mkdir(parents=True, exist_ok=False)
    rows = []
    for case in CASES if args.case == 'all' else (args.case,):
        work = output / case
        config = work / 'c'
        preferences = config / 'settings/plugins'
        preferences.mkdir(parents=True)
        (config / 'settings.json').write_text('{"settingsVersion":62}')
        (config / 'plugins.json').write_text('{"version":5,"states":{},"sources":[]}')
        plugin = config / 'plugins/notes-scratchpad'
        shutil.copytree(plugins / 'notes-scratchpad', plugin)
        if case.startswith('popup-'):
            (plugin / 'Settings.qml').write_text('''import QtQuick
Item {
 property var pluginApi: null
 implicitWidth: 240; implicitHeight: 80
 function saveSettings() {
  pluginApi.pluginSettings.scratchpadContent = "unsaved scratchpad destruction consumer";
  pluginApi.saveSettings();
 }
}
''')
        target = preferences / 'notes-scratchpad.json'
        target.write_text('{"scratchpadContent":"original","opaque":{"keep":true}}')
        runtime = profile.child_environment('ul-')
        env = dict(os.environ, **runtime, QT_QPA_PLATFORM='wayland', QML_DISABLE_DISK_CACHE='1',
                   ATMOSPHERA_CONFIG_DIR=str(config), ATMOSPHERA_SETTINGS_FILE=str(config / 'settings.json'),
                   ATMOSPHERA_CACHE_DIR=str(work / 'cache'), ATMOSPHERA_STATE_DIR=str(work / 'state'),
                   PLUGIN_UNLOAD_MANIFEST=(plugin / 'manifest.json').read_text(), PLUGIN_UNLOAD_CASE=case)
        held = case in ('reload-held', 'placement-held', 'editor-apply-held', 'popup-apply-held', 'popup-close-held')
        marker, gate = work / 'held.json', work / 'release'
        if held or case == 'failed-save' or case.startswith('placement-retry-'):
            if case == 'placement-held' or case.startswith('placement-retry-'):
                target = config / 'settings/bar.json'
            rule = dict(file=str(target), phase='rename', marker=str(marker))
            if case == 'placement-held' or case.startswith('placement-retry-'):
                rule['enabled'] = str(work / 'enabled')
                env['PLUGIN_UNLOAD_ENABLE'] = str(work / 'enabled')
            if held:
                os.mkfifo(gate, 0o600)
                rule['gate'] = str(gate)
            else:
                rule['error'] = 'controlled-native-unload-save'
            schedule = work / 'schedule.json'
            schedule.write_text(json.dumps(dict(rules=[rule])))
            env.update(LD_PRELOAD=str(build / 'libatmosphera_native_io.so'), ATCQ_NATIVE_SCHEDULE=str(schedule))
        execution = None
        runtime_quiet = False
        released = False
        cleanup_errors = []

        def release():
            nonlocal released
            fd = os.open(gate, os.O_WRONLY | os.O_NONBLOCK)
            try:
                os.write(fd, b'0\n')
            finally:
                os.close(fd)
            released = True

        try:
            with closing(ProbeFiles(source, Path(__file__).parent / 'fixtures/settings-plugin-unload-review.qml')) as probes:
                command = ['dbus-run-session', '--']
                if 'LD_PRELOAD' in env:
                    command += ['env', 'LD_PRELOAD=' + env.pop('LD_PRELOAD')]
                command += ['qs', '-p', str(probes.probe), '--no-color']
                live = work/'execution'
                live.mkdir()
                # The existing namespace supervisor owns every descendant,
                # including setsid() pipe holders. The caller retains only the
                # scheduling side channel; it never adopts a desktop process.
                with ThreadPoolExecutor(max_workers=1) as supervisor:
                    future = supervisor.submit(run_harness, command, live, env, 30)
                    try:
                        if held:
                            deadline = time.monotonic() + 20
                            while not marker.exists() or not (live/'shell.log').exists() or 'PLUGIN_UNLOAD: HELD_PASS' not in (live/'shell.log').read_text():
                                assert not future.done() and time.monotonic() < deadline, 'real IO/consumer hold not reached'
                                time.sleep(.02)
                            if case in ('reload-held', 'editor-apply-held', 'popup-apply-held', 'popup-close-held'):
                                assert json.loads(target.read_text())['scratchpadContent'] == 'original'
                            release()
                    finally:
                        execution = future.result(timeout=40)
                        runtime_quiet = bool(execution['cleanup_complete'])
                        shutil.copyfile(live/'shell.log', work/'engine.log')
                assert execution['exit_code'] == 0 and not execution['timed_out'] and execution['cleanup_complete'], execution
                text = (work / 'engine.log').read_text()
                assert 'PLUGIN_UNLOAD: PASS' in text and not any(token in text for token in (
                    'TypeError:', 'ReferenceError:', 'SyntaxError:', '_ASSERT:', 'Failed to load configuration')), text[-6000:]
                if case == 'failed-save' or case.startswith('placement-retry-'):
                    assert marker.exists(), 'native publication failure was exercised'
                if case != 'closed-api':
                    cold_env = dict(env, PLUGIN_UNLOAD_COLD='1')
                    cold_env.pop('LD_PRELOAD', None)
                    cold_env.pop('ATCQ_NATIVE_SCHEDULE', None)
                    cold_root = work/'cold-execution'
                    cold_root.mkdir()
                    cold = run_harness(['dbus-run-session', '--', 'qs', '-p', str(probes.probe), '--no-color'], cold_root, cold_env, 25)
                    runtime_quiet = runtime_quiet and bool(cold['cleanup_complete'])
                    text = (cold_root/'shell.log').read_text()
                    (work / 'cold.log').write_text(text)
                    assert cold['exit_code'] == 0 and cold['cleanup_complete'] and not cold['timed_out'] and 'PLUGIN_UNLOAD: COLD_PASS' in text, text[-6000:]
                    assert not any(token in text for token in ('TypeError:', 'ReferenceError:', 'SyntaxError:', '_ASSERT:'))
                assert json.loads((preferences / 'notes-scratchpad.json').read_text())['opaque']['keep']
                if args.lint and case == (CASES[-1] if args.case == 'all' else args.case):
                    vfs = list((Path(runtime['XDG_RUNTIME_DIR']) / 'quickshell/vfs').iterdir())
                    assert len(vfs) == 1
                    files = ('Services/Plugins/Service.qml', 'Services/Plugins/PluginLoader.qml',
                             'Services/Plugins/PluginInstances.qml', 'Services/Plugins/PluginInstanceApi.qml',
                             'Services/Plugins/PluginPreferenceEditor.qml',
                             'Services/Plugins/PluginSettingsPreview.qml',
                             'Modules/Panels/Plugins/PluginPanelSlot.qml', 'Scripts/dev/fixtures/settings-plugin-unload-review.qml')
                    lint = subprocess.run(['bash', str(source / 'Scripts/dev/qmllint.sh'), *files], cwd=source,
                                          env=dict(env, QS_VFS=str(vfs[0])), capture_output=True, text=True, timeout=60)
                    (work / 'lint.log').write_text(lint.stdout + lint.stderr)
                    assert lint.returncode == 0, lint.stdout + lint.stderr
                rows.append(dict(id=case, status='PASS'))
        except Exception as error:
            rows.append(dict(id=case, status='FAIL', error=repr(error)))
        except (KeyboardInterrupt, SystemExit) as error:
            rows.append(dict(id=case, status='FAIL', error=repr(error)))
            raise
        finally:
            if held and marker.exists() and not released:
                try:
                    release()
                except OSError as error:
                    cleanup_errors.append('release: '+repr(error))
            if runtime_quiet:
                try:
                    shutil.rmtree(Path(runtime['XDG_RUNTIME_DIR']))
                except OSError as error:
                    cleanup_errors.append('runtime: '+repr(error))
            else:
                cleanup_errors.append('namespace not proven quiet; runtime retained')
            if rows:
                rows[-1]['cleanupErrors'] = cleanup_errors
                rows[-1]['execution'] = execution
                if cleanup_errors:
                    rows[-1]['status'] = 'FAIL'
            (output / 'result.json').write_text(json.dumps(dict(cases=rows, nativeControls=contract), indent=2) + '\n')
        print(json.dumps({key: value[:500] if key == 'error' else value for key, value in rows[-1].items()}), flush=True)
    return int(any(row['status'] != 'PASS' for row in rows))


if __name__ == '__main__':
    raise SystemExit(main())
