#!/usr/bin/env python3
"""Currency Exchange native both-scope page and actual runtime consumers. Guest only."""
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

from guest_profile import activate_profile, profile_argument

SPEC = importlib.util.spec_from_file_location('host_runner', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)
BAD = ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected', 'is not installed', 'CURRENCY_ASSERT:')


def hashes(case):
    return {str(p.relative_to(case)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted((case / 'config').rglob('*.json'))}


@receipt_run
def run(args, profile, scope):
    case, out = args.work_root / scope, args.output / scope
    case.mkdir(); out.mkdir(); (out / 'persisted').mkdir()
    install = case / 'install'
    shutil.copytree(args.source, install, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
    for part in ('config/settings/plugins', 'cache', 'state', 'bin'):
        (case / part).mkdir(parents=True)
    shutil.copytree(args.plugins / 'currency-exchange', case / 'config/plugins/currency-exchange')
    adapter = case / 'bin/curl'
    shutil.copy2(args.source / 'Scripts/dev/fixtures/plugin-settings-currency-curl.py', adapter)
    adapter.chmod(0o700)
    shared = dict(sourceCurrency='USD', targetCurrency='EUR', widgetDisplayMode='compact', refreshInterval=15, opaque=dict(keep='shared'))
    bar = dict(widgets=dict(left=[dict(id='plugin:currency-exchange', tag='selected', instanceSettings=dict(opaque=dict(keep='selected'))),
                                 dict(id='plugin:currency-exchange', tag='sibling', instanceSettings=dict(sourceCurrency='EUR', targetCurrency='GBP', widgetDisplayMode='icon', refreshInterval=15)),
                                 dict(id='plugin:currency-exchange', tag='inherited')]))
    initial = dict(shared=shared, bar=bar)
    edited = deepcopy(initial)
    (edited['shared'] if scope == 'shared' else edited['bar']['widgets']['left'][0]['instanceSettings']).update(
        sourceCurrency='GBP', targetCurrency='JPY', widgetDisplayMode='full', refreshInterval=30)
    reset = deepcopy(edited)
    target = reset['shared'] if scope == 'shared' else reset['bar']['widgets']['left'][0]['instanceSettings']
    for key in ('sourceCurrency', 'targetCurrency', 'widgetDisplayMode', 'refreshInterval'):
        target.pop(key)
    following = deepcopy(reset)
    following['shared'].update(sourceCurrency='JPY', targetCurrency='GBP', widgetDisplayMode='full', refreshInterval=60)
    expected = dict(initial=initial, discarded=initial, failed=initial, edited=edited,
                    **{'reset-staged': edited}, reset=reset, following=following)
    runner.write_json(case / 'expectations.json', expected)
    runner.write_json(case / 'config/settings.json', dict(settingsVersion=62))
    runner.write_json(case / 'config/plugins.json', dict(version=6, states={}, sources=[]))
    runner.write_json(case / 'config/settings/plugins/currency-exchange.json', shared)
    runner.write_json(case / 'config/settings/bar.json', bar)
    expected_rejection = None
    if args.negative_control:
        entry = {'shared-panel': 'Panel.qml', 'shared-bar': 'BarWidget.qml', 'shared-launcher': 'LauncherProvider.qml', 'rendered-result': 'Panel.qml'}[args.negative_control]
        path = case / 'config/plugins/currency-exchange' / entry
        needle = 'pluginApi.mainInstance.settingsConsumerFor(pluginApi.settingsContext)'
        replacement = 'pluginApi.mainInstance.settingsConsumer'
        if args.negative_control == 'rendered-result':
            needle = 'text: loaded ? toAmount.toFixed(2) : (loading ? "..." : "--")'
            replacement = 'text: loaded ? "wrong conversion" : (loading ? "..." : "--")'
        text = path.read_text()
        if text.count(needle) != 1:
            raise RuntimeError('review Currency rejecting-control anchor')
        path.write_text(text.replace(needle, replacement, 1))
        expected_rejection = ('actual child Panel result Text' if args.negative_control == 'rendered-result' else
                              'selected context owns client' if entry == 'Panel.qml' else 'all views share selected client identity')
        runner.write_json(out / 'mutation.json', dict(control=args.negative_control, sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
    fixture = args.source / 'Scripts/dev/fixtures/plugin-settings-currency.qml'
    env = dict(PHA_CURRENCY_SCOPE=scope, PHA_CURRENCY_CASE=str(case), PHA_CURRENCY_OUTPUT=str(out),
               PHA_CURRENCY_DISK=str(args.source / 'Scripts/dev/fixtures/plugin-settings-currency-disk.py'),
               PATH=str(case / 'bin') + ':' + os.environ['PATH'])
    modes = [('edit', ''), ('cold', 'edited'), ('reset', ''), ('cold', 'reset'), ('follow', ''), ('cold', 'following'), ('policy', ''), ('retire', '')]
    if args.expect_old_timer_red:
        modes = [('edit', '')]
        env['PHA_CURRENCY_OLD_RED'] = '1'
    for mode, boundary in modes:
        output = out / (mode + ('-' + boundary if boundary else '')); output.mkdir()
        before = hashes(case)
        if mode == 'policy':
            (case / 'fail-next').touch(exist_ok=False)
        try:
            text = runner.run_fixture(profile, install, case, output, fixture,
                extra_env=dict(env, PHA_CURRENCY_MODE=mode, PHA_CURRENCY_BOUNDARY=boundary), timeout=130,
                extra_lint=tuple(sorted((case / 'config/plugins/currency-exchange').glob('*.qml'))))
        except RuntimeError:
            log, code = output / 'runtime.log', output / 'runtime.exit'
            wanted = 'actual refresh Timer follows selected interval' if args.expect_old_timer_red else expected_rejection
            if not wanted or not log.is_file() or not code.is_file() or code.read_text().strip() != '2' or wanted not in log.read_text():
                raise
            if args.expect_old_timer_red:
                actual = dict(shared=json.loads((case / 'config/settings/plugins/currency-exchange.json').read_text()),
                              bar=json.loads((case / 'config/settings/bar.json').read_text()))
                if actual != edited or 'CURRENCY_NATIVE_EDITED' not in log.read_text():
                    raise RuntimeError('old Timer red lacks independent successful native publication')
                runner.write_json(out / 'old-timer-native.json', actual)
            result = dict(status='PASS', kind='old-consumer-red' if args.expect_old_timer_red else 'rejecting-control',
                          rejectedAt=wanted, productionCoverage=False)
            stage_receipt(out / 'result.json', result)
            return result
        if args.negative_control or args.expect_old_timer_red:
            raise RuntimeError('Currency rejecting control escaped')
        marker = 'CURRENCY: COLD_PASS ' + scope + ' ' + boundary if mode == 'cold' else 'CURRENCY: PASS ' + scope + ' ' + mode
        if marker not in text or any(item in text for item in BAD):
            raise RuntimeError('Currency actual consumer failed: ' + mode + '/' + boundary)
        if mode in ('cold', 'policy', 'retire') and hashes(case) != before:
            raise RuntimeError('Currency nonpublishing engine changed configuration')
        stage_receipt(output / 'observed.json', dict(status='PASS', mode=mode, boundary=boundary, configurationHashes=hashes(case)))
    observed = {p.stem for p in (out / 'persisted').glob('*.json')}
    if observed != set(expected):
        raise RuntimeError('missing independent Currency document boundaries')
    for name in expected:
        if json.loads((out / 'persisted' / (name + '.json')).read_text()) != dict(status='PASS', values=expected[name]):
            raise RuntimeError('independent Currency readback differs: ' + name)
    events = [json.loads(line) for line in (out / 'curl.jsonl').read_text().splitlines()]
    if not any(row['event'] == 'held' for row in events) or not any(row['event'] == 'cancelled' for row in events):
        raise RuntimeError('missing real held process/retirement cancellation')
    # Seven ordinary four-context engines, plus one held request, plus policy's
    # actual failed request, forced retry and expired-cache request. Extra fetches
    # expose retry/cache bypasses rather than merely checking policy constants.
    if sum(row['event'] == 'requested' for row in events) != 32 or sum(row['event'] == 'failed' for row in events) != 1:
        raise RuntimeError('actual Currency cache/retry request count differs')
    result = dict(status='PASS', scope=scope, realMainPagePanelBarLauncher=True, allFourConfigurationFields=True,
                  independentBoundaries=sorted(observed), unchangedHashColdReaders=['edited', 'reset', 'following'],
                  discardFailureRetryResetInheritanceRetirement=True, completePlanAcceptance=False)
    stage_receipt(out / 'result.json', result); runner.remove_completed_installs(case, out)
    print('CURRENCY ' + scope + ': PASS', flush=True)
    return result


@receipt_run
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    profile_argument(parser)
    for name in ('source', 'plugins', 'work-root', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--scope', choices=('shared', 'instance'))
    parser.add_argument('--negative-control', choices=('shared-panel', 'shared-bar', 'shared-launcher', 'rendered-result'))
    parser.add_argument('--expect-old-timer-red', action='store_true')
    args = parser.parse_args()
    profile = activate_profile(args.guest_profile); profile.prepare_roots()
    if Path(__file__).resolve() != args.source.resolve() / 'Scripts/dev/plugin-settings-currency-regression.py':
        parser.error('execute the driver from the supplied source tree')
    if (args.negative_control or args.expect_old_timer_red) and args.scope != 'instance':
        parser.error('rejecting controls require --scope instance')
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent):
            parser.error('fresh roots must belong to the verified profile')
    with (profile.work_base / '.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        args.work_root.mkdir(); args.output.mkdir()
        args.baseline_source = args.baseline_plugins = None
        inputs = dict(native=runner.input_fingerprints(args), files={str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
                      for root, paths in ((args.source, [Path(__file__), *sorted((args.source / 'Scripts/dev/fixtures').glob('plugin-settings-currency*'))]),
                                          (args.plugins, sorted((args.plugins / 'currency-exchange').rglob('*')))) for p in paths if p.is_file()})
        runner.write_json(args.output / 'inputs.json', inputs)
        results = [run(args, profile, scope) for scope in ((args.scope,) if args.scope else ('instance', 'shared'))]
        stage_receipt(args.output / 'result.json', dict(status='PASS', cases=results, completePlanAcceptance=False))
        print('PLUGIN_SETTINGS_CURRENCY: PASS', flush=True)


if __name__ == '__main__':
    main()
