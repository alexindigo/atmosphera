#!/usr/bin/env python3
"""Individual shared history/notification/device/calculation lifetime outcomes."""
import argparse
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil

from guest_profile import activate_profile, profile_argument

spec = importlib.util.spec_from_file_location('projection_lifecycle_runner', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(spec); spec.loader.exec_module(runner)


def run(args, profile, plugin):
    case, out = args.work_root / plugin, args.output / plugin
    case.mkdir(); out.mkdir()
    install = case / 'install'
    shutil.copytree(args.source, install, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
    for part in ('config/plugins', 'cache', 'state', 'bin', 'home'):
        (case / part).mkdir(parents=True)
    dest = case / ('config/plugins/' + plugin)
    shutil.copytree(args.plugins / plugin, dest)
    manifest = json.loads((dest / 'manifest.json').read_text())
    runner.write_json(case / 'input.json', dict(plugin=plugin, directory=str(dest), manifest=manifest))
    runner.write_json(case / 'config/settings.json', dict(settingsVersion=62))
    seed = dict(history=[dict(appName='retained-content', type='Camera', icon='camera', colorKey='secondary', time='retained-time', timestamp=123, action='started')])
    runner.write_json(case / 'cache/privacy-history.json', seed)
    (case / 'requests.jsonl').write_text('')
    endpoint = (args.source / 'Scripts/dev/fixtures/plugin-settings-projection-endpoint.py').read_text()
    for command in ('sh', 'busctl', 'which', 'wl-copy'):
        path = case / 'bin' / command; path.write_text(endpoint); path.chmod(0o755)
    wanted = None
    if args.negative_control:
        if plugin == 'privacy-indicator':
            path = dest / 'Main.qml'; old, new = 'root._toastIssued.has(type)', 'false'
            wanted = 'common notification admitted once across selected contexts'
        elif plugin == 'kde-connect':
            path = dest / 'KdeSettingsClient.qml'; old, new = 'observation.triggerFindMyPhone(mainDevice.id)', 'observation.triggerFindMyPhone(observation.mainDevice.id)'
            wanted = 'selected device action reaches literal endpoint'
        else:
            path = dest / 'CalculatorSettingsClient.qml'; old, new = 'calculation.handleKeyEvent(event, precision)', 'calculation.handleKeyEvent(event)'
            wanted = 'keyboard calculation uses originating precision'
        text = path.read_text()
        if text.count(old) != 1:
            raise RuntimeError('stale projection lifecycle control')
        path.write_text(text.replace(old, new))
    env = dict(PHA_PROJECTION_PLUGIN=plugin, PHA_PROJECTION_CASE=str(case), PHA_PROJECTION_OUTPUT=str(out), PHA_PROJECTION_REQUESTS=str(case / 'requests.jsonl'), HOME=str(case / 'home'), PATH=str(case / 'bin') + ':' + os.environ['PATH'])
    try:
        text = runner.run_fixture(profile, install, case, out, args.source / 'Scripts/dev/fixtures/plugin-settings-projection-lifecycle.qml', extra_env=env, extra_lint=tuple(sorted(dest.rglob('*.qml'))), timeout=100)
    except RuntimeError:
        if not wanted or not (out / 'runtime.log').is_file() or wanted not in (out / 'runtime.log').read_text() or (out / 'runtime.exit').read_text().strip() != '2':
            raise
        result = dict(status='PASS', kind='rejecting-individual-projection-control', rejectedAt=wanted, completePlanAcceptance=False)
    else:
        if wanted or 'PROJECTION_LIFECYCLE: PASS ' + plugin not in text or any(word in text for word in ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected', 'PROJECTION_LIFECYCLE_ASSERT:')):
            raise RuntimeError('individual projection outcome/diagnostic failure')
        if plugin == 'privacy-indicator':
            before = (case / 'history-before.json').read_bytes()
            after = (case / 'history-after.json').read_bytes()
            if before != after or json.loads(before)['history'][-1] != seed['history'][0]:
                raise RuntimeError('instance projection changed shared history bytes/content')
            history = json.loads(before)['history']
            if not any(row['appName'] == 'Controlled Microphone' and row['colorKey'] == 'secondary' for row in history):
                raise RuntimeError('plugin-level captured history color missing')
            shutil.copy2(case / 'history-before.json', out / 'history-before.json')
            shutil.copy2(case / 'history-after.json', out / 'history-after.json')
        result = dict(status='PASS', plugin=plugin, explicitContext=True, nativePlacementProof=False, completePlanAcceptance=False)
    shutil.copy2(case / 'requests.jsonl', out / 'requests.jsonl')
    rows = [json.loads(line) for line in (case / 'requests.jsonl').read_text().splitlines()]
    for row in rows:
        p = Path('/proc') / str(row['pid']) / 'stat'
        if p.exists() and p.read_text().split(') ', 1)[1].split()[19] == row['start']:
            raise RuntimeError('projection endpoint survived engine')
    runner.write_json(out / 'result.json', result); runner.remove_completed_installs(case, out)
    print('PROJECTION_LIFECYCLE ' + plugin + ': PASS', flush=True)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__); profile_argument(parser)
    for key in ('source', 'plugins', 'work-root', 'output'):
        parser.add_argument('--' + key, type=Path, required=True)
    parser.add_argument('--plugin', choices=('privacy-indicator', 'kde-connect', 'noctalia-calculator'))
    parser.add_argument('--negative-control', action='store_true')
    args = parser.parse_args(); profile = activate_profile(args.guest_profile); profile.prepare_roots()
    if Path(__file__).resolve() != args.source.resolve() / 'Scripts/dev/plugin-settings-projection-lifecycle-regression.py':
        parser.error('execute supplied source')
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent):
            parser.error('fresh owned profile roots required')
    if args.negative_control and not args.plugin:
        parser.error('control requires member')
    with (profile.work_base / '.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB); args.work_root.mkdir(); args.output.mkdir()
        paths = [Path(__file__), args.source / 'Scripts/dev/fixtures/plugin-settings-projection-lifecycle.qml', args.source / 'Scripts/dev/fixtures/plugin-settings-projection-endpoint.py']
        runner.write_json(args.output / 'inputs.json', dict(source=str(args.source), plugins=str(args.plugins), files={str(p.relative_to(args.source)): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}, pluginFiles={str(p.relative_to(args.plugins)): hashlib.sha256(p.read_bytes()).hexdigest() for member in ((args.plugin,) if args.plugin else ('privacy-indicator', 'kde-connect', 'noctalia-calculator')) for p in (args.plugins / member).rglob('*') if p.is_file()}))
        results = [run(args, profile, plugin) for plugin in ((args.plugin,) if args.plugin else ('privacy-indicator', 'kde-connect', 'noctalia-calculator'))]
        runner.write_json(args.output / 'result.json', dict(status='PASS', cases=results, completePlanAcceptance=False))


if __name__ == '__main__':
    main()
