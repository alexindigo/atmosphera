#!/usr/bin/env python3
"""Actual native-owner load, cancellation and completion controls in the assigned VM."""
import argparse
from contextlib import closing
import json
import os
from pathlib import Path
import shutil

from guest_profile import activate_profile
from presentation_harness import run_harness
from probe_files import ProbeFiles


CASES = ('opening', 'state', 'state-replace', 'icons', 'icons-failure', 'self-unload', 'success', 'failure', 'missing', 'coalesce')


def main():
    if not __debug__:
        raise RuntimeError('optimized execution cannot run assertion-based controls')
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ('source', 'plugins', 'output'):
        parser.add_argument('--' + key, type=Path, required=True)
    parser.add_argument('--case', choices=CASES + ('all',), default='all')
    args = parser.parse_args()
    source, plugins, output = (path.resolve() for path in (args.source, args.plugins, args.output))
    profile = activate_profile(Path('/home/tester/Projects/atcq/tools/ark/guest-profiles/atmosphera-configqml-settings.json'))
    if profile.uuid != '12f17a02-25e9-474c-9dae-fea092c2d2be' or profile.console.records:
        raise RuntimeError('wrong assigned guest/profile')
    output.mkdir(parents=True, exist_ok=False)
    rows = []
    for case in CASES if args.case == 'all' else (args.case,):
        work = output / case
        config = work / 'config'
        config.mkdir(parents=True)
        (config / 'settings.json').write_text('{"settingsVersion":62}')
        (config / 'plugins.json').write_text('{"version":5,"states":{},"sources":[]}')
        plugin = config / 'plugins/notes-scratchpad'
        shutil.copytree(plugins / 'notes-scratchpad', plugin)
        manifest = json.loads((plugin / 'manifest.json').read_text())
        # No entry objects are needed to prove the pre-registration boundary.
        manifest['entryPoints'] = {}
        if case == 'self-unload':
            manifest['entryPoints'] = {'main': 'LoadReviewMain.qml'}
            (plugin / 'LoadReviewMain.qml').write_text('''import QtQuick
import qs.Services.Plugins
Item {
  property var pluginApi: null
  Component.onCompleted: Service.unloadPlugin(pluginApi.pluginId, true)
}
''')
        if case.startswith('icons'):
            manifest['entryPoints'] = {'icons': 'load-review-icons.json'}
            (plugin / 'load-review-icons.json').write_text('invalid' if case == 'icons-failure' else '{"icons":{}}')
        if case == 'failure':
            (plugin / 'manifest.json').write_text('{}')
        marker, release = work / 'state-held', work / 'state-release'
        state = work / 'state'
        state_file = state / 'plugins/notes-scratchpad/state.json'
        state_file.parent.mkdir(parents=True)
        state_file.write_text('{}')
        wrappers = work / 'bin'
        wrappers.mkdir()
        wrapper = wrappers / 'cat'
        wrapper.write_text('''#!/usr/bin/python3
import os, pathlib, subprocess, sys, time
mode = os.environ['PLUGIN_LOAD_CASE']
target = os.environ['ATMOSPHERA_STATE_DIR'] + '/plugins/notes-scratchpad/state.json'
held = (mode.startswith('state') and sys.argv[1:] == [target]) or (mode == 'icons' and any(arg.endswith('/load-review-icons.json') for arg in sys.argv[1:]))
if held:
    pathlib.Path(os.environ['PLUGIN_LOAD_MARKER']).write_text('held')
    deadline = time.monotonic() + 10
    while not pathlib.Path(os.environ['PLUGIN_LOAD_RELEASE']).exists():
        if time.monotonic() >= deadline: sys.exit(9)
        time.sleep(.02)
sys.exit(subprocess.call(['/usr/bin/cat', *sys.argv[1:]]))
''')
        wrapper.chmod(0o700)
        runtime = profile.child_environment('pl-')
        env = dict(os.environ, **runtime, QT_QPA_PLATFORM='wayland', QML_DISABLE_DISK_CACHE='1',
                   ATMOSPHERA_CONFIG_DIR=str(config), ATMOSPHERA_SETTINGS_FILE=str(config / 'settings.json'),
                   ATMOSPHERA_CACHE_DIR=str(work / 'cache'), ATMOSPHERA_STATE_DIR=str(state),
                   PLUGIN_LOAD_MANIFEST=json.dumps(manifest), PLUGIN_LOAD_CASE=case,
                   PLUGIN_LOAD_MARKER=str(marker), PLUGIN_LOAD_RELEASE=str(release),
                   PATH=str(wrappers) + os.pathsep + os.environ['PATH'])
        execution = None
        try:
            with closing(ProbeFiles(source, Path(__file__).parent / 'fixtures/settings-plugin-load-review.qml')) as probes:
                live = work / 'execution'
                live.mkdir()
                execution = run_harness(['dbus-run-session', '--', 'qs', '-p', str(probes.probe), '--no-color'], live, env, 20)
                text = (live / 'shell.log').read_text()
                assert execution['exit_code'] == 0 and execution['cleanup_complete'] and not execution['timed_out'], text[-6000:]
                diagnostics = text
                if case == 'icons-failure':
                    expected = ('Failed to parse icons.json for plugin: notes-scratchpad SyntaxError: JSON.parse: Parse error',
                                'Plugin load error [notes-scratchpad/icons]: SyntaxError: JSON.parse: Parse error')
                    assert all(text.count(message) == 1 for message in expected), text[-6000:]
                    diagnostics = '\n'.join(line for line in text.splitlines() if not any(message in line for message in expected))
                assert 'PLUGIN_LOAD: PASS ' + case in text and not any(item in diagnostics for item in ('TypeError:', 'ReferenceError:', 'SyntaxError:', '_ASSERT:')), text[-6000:]
                if case.startswith('state') or case == 'icons':
                    assert marker.read_text() == 'held' and release.read_text() == 'release'
                rows.append(dict(id=case, status='PASS'))
        except Exception as error:
            rows.append(dict(id=case, status='FAIL', error=repr(error)))
        finally:
            if execution and execution['cleanup_complete']:
                shutil.rmtree(Path(runtime['XDG_RUNTIME_DIR']))
            if rows:
                rows[-1]['execution'] = execution
            (output / 'result.json').write_text(json.dumps(dict(cases=rows), indent=2) + '\n')
        print(json.dumps(rows[-1]), flush=True)
    return int(any(row['status'] != 'PASS' for row in rows))


if __name__ == '__main__':
    raise SystemExit(main())
