#!/usr/bin/env python3
"""Real weekly calendar page/native files and selected projection consumers."""
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

spec = importlib.util.spec_from_file_location('calendar_runner', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(spec); spec.loader.exec_module(runner)


def hashes(case):
    return {str(p.relative_to(case)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((case / 'config').rglob('*.json'))}


@receipt_run
def run(args, profile, scope):
    case, out = args.work_root / scope, args.output / scope
    case.mkdir(); out.mkdir(); (out / 'persisted').mkdir()
    install = case / 'install'
    shutil.copytree(args.source, install, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
    for part in ('config/settings/plugins', 'cache', 'state', 'home'):
        (case / part).mkdir(parents=True)
    dest = case / 'config/plugins/weekly-calendar'; shutil.copytree(args.plugins / 'weekly-calendar', dest)
    shared = dict(weekStart='1', timeFormat='24h', panelMode='attached', lineColorType='mOutline', hourLineOpacity=0.5, dayLineOpacity=0.9, opaque=dict(keep='shared'))
    bar = dict(widgets=dict(left=[dict(id='plugin:weekly-calendar', tag='selected', instanceSettings=dict(opaque=dict(keep='selected'))), dict(id='plugin:weekly-calendar', tag='sibling', instanceSettings=dict(panelMode='centered', weekStart='6', timeFormat='12h', opaque=dict(keep='sibling'))), dict(id='plugin:weekly-calendar', tag='inherited', instanceSettings=dict(opaque=dict(keep='inherited')))]))
    initial = dict(shared=shared, bar=bar)
    edited = deepcopy(initial)
    (edited['shared'] if scope == 'shared' else edited['bar']['widgets']['left'][0]['instanceSettings'])['panelMode'] = 'centered'
    reset = deepcopy(edited)
    (reset['shared'] if scope == 'shared' else reset['bar']['widgets']['left'][0]['instanceSettings']).pop('panelMode')
    following = deepcopy(reset); following['shared']['panelMode'] = 'centered'
    policy = deepcopy(following)
    (policy['shared'] if scope == 'shared' else policy['bar']['widgets']['left'][0]['instanceSettings']).update(weekStart='0', timeFormat='12h', lineColorType='mOnSurfaceVariant', hourLineOpacity=0.2, dayLineOpacity=0.3)
    expected = dict(initial=initial, discarded=initial, edited=edited, **{'reset-staged': edited}, reset=reset, following=following, policy=policy)
    for path, data in [('input.json', dict(plugin='weekly-calendar')), ('expectations.json', expected), ('config/settings.json', dict(settingsVersion=62)), ('config/plugins.json', dict(version=6, states={}, sources=[])), ('config/settings/plugins/weekly-calendar.json', shared), ('config/settings/bar.json', bar)]:
        runner.write_json(case / path, data)
    wanted = 'original Panel consumes saved selected mode' if args.old_red else None
    if args.negative_control:
        controls = {
            'shared-client': ('Panel.qml', 'settingsConsumerFor(pluginApi.settingsContext)', 'settingsConsumerFor(pluginApi.mainInstance.pluginApi.settingsContext)', 'actual views share exact selected calendar client'),
            'retirement': ('Main.qml', 'root._settingsConsumers.delete(context)', 'context', 'retirement releases every calendar projection'),
            'range-union': ('Main.qml', 'if (!start || first < start) start = first;', 'start = first;', 'one provider receives union of active selected ranges'),
            'child': ('Panel.qml', 'return mainInstance.formatTime(d)', 'return "wrong-calendar-hour"', 'actual Panel hour Text uses selected format'),
            'availability': ('Main.qml', 'if (client.current) client.updateEventsFromService();', 'if (false) client.updateEventsFromService();', 'new clients receive events when common service becomes available'),
        }
        filename, old, new, wanted = controls[args.negative_control]; path = dest / filename
        text = path.read_text()
        if text.count(old) != 1: raise RuntimeError('stale calendar control: ' + old)
        path.write_text(text.replace(old, new))
    env = dict(PHA_CALENDAR_SCOPE=scope, PHA_CALENDAR_CASE=str(case), PHA_CALENDAR_OUTPUT=str(out), PHA_CALENDAR_DISK=str(args.source / 'Scripts/dev/fixtures/plugin-settings-query-disk.py'), PHA_CALENDAR_OLD_RED='1' if args.old_red else '0', HOME=str(case / 'home'))
    for mode, boundary in [('edit', ''), ('cold', 'edited'), ('reset', ''), ('cold', 'reset'), ('follow', ''), ('cold', 'following'), ('policy', ''), ('cold', 'policy')]:
        output = out / (mode + ('-' + boundary if boundary else '')); output.mkdir()
        before = hashes(case)
        try:
            text = runner.run_fixture(profile, install, case, output, args.source / 'Scripts/dev/fixtures/plugin-settings-calendar-native.qml', extra_env=dict(env, PHA_CALENDAR_MODE=mode, PHA_CALENDAR_BOUNDARY=boundary), extra_lint=tuple(sorted(dest.rglob('*.qml'))), timeout=110)
        except RuntimeError:
            if not wanted or not (output / 'runtime.log').is_file() or wanted not in (output / 'runtime.log').read_text() or (output / 'runtime.exit').read_text().strip() != '2': raise
            if args.old_red and not (out / 'persisted/edited.json').is_file(): raise RuntimeError('old calendar red precedes independent native publication')
            result = dict(status='PASS', rejectedAt=wanted, originalRed=args.old_red, completePlanAcceptance=False)
            stage_receipt(out / 'result.json', result); runner.remove_completed_installs(case, out); return result
        marker = 'CALENDAR_NATIVE: PASS ' + scope + ' ' + mode
        if marker not in text or any(key in text for key in ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected', 'CALENDAR_ASSERT:')): raise RuntimeError('calendar consumer/diagnostic failure')
        if mode == 'cold' and hashes(case) != before: raise RuntimeError('calendar cold reader published configuration')
        stage_receipt(output / 'observed.json', dict(status='PASS', configurationBefore=before, configurationAfter=hashes(case)))
    if wanted: raise RuntimeError('calendar control escaped')
    for boundary, data in expected.items():
        if json.loads((out / ('persisted/' + boundary + '.json')).read_text()) != dict(status='PASS', values=data): raise RuntimeError('calendar complete documents differ')
    result = dict(status='PASS', scope=scope, independentBoundaries=sorted(expected), unchangedHashColdReaders=['edited', 'reset', 'following', 'policy'], physicalProof=False, completePlanAcceptance=False)
    stage_receipt(out / 'result.json', result); runner.remove_completed_installs(case, out)
    print('CALENDAR_NATIVE ' + scope + ': PASS', flush=True); return result


@receipt_run
def main():
    parser = argparse.ArgumentParser(description=__doc__); profile_argument(parser)
    for key in ('source', 'plugins', 'work-root', 'output'): parser.add_argument('--' + key, type=Path, required=True)
    parser.add_argument('--scope', choices=('shared', 'instance'))
    oracle = parser.add_mutually_exclusive_group()
    oracle.add_argument('--old-red', action='store_true')
    oracle.add_argument('--negative-control', choices=('shared-client', 'retirement', 'range-union', 'child', 'availability'))
    args = parser.parse_args(); profile = activate_profile(args.guest_profile); profile.prepare_roots()
    if Path(__file__).resolve() != args.source.resolve() / 'Scripts/dev/plugin-settings-calendar-regression.py': parser.error('execute supplied source')
    if (args.old_red or args.negative_control) and args.scope != 'instance': parser.error('control requires explicit instance scope')
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent): parser.error('fresh owned profile roots required')
    with (profile.work_base / '.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB); args.work_root.mkdir(); args.output.mkdir()
        paths = [Path(__file__), args.source / 'Scripts/dev/fixtures/plugin-settings-calendar-native.qml', args.source / 'Scripts/dev/fixtures/plugin-settings-query-disk.py']
        runner.write_json(args.output / 'inputs.json', dict(source=str(args.source), plugins=str(args.plugins), files={str(p.relative_to(args.source)): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}, pluginFiles={str(p.relative_to(args.plugins)): hashlib.sha256(p.read_bytes()).hexdigest() for p in (args.plugins / 'weekly-calendar').rglob('*') if p.is_file()}))
        results = [run(args, profile, scope) for scope in ((args.scope,) if args.scope else ('instance', 'shared'))]
        stage_receipt(args.output / 'result.json', dict(status='PASS', cases=results, completePlanAcceptance=False))


if __name__ == '__main__': main()
