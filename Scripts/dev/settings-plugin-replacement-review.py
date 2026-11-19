#!/usr/bin/env python3
"""Actual native save/retirement/install/load replacement controls in the assigned VM."""
import argparse
from contextlib import closing
import hashlib
import json
import os
from pathlib import Path
import shutil

from guest_profile import activate_profile
from native_settings_controls import prepare
from presentation_harness import run_harness
from probe_files import ProbeFiles

CASES = ('reload-retry', 'update-retry', 'reload-held-load', 'update-held-load',
         'reload-load-failure', 'update-load-failure', 'uninstall-retry', 'update-disabled')


def main():
    if not __debug__:
        raise RuntimeError('optimized execution cannot run assertion-based controls')
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('source', 'plugins', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--case', choices=CASES + ('all',), default='all')
    args = parser.parse_args()
    source, plugins, output = (path.resolve() for path in (args.source, args.plugins, args.output))
    profile = activate_profile(Path('/home/tester/Projects/atcq/tools/ark/guest-profiles/atmosphera-configqml-settings.json'))
    if profile.uuid != '12f17a02-25e9-474c-9dae-fea092c2d2be' or profile.console.records:
        raise RuntimeError('wrong assigned guest/profile')
    build, contract = prepare(source)
    output.mkdir(parents=True, exist_ok=False)
    rows = []
    for case in CASES if args.case == 'all' else (args.case,):
        work = output / case
        config = work / 'config'
        config.mkdir(parents=True)
        (config / 'settings.json').write_text('{"settingsVersion":62}')
        (config / 'plugins.json').write_text('{"version":5,"states":{},"sources":[]}')
        available = work / 'available'
        shutil.copytree(plugins / 'notes-scratchpad', available / 'notes-scratchpad')
        source_url = available.as_uri()
        key = hashlib.sha256(source_url.encode()).hexdigest()[:6] + ':notes-scratchpad'
        plugin = config / 'plugins' / key
        shutil.copytree(plugins / 'notes-scratchpad', plugin)
        manifest = json.loads((plugin / 'manifest.json').read_text())
        manifest['entryPoints'] = {}
        (plugin / 'manifest.json').write_text(json.dumps(manifest))
        updated = dict(manifest)
        if case == 'update-load-failure':
            updated['entryPoints'] = dict(main='MissingReplacement.qml')
        (available / 'notes-scratchpad/manifest.json').write_text(json.dumps(updated))
        (plugin / 'revision.txt').write_text('old')
        (available / 'notes-scratchpad/revision.txt').write_text('new')
        preferences = config / ('settings/plugins/' + key + '.json')
        preferences.parent.mkdir(parents=True)
        preferences.write_text('{"scratchpadContent":"original","opaque":{"keep":true}}')
        state = work / 'state'
        state_file = state / 'plugins' / key / 'state.json'
        state_file.parent.mkdir(parents=True)
        state_file.write_text('{}')
        wrappers = work / 'bin'
        wrappers.mkdir()
        wrapper = wrappers / 'cat'
        wrapper.write_text('''#!/usr/bin/python3
import os, pathlib, subprocess, sys, time
if os.environ['PLUGIN_REPLACEMENT_CASE'].endswith('-held-load') and sys.argv[1:] == [os.environ['PLUGIN_REPLACEMENT_STATE']]:
    pathlib.Path(os.environ['PLUGIN_REPLACEMENT_MARKER']).write_text('held')
    deadline = time.monotonic() + 15
    while not pathlib.Path(os.environ['PLUGIN_REPLACEMENT_RELEASE']).exists():
        if time.monotonic() >= deadline: sys.exit(9)
        time.sleep(.02)
sys.exit(subprocess.call(['/usr/bin/cat', *sys.argv[1:]]))
''')
        wrapper.chmod(0o700)
        runtime = profile.child_environment('rp-')
        env = dict(os.environ, **runtime, QT_QPA_PLATFORM='wayland', QML_DISABLE_DISK_CACHE='1',
                   ATMOSPHERA_CONFIG_DIR=str(config), ATMOSPHERA_SETTINGS_FILE=str(config / 'settings.json'),
                   ATMOSPHERA_CACHE_DIR=str(work / 'cache'), ATMOSPHERA_STATE_DIR=str(state),
                   PLUGIN_REPLACEMENT_CASE=case, PLUGIN_REPLACEMENT_KEY=key,
                   PLUGIN_REPLACEMENT_MANIFEST=json.dumps(manifest), PLUGIN_REPLACEMENT_SOURCE=source_url,
                   PLUGIN_REPLACEMENT_REVISION=str(plugin / 'revision.txt'),
                   PLUGIN_REPLACEMENT_PREFERENCES=str(preferences), PLUGIN_REPLACEMENT_STATE=str(state_file),
                   PLUGIN_REPLACEMENT_MARKER=str(work / 'held'), PLUGIN_REPLACEMENT_RELEASE=str(work / 'release'),
                   PATH=str(wrappers) + os.pathsep + os.environ['PATH'])
        if case.endswith('-retry'):
            schedule = work / 'schedule.json'
            schedule.write_text(json.dumps(dict(rules=[dict(file=str(preferences), phase='rename',
                marker=str(work / 'failed.json'), error='controlled-native-replacement-save')])))
            env.update(LD_PRELOAD=str(build / 'libatmosphera_native_io.so'), ATCQ_NATIVE_SCHEDULE=str(schedule))
        execution = None
        try:
            with closing(ProbeFiles(source, Path(__file__).parent / 'fixtures/settings-plugin-replacement-review.qml')) as probes:
                live = work / 'execution'
                live.mkdir()
                command = ['dbus-run-session', '--']
                if 'LD_PRELOAD' in env:
                    command += ['env', 'LD_PRELOAD=' + env.pop('LD_PRELOAD')]
                command += ['qs', '-p', str(probes.probe), '--no-color']
                execution = run_harness(command, live, env, 27)
                text = (live / 'shell.log').read_text()
                assert execution['exit_code'] == 0 and execution['cleanup_complete'] and not execution['timed_out'], text[-7000:]
                assert 'PLUGIN_REPLACEMENT: PASS ' + case in text and not any(item in text for item in ('TypeError:', 'ReferenceError:', 'SyntaxError:', '_ASSERT:')), text[-7000:]
                if case.endswith('-retry'):
                    assert (work / 'failed.json').exists()
                    assert json.loads(preferences.read_text())['scratchpadContent'] == 'latest requested-key intent'
                    assert 'fontSize' not in json.loads(preferences.read_text())
                if case == 'uninstall-retry':
                    assert not plugin.exists(), 'retired plugin files were removed'
                rows.append(dict(id=case, status='PASS'))
        except Exception as error:
            rows.append(dict(id=case, status='FAIL', error=repr(error)))
        finally:
            if execution and execution['cleanup_complete']:
                shutil.rmtree(Path(runtime['XDG_RUNTIME_DIR']))
            if rows:
                rows[-1]['execution'] = execution
            (output / 'result.json').write_text(json.dumps(dict(cases=rows, nativeControls=contract), indent=2) + '\n')
        print(json.dumps(rows[-1]), flush=True)
    return int(any(row['status'] != 'PASS' for row in rows))


if __name__ == '__main__':
    raise SystemExit(main())
