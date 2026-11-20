#!/usr/bin/env python3
"""Real Video Wallpaper page and automation consumer. Assigned guest only."""
import argparse
import fcntl
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    profile_argument(parser)
    for name in ('source', 'plugins', 'work-root', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    profile = activate_profile(args.guest_profile)
    profile.prepare_roots()
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent):
            parser.error('fresh roots must belong to the verified task guest')
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
        screens = list(json.loads(names.stdout))
        if not screens:
            raise RuntimeError('verified compositor has no outputs')
        results = []
        for name in ('monitor-intent', 'automation-fallback'):
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
            shared = case / 'config/settings/plugins/video-wallpaper.json'
            runner.write_json(shared, seed)
            fixture = plugin / ('fixtures/' + name + '.qml')
            extra = dict(MINOR_REVIEW_MANIFEST=json.dumps(manifest), AUTOMATION_EXPECTED=json.dumps(dict(automation=True, automationMode='alphabetically', automationTime=0.05)))
            bad = ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected', 'is not installed')
            text = runner.run_fixture(profile, install, case, out, fixture, extra_env=extra)
            if 'MINOR_REVIEW: SAVED_PASS' not in text or any(marker in text for marker in bad):
                raise RuntimeError(name + ': page/automation consumer failure')
            expected = dict(seed, wallpapersFolder=seed['wallpapersFolder'] + '/unrelated')
            if name == 'monitor-intent':
                expected['automationMode'] = 'random'
            if json.loads(shared.read_text()) != expected:
                raise RuntimeError(name + ': unrelated page edit authored another field or monitor member')
            cold = out / 'cold'
            cold.mkdir()
            text = runner.run_fixture(profile, install, case, cold, fixture, extra_env=dict(extra, MINOR_REVIEW_COLD='1'))
            if 'MINOR_REVIEW: COLD_PASS' not in text or any(marker in text for marker in bad):
                raise RuntimeError(name + ': separate cold automation consumer')
            results.append(dict(id=name, status='PASS', independentReadback=True, separateColdConsumer=True))
            runner.remove_completed_installs(case, out)
        runner.write_json(args.output / 'result.json', dict(status='PASS', cases=results, screenCount=len(screens),
            witness='actual control signals, native page Apply and running automation; not physical input; dual-output navigation remains separate'))
        print('PLUGIN_SETTINGS_VIDEO_PAGE: PASS')


if __name__ == '__main__':
    main()
