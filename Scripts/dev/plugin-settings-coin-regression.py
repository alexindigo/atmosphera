#!/usr/bin/env python3
"""Coin Flip direct configuration and actual operational consumers. Guest only."""
import argparse
from copy import deepcopy
import fcntl
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil

from guest_profile import activate_profile, profile_argument

SPEC = importlib.util.spec_from_file_location('host_runner', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)
BAD = ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected', 'is not installed', 'COIN_ASSERT:')


def hashes(case):
    return {str(p.relative_to(case)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted((case / 'config').rglob('*.json'))}


def run(args, profile, scope):
    case, out = args.work_root / scope, args.output / scope
    case.mkdir(); out.mkdir(); (out / 'persisted').mkdir()
    install = case / 'install'
    shutil.copytree(args.source, install, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
    for part in ('config/settings/plugins', 'cache', 'state'):
        (case / part).mkdir(parents=True)
    shutil.copytree(args.plugins / 'coin-flip', case / 'config/plugins/coin-flip')
    shared = dict(delay=21, iconColor='mSecondary', lastResult='seed-shared', opaque=dict(keep='shared'))
    bar = dict(widgets=dict(left=[dict(id='plugin:coin-flip', tag='selected', instanceSettings=dict(lastResult='seed-selected', opaque=dict(keep='selected'))),
                                 dict(id='plugin:coin-flip', tag='sibling', instanceSettings=dict(delay=36, iconColor='mPrimary', lastResult='seed-sibling')),
                                 dict(id='plugin:coin-flip', tag='inherited', instanceSettings=dict(lastResult='seed-inherited'))]))
    initial = dict(shared=shared, bar=bar)
    edited = deepcopy(initial)
    (edited['shared'] if scope == 'shared' else edited['bar']['widgets']['left'][0]['instanceSettings']).update(delay=6)
    reset = deepcopy(edited)
    (reset['shared'] if scope == 'shared' else reset['bar']['widgets']['left'][0]['instanceSettings']).pop('delay')
    following = deepcopy(reset)
    following['shared'].update(delay=31, iconColor='mTertiary')
    expected = dict(initial=initial, discarded=initial, edited=edited, **{'reset-staged': edited}, reset=reset, following=following)
    runner.write_json(case / 'expectations.json', expected)
    runner.write_json(case / 'config/settings.json', dict(settingsVersion=62))
    runner.write_json(case / 'config/plugins.json', dict(version=6, states={}, sources=[]))
    runner.write_json(case / 'config/settings/plugins/coin-flip.json', shared)
    runner.write_json(case / 'config/settings/bar.json', bar)
    wanted = None
    if args.negative_control:
        entry = 'BarWidget.qml' if args.negative_control == 'shared-bar' else 'Panel.qml'
        path = case / 'config/plugins/coin-flip' / entry
        needles = {
            'shared-panel': ('property int delay: pluginApi?.pluginSettings?.delay ?? 20',
                             'property int delay: pluginApi?.base?.pluginSettings?.delay ?? pluginApi?.pluginSettings?.delay ?? 20',
                             'actual animation Timer follows selected delay'),
            'shared-bar': ('pluginApi?.pluginSettings.iconColor ?? defaults.iconColor',
                           'pluginApi?.base?.pluginSettings.iconColor ?? pluginApi?.pluginSettings.iconColor ?? defaults.iconColor',
                           'actual Bar foreground follows selected configuration'),
            'shared-writer': ('pluginApi.pluginSettings.lastResult = coinItem.resultString',
                              '(pluginApi.base || pluginApi).pluginSettings.lastResult = coinItem.resultString',
                              'COIN_DISK operation-1'),
            'rendered-result': ('text: coinItem.showResult ? coinItem.resultString : ""',
                                'text: coinItem.showResult ? "wrong result" : ""',
                                'actual child result Text follows finished animation')}
        needle, replacement, wanted = needles[args.negative_control]
        text = path.read_text()
        if text.count(needle) != 1:
            raise RuntimeError('review Coin rejecting-control anchor')
        path.write_text(text.replace(needle, replacement, 1))
        runner.write_json(out / 'mutation.json', dict(control=args.negative_control, sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
    fixture = args.source / 'Scripts/dev/fixtures/plugin-settings-coin.qml'
    env = dict(PHA_COIN_SCOPE=scope, PHA_COIN_CASE=str(case), PHA_COIN_OUTPUT=str(out),
               PHA_COIN_DISK=str(args.source / 'Scripts/dev/fixtures/plugin-settings-coin-disk.py'))
    for mode, boundary in (('edit', ''), ('cold', 'edited'), ('reset', ''), ('cold', 'reset'), ('follow', ''), ('cold', 'following'), ('operation', ''), ('cold', 'operation-3')):
        output = out / (mode + ('-' + boundary if boundary else '')); output.mkdir()
        before = hashes(case)
        try:
            text = runner.run_fixture(profile, install, case, output, fixture,
                extra_env=dict(env, PHA_COIN_MODE=mode, PHA_COIN_BOUNDARY=boundary), timeout=130,
                extra_lint=tuple(sorted((case / 'config/plugins/coin-flip').glob('*.qml'))))
        except RuntimeError:
            log, code = output / 'runtime.log', output / 'runtime.exit'
            if not wanted or not log.is_file() or not code.is_file() or code.read_text().strip() != '2' or wanted not in log.read_text():
                raise
            result = dict(status='PASS', kind='rejecting-control', control=args.negative_control, rejectedAt=wanted, productionCoverage=False)
            runner.write_json(out / 'result.json', result)
            return result
        if args.negative_control and (mode == 'operation' or args.negative_control in ('shared-panel', 'shared-bar')):
            raise RuntimeError('Coin rejecting control escaped')
        marker = 'COIN: COLD_PASS ' + scope + ' ' + boundary if mode == 'cold' else 'COIN: PASS ' + scope + ' ' + mode
        if marker not in text or any(item in text for item in BAD):
            raise RuntimeError('Coin actual consumer failed: ' + mode + '/' + boundary)
        if mode == 'cold' and hashes(case) != before:
            raise RuntimeError('Coin cold reader published an unrequested flip')
        runner.write_json(output / 'observed.json', dict(status='PASS', mode=mode, boundary=boundary, configurationHashes=hashes(case)))
    observed = {p.stem for p in (out / 'persisted').glob('*.json')}
    if observed != set(expected) | {'operation-' + str(i) for i in range(4)}:
        raise RuntimeError('missing independent Coin document boundaries')
    for name in expected:
        if json.loads((out / 'persisted' / (name + '.json')).read_text()) != dict(status='PASS', values=expected[name]):
            raise RuntimeError('independent Coin configuration readback differs: ' + name)
    result = dict(status='PASS', scope=scope, realPagePanelBar=True, untouchedIconConfiguration=True,
                  independentBoundaries=sorted(observed), unchangedHashColdReaders=['edited', 'reset', 'following', 'operation-3'],
                  fourActualSequentialAnimationsAndLocalWrites=True, completePlanAcceptance=False)
    runner.write_json(out / 'result.json', result); runner.remove_completed_installs(case, out)
    print('COIN ' + scope + ': PASS', flush=True)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    profile_argument(parser)
    for name in ('source', 'plugins', 'work-root', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--scope', choices=('shared', 'instance'))
    parser.add_argument('--negative-control', choices=('shared-panel', 'shared-bar', 'shared-writer', 'rendered-result'))
    args = parser.parse_args()
    profile = activate_profile(args.guest_profile); profile.prepare_roots()
    if Path(__file__).resolve() != args.source.resolve() / 'Scripts/dev/plugin-settings-coin-regression.py':
        parser.error('execute the driver from the supplied source tree')
    if args.negative_control and args.scope != 'instance':
        parser.error('rejecting controls require --scope instance')
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent):
            parser.error('fresh roots must belong to the verified profile')
    with (profile.work_base / '.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        args.work_root.mkdir(); args.output.mkdir()
        args.baseline_source = args.baseline_plugins = None
        runner.write_json(args.output / 'inputs.json', dict(native=runner.input_fingerprints(args), files={str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
            for root, paths in ((args.source, [Path(__file__), *sorted((args.source / 'Scripts/dev/fixtures').glob('plugin-settings-coin*'))]),
                                (args.plugins, sorted((args.plugins / 'coin-flip').rglob('*')))) for p in paths if p.is_file()}))
        results = [run(args, profile, scope) for scope in ((args.scope,) if args.scope else ('instance', 'shared'))]
        runner.write_json(args.output / 'result.json', dict(status='PASS', cases=results, completePlanAcceptance=False))
        print('PLUGIN_SETTINGS_COIN: PASS', flush=True)


if __name__ == '__main__':
    main()
