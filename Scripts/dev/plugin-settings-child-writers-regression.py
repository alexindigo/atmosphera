#!/usr/bin/env python3
"""Shared child field intent and explicit dependent-choice ownership. Guest only."""
from fixture_receipts import receipt_run, stage_receipt
import argparse
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


@receipt_run
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    profile_argument(parser)
    for name in ('source', 'plugins', 'work-root', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--plugin', choices=('mpvpaper', 'video-wallpaper', 'screen-recorder'), required=True)
    parser.add_argument('--scope', choices=('plugin', 'instance'), default='instance')
    args = parser.parse_args()
    profile = activate_profile(args.guest_profile)
    profile.prepare_roots()
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent):
            parser.error('fresh roots must belong to the verified profile')
    with (profile.work_base / '.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        case, out = args.work_root, args.output
        case.mkdir(exist_ok=False)
        out.mkdir(exist_ok=False)
        for name in ('config/settings/plugins', 'config/empty', 'cache', 'state'):
            (case / name).mkdir(parents=True)
        install = case / 'install'
        shutil.copytree(args.source, install, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
        shutil.copytree(args.plugins / args.plugin, case / 'config/plugins' / args.plugin)
        runner.write_json(case / 'config/settings.json', dict(settingsVersion=62))
        runner.write_json(case / 'config/plugins.json', dict(version=6, states={}, sources=[]))
        screen = json.loads(subprocess.run(['niri', 'msg', '-j', 'outputs'],
                           env=dict(os.environ, **profile.session_environment()), capture_output=True, text=True, check=True).stdout)
        screens = sorted(screen)
        screen = screens[0]
        shared = dict(opaque=dict(keep=True))
        row = dict(id='plugin:' + args.plugin)
        if args.plugin == 'screen-recorder':
            shared.update(videoSource='screen' if args.scope == 'plugin' else 'portal', videoCodec='hevc_hdr')
            if args.scope == 'instance':
                row['instanceSettings'] = dict(videoSource='screen')
        elif args.plugin == 'mpvpaper':
            shared.update(active=True, isPlaying=True, isMuted=True)
        else:
            shared.update(enabled=True, monitorSpecific=False, monitors={name: dict(isPlaying=True, isMuted=True, opaque=dict(keep=True)) for name in screens})
        shared_path = case / 'config/settings/plugins' / (args.plugin + '.json')
        runner.write_json(shared_path, shared)
        runner.write_json(case / 'config/settings/bar.json', dict(widgets=dict(left=[row])))
        fixture = args.source / 'Scripts/dev/fixtures/plugin-settings-child-writers.qml'
        env = dict(PHA_CHILD_PLUGIN=args.plugin, PHA_CHILD_SCOPE=args.scope, PHA_CHILD_SCREEN=screen)
        error = None
        try:
            text = runner.run_fixture(profile, install, case, out, fixture, extra_env=env, timeout=150,
                                      extra_lint=list((case / 'config/plugins' / args.plugin).rglob('*.qml')))
            if 'CHILD_WRITERS: PASS' not in text:
                raise RuntimeError('missing warm consumer marker')
            cold = out / 'cold'
            cold.mkdir()
            cold_text = runner.run_fixture(profile, install, case, cold, fixture, extra_env=dict(env, PHA_CHILD_COLD='1'))
            if 'CHILD_WRITERS_COLD: PASS' not in cold_text:
                raise RuntimeError('missing independent cold consumer')
            if any(token in text + cold_text for token in ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Cannot assign to non-existent property')):
                raise RuntimeError('runtime diagnostic')
        except RuntimeError as failure:
            error = str(failure)
        final_shared = json.loads(shared_path.read_text())
        rows = json.loads((case / 'config/settings/bar.json').read_text())['widgets']['left']
        expected_shared = dict(shared)
        expected_rows = [dict(row)]
        if args.plugin == 'screen-recorder':
            if args.scope == 'plugin':
                expected_shared.update(videoSource='portal', videoCodec='h264')
            else:
                expected_rows = [dict(id=row['id'], instanceSettings=dict(videoCodec='h264'))]
        same = final_shared == expected_shared and rows == expected_rows
        result = dict(status='PASS' if not error and same else 'FAIL', plugin=args.plugin, scope=args.scope,
                      error=error, independentFiles=same, shared=final_shared, placements=rows,
                      pluginInputs={str(path.relative_to(args.plugins)): hashlib.sha256(path.read_bytes()).hexdigest()
                                    for path in sorted((args.plugins / args.plugin).rglob('*'))
                                    if path.is_file() and path.suffix in ('.qml', '.js', '.json')},
                      shellInputs={str(path.relative_to(args.source)): hashlib.sha256(path.read_bytes()).hexdigest()
                                   for path in (args.source / 'Scripts/dev/fixtures/plugin-settings-child-writers.qml',
                                                args.source / 'Scripts/dev/plugin-settings-child-writers-regression.py')},
                      witness='actual control signals, native selected field publication, shared children and runtime Panel; no physical media/device claim')
        stage_receipt(out / 'result.json', result)
        print('PLUGIN_SETTINGS_CHILD_WRITERS: ' + result['status'], flush=True)
        if result['status'] == 'PASS':
            runner.remove_completed_installs(case, out)
        else:
            raise SystemExit(1)


if __name__ == '__main__':
    main()
