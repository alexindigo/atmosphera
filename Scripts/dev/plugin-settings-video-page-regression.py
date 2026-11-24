#!/usr/bin/env python3
"""Real Video Wallpaper page and automation consumer. Assigned guest only."""
from fixture_receipts import receipt_run, stage_receipt
import argparse
from copy import deepcopy
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess

from guest_profile import activate_profile, profile_argument

SPEC = importlib.util.spec_from_file_location('host_runner', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)
CASES = ('monitor-intent', 'automation-fallback', 'navigation', 'domains', 'acknowledge', 'refusal',
         'custom-monitor', 'custom-domain', 'custom-space', 'custom-discard')


@receipt_run
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    profile_argument(parser)
    for name in ('source', 'plugins', 'work-root', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--case', choices=('all',) + CASES, default='all')
    args = parser.parse_args()
    profile = activate_profile(args.guest_profile)
    profile.prepare_roots()
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent):
            parser.error('fresh roots must belong to the verified task guest')
    if args.work_root.exists() or args.output.exists():
        parser.error('case roots already exist; refuse duplicate work or overwritten evidence')
    try:
        run(args, profile)
    except Exception as error:
        status = args.output / 'status.json'
        if args.output.is_dir():
            state = json.loads(status.read_text()) if status.is_file() else {}
            runner.write_json(status, dict(state, status='FAIL', error=str(error)))
        raise


