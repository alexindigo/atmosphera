#!/usr/bin/env python3
"""Actual G4 pages, independent native documents and cold rendered consumers."""
from fixture_receipts import receipt_run, stage_receipt
from fixtures.json_evidence import require_json_match
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

spec = importlib.util.spec_from_file_location('backend', Path(__file__).with_name('plugin-settings-backend-lifetime-regression.py'))
backend = importlib.util.module_from_spec(spec); spec.loader.exec_module(backend)
runner = backend.runner


@receipt_run
def run(args, profile, scope):
    case, out = args.work_root/scope, args.output/scope
    case.mkdir(); out.mkdir(); (out/'persisted').mkdir()
    install = case/'install'
    shutil.copytree(args.source, install, copy_function=os.link, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
    plugin = args.plugin
    product = backend.seed(case, args.source, args.plugins, plugin)
    if args.shared_popup:
        path = product/('Panel.qml' if plugin == 'auto-cpufreq' else 'BatteryPopup.qml')
        text = path.read_text()
        old = 'settingsConsumerFor(pluginApi.settingsContext)'
        assert text.count(old) == 1
        path.write_text(text.replace(old, 'settingsConsumerFor(pluginApi.mainInstance.pluginApi.settingsContext)'))
    field = 'compactMode' if plugin == 'auto-cpufreq' else 'showProfile'
    base, edit, follow = (False, True, True) if plugin == 'auto-cpufreq' else (True, False, False)
    shared = dict(opaque='shared', **{field: base})
    if plugin == 'auto-cpufreq': shared['refreshInterval'] = 3000
    else: shared['batteryDevice'] = str(case/'hardware/sys/class/power_supply/BAT0')
    initial = dict(shared=shared, bar=dict(widgets=dict(left=[dict(id='plugin:'+plugin, instanceSettings=row) for row in ({'opaque':'selected'}, {field:edit,'opaque':'sibling'}, {'opaque':'inherited'})])))
    edited = deepcopy(initial)
    (edited['shared'] if scope == 'shared' else edited['bar']['widgets']['left'][0]['instanceSettings'])[field] = edit
    reset = deepcopy(edited)
    (reset['shared'] if scope == 'shared' else reset['bar']['widgets']['left'][0]['instanceSettings']).pop(field)
    following = deepcopy(reset); following['shared'][field] = follow
    expected = dict(initial=initial, discarded=initial, edited=edited, **{'reset-staged':edited}, reset=reset, following=following)
    runner.write_json(case/'expectations.json', expected)
    runner.write_json(case/'input.json', dict(plugin=plugin, field=field, editValue=edit, followValue=follow))
    runner.write_json(case/('config/settings/plugins/'+plugin+'.json'), shared)
    runner.write_json(case/'config/settings/bar.json', initial['bar'])
    runner.write_json(out/'sources.json', {str(p.relative_to(args.plugins/plugin)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((args.plugins/plugin).rglob('*')) if p.is_file()})
    env = dict(PHA_BACKEND_CASE=str(case), PHA_BACKEND_PLUGIN=plugin, PHA_BACKEND_SCOPE=scope, PHA_BACKEND_OUTPUT=str(out), PHA_BACKEND_DISK=str(args.source/'Scripts/dev/fixtures/plugin-settings-query-disk.py'), HOME=str(case/'home'), PATH=str(case/'bin')+':'+os.environ['PATH'])
    modes = [('edit','')] if args.shared_popup else [('edit',''),('cold','edited'),('reset',''),('cold','reset'),('follow',''),('cold','following')]
    for mode, boundary in modes:
        part = out/(mode+('-'+boundary if boundary else '')); part.mkdir()
        before = backend.hashes(case)
        text = runner.run_fixture(profile, install, case, part, args.source/'Scripts/dev/fixtures/plugin-settings-backend-native.qml', extra_env=dict(env, PHA_BACKEND_MODE=mode, PHA_BACKEND_BOUNDARY=boundary), extra_lint=tuple(sorted(product.glob('*.qml'))), timeout=90)
        assert 'BACKEND_NATIVE: PASS '+scope+' '+mode+' '+boundary in text
        assert not any(word in text for word in ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected'))
        after = backend.hashes(case)
        runner.write_json(part/'configuration-hashes.json', dict(before=before, after=after))
        if mode == 'cold': assert before == after, 'cold reader published'
        observed = json.loads(text.split('BACKEND_NATIVE_CONSUMER ')[1].splitlines()[0])
        assert observed['barSelected'] and observed['rendered'], observed
        if args.shared_popup:
            assert not observed['popupSelected'], 'shared popup control escaped'
        else: assert observed['popupSelected'], observed
        runner.write_json(part/'consumer.json', dict(status='REJECTED' if args.shared_popup else 'PASS', observed=observed))
    boundaries = ['initial','discarded','edited'] if args.shared_popup else list(expected)
    for boundary in boundaries:
        require_json_match(json.loads((out/'persisted'/(boundary+'.json')).read_text()),
                           dict(status='PASS', values=expected[boundary]), 'independent boundary: '+boundary)
    shutil.copy2(case/'requests.jsonl', out/'requests.jsonl')
    rows = [json.loads(line) for line in (out/'requests.jsonl').read_text().splitlines()]
    for row in rows:
        stat = Path('/proc')/str(row['pid'])/'stat'
        assert not stat.exists() or stat.read_text().split(') ',1)[1].split()[19] != row['start'], row
    stage_receipt(out/'result.json', dict(status='PASS', plugin=plugin, scope=scope, kind='shared-popup-control' if args.shared_popup else 'native', completeNativeBoundaries=boundaries, nonpublishingColdReaders=[] if args.shared_popup else ['edited','reset','following'], endpointRows=len(rows), allEndpointIdentitiesAbsent=True, physicalProof=False))
    runner.remove_completed_installs(case, out)


@receipt_run
def main():
    parser = argparse.ArgumentParser(description=__doc__); profile_argument(parser)
    for name in ('source','plugins','work-root','output'): parser.add_argument('--'+name, type=Path, required=True)
    parser.add_argument('--plugin', choices=('auto-cpufreq','battery-and-power-management'), required=True)
    parser.add_argument('--scope', choices=('instance','shared'))
    parser.add_argument('--shared-popup', action='store_true')
    args = parser.parse_args(); profile = activate_profile(args.guest_profile); profile.prepare_roots()
    if Path(__file__).resolve() != args.source.resolve()/'Scripts/dev/plugin-settings-backend-native-regression.py': parser.error('execute supplied source')
    for path,parent in ((args.work_root,profile.work_base),(args.output,profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent): parser.error('fresh owned guest roots required')
    with (profile.work_base/'.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX|fcntl.LOCK_NB); args.work_root.mkdir(); args.output.mkdir()
        inputs = [Path(__file__), Path(backend.__file__), args.source/'Scripts/dev/fixtures/plugin-settings-backend-native.qml', args.source/'Scripts/dev/fixtures/plugin-settings-query-disk.py']
        runner.write_json(args.output/'inputs.json', {str(p.relative_to(args.source)):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs})
        for scope in ((args.scope,) if args.scope else ('instance','shared')): run(args,profile,scope)
        stage_receipt(args.output/'result.json', dict(status='PASS', completeGroupAcceptance=False))


if __name__ == '__main__': main()
