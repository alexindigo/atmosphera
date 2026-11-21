#!/usr/bin/env python3
"""Not Just Text actual selected source and child Text consumers. Guest only."""
import argparse
from copy import deepcopy
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
BAD = ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected', 'is not installed', 'TEXT_ASSERT:')
KEYS = ('text', 'fortuneEnabled', 'fortuneOffensive', 'fortuneEqual', 'fortuneCategory', 'fortuneMaxLength', 'listEnabled', 'textFile', 'refreshOnWallpaper')


def hashes(case):
    return {str(p.relative_to(case)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted((case / 'config').rglob('*.json'))}


def run(args, profile, scope):
    case, out = args.work_root / scope, args.output / scope
    case.mkdir(); out.mkdir(); (out / 'persisted').mkdir()
    install = case / 'install'
    shutil.copytree(args.source, install, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
    for part in ('config/settings/plugins', 'cache', 'state', 'bin'):
        (case / part).mkdir(parents=True)
    shutil.copytree(args.plugins / 'not-just-text', case / 'config/plugins/not-just-text')
    adapter = case / 'bin/fortune'
    shutil.copy2(args.source / 'Scripts/dev/fixtures/plugin-settings-not-just-text-fortune.py', adapter)
    adapter.chmod(0o700)
    (case / 'selected.txt').write_text('# one reviewed selected source\nselected-file\n')
    shared = dict(text='shared-text', fortuneEnabled=False, listEnabled=False, refreshOnWallpaper=True, opaque=dict(keep='shared'))
    bar = dict(widgets=dict(left=[dict(id='plugin:not-just-text', tag='selected', instanceSettings=dict(opaque=dict(keep='selected'))),
                                 dict(id='plugin:not-just-text', tag='sibling', instanceSettings=dict(text='sibling-text', fortuneEnabled=True,
                                      fortuneCategory='sibling', fortuneMaxLength=60, listEnabled=False, refreshOnWallpaper=False)),
                                 dict(id='plugin:not-just-text', tag='inherited')]))
    initial = dict(shared=shared, bar=bar)
    single = deepcopy(initial)
    (single['shared'] if scope == 'shared' else single['bar']['widgets']['left'][0]['instanceSettings']).update(text='')
    edited = deepcopy(initial)
    # fortuneEnabled=false equals its base/default: explicit equal intent must omit it.
    changes = dict(text='', fortuneOffensive=True, fortuneEqual=True, fortuneCategory='following', fortuneMaxLength=30,
                   listEnabled=True, textFile=str(case / 'selected.txt'), refreshOnWallpaper=False)
    (edited['shared'] if scope == 'shared' else edited['bar']['widgets']['left'][0]['instanceSettings']).update(changes)
    reset = deepcopy(edited)
    target = reset['shared'] if scope == 'shared' else reset['bar']['widgets']['left'][0]['instanceSettings']
    for key in KEYS:
        target.pop(key, None)
    following = deepcopy(reset)
    following['shared'].update(text='following-text', fortuneEnabled=True, fortuneOffensive=True, fortuneEqual=True,
                               fortuneCategory='following', fortuneMaxLength=60, listEnabled=False, refreshOnWallpaper=True)
    replaced = deepcopy(following)
    (replaced['shared'] if scope == 'shared' else replaced['bar']['widgets']['left'][0]['instanceSettings']).update(fortuneCategory='replacement')
    policy = deepcopy(replaced)
    (policy['shared'] if scope == 'shared' else policy['bar']['widgets']['left'][0]['instanceSettings']).update(fortuneCategory='oversized', fortuneMaxLength=10)
    expected = dict(initial=initial, single=single, discarded=single, failed=single, edited=edited, **{'reset-staged': edited}, reset=reset, following=following, replaced=replaced, policy=policy)
    runner.write_json(case / 'expectations.json', expected)
    runner.write_json(case / 'config/settings.json', dict(settingsVersion=62))
    runner.write_json(case / 'config/plugins.json', dict(version=6, states={}, sources=[]))
    runner.write_json(case / 'config/settings/plugins/not-just-text.json', shared)
    runner.write_json(case / 'config/settings/bar.json', bar)
    wanted = None
    if args.negative_control:
        path = case / 'config/plugins/not-just-text/BarWidget.qml'
        needle = 'pluginApi.mainInstance.settingsConsumerFor(pluginApi.settingsContext)'
        replacement = 'pluginApi.mainInstance.settingsConsumer'
        wanted = 'selected context owns actual Bar client'
        if args.negative_control == 'rendered-text':
            needle = 'text: root.displayText'
            replacement = 'text: "wrong rendered text"'
            wanted = 'actual child Bar Text follows selected source'
        text = path.read_text()
        if text.count(needle) != 1:
            raise RuntimeError('review Not Just Text control anchor')
        path.write_text(text.replace(needle, replacement, 1))
        runner.write_json(out / 'mutation.json', dict(control=args.negative_control, sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
    fixture = args.source / 'Scripts/dev/fixtures/plugin-settings-not-just-text.qml'
    env = dict(PHA_TEXT_SCOPE=scope, PHA_TEXT_CASE=str(case), PHA_TEXT_OUTPUT=str(out),
               PHA_TEXT_DISK=str(args.source / 'Scripts/dev/fixtures/plugin-settings-not-just-text-disk.py'),
               PATH=str(case / 'bin') + ':' + os.environ['PATH'])
    modes = [('single', ''), ('cold', 'single'), ('edit', ''), ('cold', 'edited'), ('reset', ''), ('cold', 'reset'), ('follow', ''), ('cold', 'following'),
             ('handoff', ''), ('cold', 'replaced'), ('wallpaper', ''), ('policy', ''), ('cold', 'policy'), ('retire', '')]
    if args.expect_old_source_red:
        modes = [('single', ''), ('edit', '')]
        env['PHA_TEXT_OLD_RED'] = '1'
    for mode, boundary in modes:
        output = out / (mode + ('-' + boundary if boundary else '')); output.mkdir()
        before = hashes(case)
        if mode in ('handoff', 'retire'):
            for name in ('held', 'cancelled'):
                (case / name).unlink(missing_ok=True)
        events_before = len((case / 'fortune.jsonl').read_text().splitlines()) if (case / 'fortune.jsonl').exists() else 0
        try:
            text = runner.run_fixture(profile, install, case, output, fixture,
                extra_env=dict(env, PHA_TEXT_MODE=mode, PHA_TEXT_BOUNDARY=boundary), timeout=130,
                extra_lint=tuple(sorted((case / 'config/plugins/not-just-text').glob('*.qml'))))
        except RuntimeError:
            log, code = output / 'runtime.log', output / 'runtime.exit'
            wanted = 'actual child Bar Text follows selected source' if args.expect_old_source_red else wanted
            if not wanted or not log.is_file() or not code.is_file() or code.read_text().strip() != '2' or wanted not in log.read_text():
                raise
            if args.expect_old_source_red:
                actual = dict(shared=json.loads((case / 'config/settings/plugins/not-just-text.json').read_text()),
                              bar=json.loads((case / 'config/settings/bar.json').read_text()))
                if actual != edited or 'TEXT_NATIVE_EDITED' not in log.read_text():
                    raise RuntimeError('old source red lacks independent successful native publication')
                runner.write_json(out / 'old-source-native.json', actual)
            result = dict(status='PASS', kind='old-consumer-red' if args.expect_old_source_red else 'rejecting-control',
                          rejectedAt=wanted, productionCoverage=False)
            runner.write_json(out / 'result.json', result)
            return result
        if args.negative_control or args.expect_old_source_red and mode != 'single':
            raise RuntimeError('Not Just Text rejecting control escaped')
        marker = 'TEXT: COLD_PASS ' + scope + ' ' + boundary if mode == 'cold' else 'TEXT: PASS ' + scope + ' ' + mode
        if marker not in text or any(item in text for item in BAD):
            raise RuntimeError('Not Just Text actual consumer failed: ' + mode + '/' + boundary)
        if mode in ('cold', 'wallpaper', 'retire') and hashes(case) != before:
            raise RuntimeError('Not Just Text cold reader changed configuration')
        if mode == 'wallpaper':
            events_after = [json.loads(line) for line in (case / 'fortune.jsonl').read_text().splitlines()][events_before:]
            # Four clients initially fetch; two screens/events debounce to one
            # further fetch in each of the three enabled contexts, not per view.
            if len(events_after) != 7 or any(row['event'] != 'requested' for row in events_after):
                raise RuntimeError('wallpaper debounce/client request count differs')
        if mode == 'policy':
            events_after = [json.loads(line) for line in (case / 'fortune.jsonl').read_text().splitlines()][events_before:]
            oversized = [row for row in events_after if row['argv'][-1] == 'oversized']
            if len(oversized) != 11 * (3 if scope == 'shared' else 1):
                raise RuntimeError('finite fortune retry policy differs')
        runner.write_json(output / 'observed.json', dict(status='PASS', mode=mode, boundary=boundary, configurationHashes=hashes(case)))
    observed = {p.stem for p in (out / 'persisted').glob('*.json')}
    if observed != set(expected):
        raise RuntimeError('missing independent Not Just Text boundaries')
    for name in expected:
        if json.loads((out / 'persisted' / (name + '.json')).read_text()) != dict(status='PASS', values=expected[name]):
            raise RuntimeError('independent Not Just Text readback differs: ' + name)
    events = [json.loads(line) for line in (case / 'fortune.jsonl').read_text().splitlines()]
    if not all(any(row.get('argv') == argv for row in events) for argv in (['-s', 'sibling'], ['-s', '-o', '-e', 'following'], ['-s', '-o', '-e', 'replacement'])):
        raise RuntimeError('missing actual selected fortune requests')
    quiescence = [json.loads(line) for line in (case / 'quiescence.jsonl').read_text().splitlines()]
    if sum(row['event'] == 'held' for row in events) != 2 or len(quiescence) != 2 or any(row['status'] != 'PASS' for row in quiescence):
        raise RuntimeError('source handoff/retirement lacks independent process quiescence')
    result = dict(status='PASS', scope=scope, realPageMainBar=True, allNineControlIntents=True,
                  independentBoundaries=sorted(observed), unchangedHashColdReaders=['single', 'edited', 'reset', 'following', 'replaced', 'policy'],
                  actualIOFailureRetry=True, sourceHandoffRetirement=True, wallpaperDebounce=True, finiteFortuneRetry=True,
                  completePlanAcceptance=False)
    runner.write_json(out / 'result.json', result); runner.remove_completed_installs(case, out)
    print('TEXT ' + scope + ': PASS', flush=True)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    profile_argument(parser)
    for name in ('source', 'plugins', 'work-root', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--scope', choices=('shared', 'instance'))
    parser.add_argument('--negative-control', choices=('shared-client', 'rendered-text'))
    parser.add_argument('--expect-old-source-red', action='store_true')
    args = parser.parse_args()
    profile = activate_profile(args.guest_profile); profile.prepare_roots()
    if Path(__file__).resolve() != args.source.resolve() / 'Scripts/dev/plugin-settings-not-just-text-regression.py':
        parser.error('execute the driver from the supplied source tree')
    if (args.negative_control or args.expect_old_source_red) and args.scope != 'instance':
        parser.error('rejecting controls require --scope instance')
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent):
            parser.error('fresh roots must belong to the verified profile')
    with (profile.work_base / '.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        args.work_root.mkdir(); args.output.mkdir()
        args.baseline_source = args.baseline_plugins = None
        inputs = dict(native=runner.input_fingerprints(args), files={str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
                      for root, paths in ((args.source, [Path(__file__), *sorted((args.source / 'Scripts/dev/fixtures').glob('plugin-settings-not-just-text*'))]),
                                          (args.plugins, sorted((args.plugins / 'not-just-text').rglob('*')))) for p in paths if p.is_file()})
        runner.write_json(args.output / 'inputs.json', inputs)
        results = [run(args, profile, scope) for scope in ((args.scope,) if args.scope else ('instance', 'shared'))]
        runner.write_json(args.output / 'result.json', dict(status='PASS', cases=results, completePlanAcceptance=False))
        print('PLUGIN_SETTINGS_NOT_JUST_TEXT: PASS', flush=True)


if __name__ == '__main__':
    main()