@receipt_run
def run(args, profile):
    with (profile.work_base / '.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        args.work_root.mkdir(exist_ok=False)
        args.output.mkdir(exist_ok=False)
        env = dict(os.environ, **profile.child_environment(''))
        sockets = list(Path('/run/user/' + str(os.getuid())).glob('niri.*.sock'))
        if len(sockets) != 1:
            raise RuntimeError('expected the assigned guest compositor socket')
        env['NIRI_SOCKET'] = str(sockets[0])
        names = subprocess.run(['niri', 'msg', '--json', 'outputs'], env=env, capture_output=True, text=True, check=True)
        screens = sorted(json.loads(names.stdout))
        if len(screens) != 2:
            raise RuntimeError('Video monitor/domain matrix requires two actual outputs in this owned guest')
        runner.write_json(args.output / 'outputs.json', json.loads(names.stdout))
        inputs = {str(path.relative_to(args.plugins)): hashlib.sha256(path.read_bytes()).hexdigest()
                  for path in (args.plugins / 'video-wallpaper').rglob('*') if path.is_file()}
        inputs.update({str(Path(__file__).relative_to(args.source)): hashlib.sha256(Path(__file__).read_bytes()).hexdigest()})
        runner.write_json(args.output / 'inputs.json', inputs)
        results = []
        for name in CASES if args.case == 'all' else (args.case,):
            runner.write_json(args.output / 'status.json', dict(status='RUNNING', completed=len(results),
                expected=len(CASES) if args.case == 'all' else 1, current=name))
            case, out = args.work_root / name, args.output / name
            case.mkdir()
            out.mkdir()
            install = case / 'install'
            shutil.copytree(args.source, install, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
            for part in ('config/settings/plugins', 'cache', 'state'):
                (case / part).mkdir(parents=True)
            plugin = case / 'config/plugins/video-wallpaper'
            shutil.copytree(args.plugins / 'video-wallpaper', plugin)
            shutil.copy2(plugin / 'fixtures/SettingsControls.js', install / 'SettingsControls.js')
            manifest = json.loads((plugin / 'manifest.json').read_text())
            runner.write_json(case / 'config/settings.json', dict(settingsVersion=62))
            runner.write_json(case / 'config/plugins.json', dict(version=6, states={}, sources=[]))
            seed = dict(enabled=False, monitorSpecific=True, automation=False, automationMode='alphabetically', automationTime=0.05,
                wallpapersFolder='/synthetic/video', monitors={screen: dict(automation=True, volume=1.75, opaque=dict(keep=True)) for screen in screens}, opaque=dict(keep=True))
            if name not in ('monitor-intent', 'automation-fallback'):
                seed['monitors'] = {screen: dict(volume=1.75, orientation=333, opaque=dict(keep=True)) for screen in screens}
            elif name == 'automation-fallback':
                seed['monitors'][screens[1]].pop('automation')
            shared = case / 'config/settings/plugins/video-wallpaper.json'
            runner.write_json(shared, seed)
            fixture_name = (name if name in ('monitor-intent', 'automation-fallback') else
                            'custom-time-navigation' if name.startswith('custom-') else 'monitor-edits')
            fixture = install / (fixture_name + '.qml')
            fixture_source = (plugin / ('fixtures/' + fixture_name + '.qml')).read_text()
            anchor = 'started = true;'
            if fixture_source.count(anchor) != 1:
                raise RuntimeError('review the fixture screen-order observation anchor')
            fixture.write_text(fixture_source.replace(anchor, anchor + '\nconsole.log("VIDEO_SCREEN_ORDER:" + JSON.stringify(Array.from(Quickshell.screens).map(screen => screen.name)));', 1))
            extra = dict(MINOR_REVIEW_MANIFEST=json.dumps(manifest), MONITOR_INTENT_FILE=str(shared),
                         REVIEW23_CASE=name.removeprefix('custom-'),
                         AUTOMATION_EXPECTED=json.dumps(dict(automation=True, automationMode='alphabetically', automationTime=0.05)))
            bad = ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected', 'is not installed')
            text = runner.run_fixture(profile, install, case, out, fixture, installed=True, extra_env=extra)
            if 'MINOR_REVIEW: SAVED_PASS' not in text or any(marker in text for marker in bad):
                raise RuntimeError(name + ': page/automation consumer failure')
            order = [json.loads(line.split('VIDEO_SCREEN_ORDER:', 1)[1]) for line in text.splitlines() if 'VIDEO_SCREEN_ORDER:' in line]
            if len(order) != 1 or set(order[0]) != set(screens):
                raise RuntimeError(name + ': actual fixture output identity missing')
            first, second = order[0]
            if name == 'automation-fallback' and first != screens[0]:
                raise RuntimeError('fixture first monitor does not match the explicit enabled-domain seed')
            expected = deepcopy(seed)
            if name not in ('acknowledge', 'refusal', 'custom-discard'):
                expected['wallpapersFolder'] += '/unrelated'
            if name == 'monitor-intent':
                expected['automationMode'] = 'random'
            if name in ('acknowledge', 'refusal'):
                defaults = manifest['metadata']['defaultSettings']
                expected['monitors'][first].update(dict(automation=True, automationMode='alphabetically', automationTime=300,
                    volume=1, orientation=270, fillMode=defaults['fillMode'], profile=defaults['profile'], hardwareAcceleration=False))
            elif name.startswith('custom-') and name != 'custom-discard':
                expected['monitors'][first].update(dict(currentWallpaper='first-choice', volume=0.25))
                if name == 'custom-monitor':
                    expected['monitors'][second].update(dict(currentWallpaper='second-choice', volume=0.5))
                expected['automationCustomTime'] = [120]
            if json.loads(shared.read_text()) != expected:
                runner.write_json(out / 'readback-failure.json', dict(expected=expected, actual=json.loads(shared.read_text())))
                raise RuntimeError(name + ': page intent differs from independent monitor/domain readback')
            runner.write_json(out / 'persisted.json', dict(status='PASS', expected=expected, actual=json.loads(shared.read_text())))
            cold = out / 'cold'
            cold.mkdir()
            before_cold = shared.read_bytes()
            text = runner.run_fixture(profile, install, case, cold, fixture, installed=True, extra_env=dict(extra, MINOR_REVIEW_COLD='1'))
            if 'MINOR_REVIEW: COLD_PASS' not in text or any(marker in text for marker in bad):
                raise RuntimeError(name + ': separate cold automation consumer')
            if shared.read_bytes() != before_cold:
                raise RuntimeError(name + ': cold page/consumer published configuration')
            results.append(dict(id=name, status='PASS', independentReadback=True, separateColdConsumer=True,
                                runningAutomation=name in ('monitor-intent', 'automation-fallback'), screens=order[0]))
            stage_receipt(out / 'result.json', results[-1])
            runner.remove_completed_installs(case, out)
        stage_receipt(args.output / 'result.json', dict(status='PASS', cases=results, screenCount=len(screens),
            witness='actual control signals, native Apply, dual-output/domain navigation, invalid input, IO Retry and running automation; not physical input'))
        stage_receipt(args.output / 'status.json', dict(status='PASS', completed=len(results), expected=len(results)))
        print('PLUGIN_SETTINGS_VIDEO_PAGE: PASS')


if __name__ == '__main__':
    main()
