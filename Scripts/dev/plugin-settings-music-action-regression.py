#!/usr/bin/env python3
"""Real Music Main/Settings helper-action result, busy admission and IO Retry. Guest only."""
import argparse
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil

from guest_profile import activate_profile, profile_argument

SPEC = importlib.util.spec_from_file_location('host_runner', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)
BAD = ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected', 'is not installed', 'MUSIC_ACTION_ASSERT:')


def config_hashes(case):
    return {str(path.relative_to(case)): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in [case / 'config' / name for name in ('settings.json', 'plugins.json', 'settings/bar.json', 'settings/plugins/music-search.json')]}


def run(args, profile, scope):
    case, out = args.work_root / scope, args.output / scope
    case.mkdir(); out.mkdir()
    (out / 'persisted').mkdir()
    install = case / 'install'
    shutil.copytree(args.source, install, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
    for part in ('config/settings/plugins', 'cache', 'state', 'helper', 'old music/album'):
        (case / part).mkdir(parents=True)
    shutil.copytree(args.plugins / 'music-search', case / 'config/plugins/music-search', ignore=shutil.ignore_patterns('*.bak'))
    runner.write_json(case / 'config/settings.json', dict(settingsVersion=62))
    runner.write_json(case / 'config/plugins.json', dict(version=6, states={}, sources=[]))
    runner.write_json(case / 'config/settings/bar.json', dict(widgets=dict(left=[dict(id='plugin:music-search', instanceSettings=dict(showHomeTop=False, opaque=dict(keep='placement')))])))
    runner.write_json(case / 'config/settings/plugins/music-search.json', dict(showHomeRecent=False, opaque=dict(keep='shared')))
    helper = dict(activeProvider='youtube', sortBy='date', downloadDirectory=str(case / 'old music'), downloadCacheMaxMb=64)
    runner.write_json(case / 'helper/settings.json', helper)
    for name, payload in (('old music/foreign.mp3', b'foreign audio'), ('old music/user.txt', b'foreign text'), ('old music/album/nested.mp3', b'foreign nested')):
        (case / name).write_bytes(payload)
    media = {str(p.relative_to(case)): hashlib.sha256(p.read_bytes()).hexdigest() for p in (case / 'old music').rglob('*') if p.is_file()}
    before = config_hashes(case)
    env = dict(MUSIC_CACHE_DIR=str(case / 'helper'), PHA_MUSIC_CASE=str(case), PHA_MUSIC_SCOPE=scope,
               PHA_MUSIC_OUTPUT=str(out), PHA_MUSIC_LOCK=str(args.source / 'Scripts/dev/fixtures/plugin-settings-music-action-lock.py'),
               PHA_MUSIC_DISK=str(args.source / 'Scripts/dev/fixtures/plugin-settings-music-action-disk.py'))
    if args.capture:
        shots = out / 'captures'; shots.mkdir()
        env['PHA_MUSIC_SHOTS'] = str(shots)
    fixture = args.source / 'Scripts/dev/fixtures/plugin-settings-music-action.qml'
    try:
        text = runner.run_fixture(profile, install, case, out, fixture, extra_env=env,
            extra_lint=(case / 'config/plugins/music-search/Main.qml', case / 'config/plugins/music-search/Settings.qml'), timeout=75)
    finally:
        (case / 'helper').chmod(0o700)
    if 'MUSIC_ACTION: PASS ' + scope not in text or any(marker in text for marker in BAD):
        raise RuntimeError('actual Music Main/Settings action boundary failed')
    phases = ('pending', 'busy', 'applied', 'folder', 'failed', 'retried')
    if {path.stem for path in (out / 'persisted').glob('*.json')} != set(phases) or any(json.loads((out / 'persisted' / (phase + '.json')).read_text()).get('status') != 'PASS' for phase in phases):
        raise RuntimeError('Music independent intermediate helper-file boundaries missing')
    expected = dict(helper, downloadDirectory=str(case / 'new music'), downloadCacheMaxMb=3)
    if json.loads((case / 'helper/settings.json').read_text()) != expected or config_hashes(case) != before:
        raise RuntimeError('independent helper/preference ownership readback mismatch')
    if media != {str(p.relative_to(case)): hashlib.sha256(p.read_bytes()).hexdigest() for p in (case / 'old music').rglob('*') if p.is_file()}:
        raise RuntimeError('explicit helper action changed foreign media')
    cold = out / 'cold'; cold.mkdir()
    text = runner.run_fixture(profile, install, case, cold, fixture, extra_env=dict(env, PHA_MUSIC_COLD='1'), timeout=75)
    if 'MUSIC_ACTION: COLD_PASS ' + scope not in text or any(marker in text for marker in BAD) or config_hashes(case) != before or json.loads((case / 'helper/settings.json').read_text()) != expected:
        raise RuntimeError('separate nonpublishing Music Main/Settings cold consumer failed')
    result = dict(id=scope, status='PASS', actualMainAndSettings=True, actualUnchangedHelper=True,
                  realSettingsLockBarrier=True, busyRejectionVisible=True, retainedLocalInput=True,
                  appliedValueNotNewerBuffer=True, realIoFailureRetry=True, independentHelperReadback=expected,
                  intermediateIndependentReadbacks=list(phases),
                  preferenceHashesUnchanged=before, foreignMediaUnchanged=media, separateColdConsumer=True,
                  noDeletion=True, visualReview=False, completePlanAcceptance=False)
    runner.write_json(out / 'result.json', result)
    runner.remove_completed_installs(case, out)
    print('MUSIC_ACTION ' + scope + ': PASS', flush=True)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    profile_argument(parser)
    for name in ('source', 'plugins', 'work-root', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--scope', choices=('shared', 'instance'))
    parser.add_argument('--capture', action='store_true', help='capture four full guest-output feedback states for visual review')
    args = parser.parse_args()
    profile = activate_profile(args.guest_profile); profile.prepare_roots()
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent):
            parser.error('fresh roots must belong to the verified profile')
    with (profile.work_base / '.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        args.work_root.mkdir(exist_ok=False); args.output.mkdir(exist_ok=False)
        runner.write_json(args.output / 'inputs.json', {
            'shell': {str(p.relative_to(args.source)): hashlib.sha256(p.read_bytes()).hexdigest() for p in [Path(__file__), *sorted((args.source / 'Scripts/dev/fixtures').glob('plugin-settings-music-action*'))] if p.is_file()},
            'music': {str(p.relative_to(args.plugins)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((args.plugins / 'music-search').rglob('*')) if p.is_file()}})
        results = [run(args, profile, scope) for scope in ((args.scope,) if args.scope else ('shared', 'instance'))]
        runner.write_json(args.output / 'result.json', dict(status='PASS', cases=results, visualReview=False, completePlanAcceptance=False))
        print('PLUGIN_SETTINGS_MUSIC_ACTION: PASS', flush=True)


if __name__ == '__main__':
    main()
