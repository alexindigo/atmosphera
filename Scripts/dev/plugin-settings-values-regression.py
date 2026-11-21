#!/usr/bin/env python3
"""Typed field intents, native Reset/equal omission and cold inheritance. Guest only."""
import argparse
from copy import deepcopy
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import time

from guest_profile import activate_profile, profile_argument

SPEC = importlib.util.spec_from_file_location('host_regression', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)
FAMILIES = ('shared', 'global-bar', 'monitor-bar', 'control-center', 'desktop')
KEYS = ('flag', 'amount', 'label', 'optionalLabel', 'items', 'record')


def cold_boundary_from_environment(boundary):
    """Parent's disk probe waits here; the separate engine cannot advance it."""
    if boundary not in ('edited', 'reset'):
        raise RuntimeError('unreviewed typed cold boundary')
    profile = activate_profile(Path(os.environ['PHA_VALUES_PROFILE']))
    case = Path(os.environ['PHA_VALUES_CASE'])
    install = Path(os.environ['PHA_VALUES_INSTALL'])
    output = Path(os.environ['PHA_VALUES_COLD_OUTPUT']) / boundary
    for path, parent in ((case, profile.work_base), (install, profile.work_base), (output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent):
            raise RuntimeError('typed cold reader escaped the explicit guest roots')
    output.mkdir(exist_ok=False)
    before = {str(p.relative_to(case / 'config')): hashlib.sha256(p.read_bytes()).hexdigest()
              for p in sorted((case / 'config').rglob('*.json'))}
    text = runner.run_fixture(profile, install, case, output, install / 'plugin-settings-values.qml',
        installed=True, extra_env=dict(PHA_VALUES_COLD='1', PHA_VALUES_BOUNDARY=boundary), timeout=45)
    family = os.environ['PHA_VALUES_FAMILY']
    if ('PLUGIN_SETTINGS_VALUES: COLD_PASS ' + family + ' ' + boundary not in text
            or any(marker in text for marker in ('TypeError:', 'ReferenceError:', 'SyntaxError:',
                                                'Binding loop detected', 'is not installed', 'VALUES_ASSERT:'))):
        raise RuntimeError('typed cold boundary consumer failed: ' + family + '/' + boundary)
    after = {str(p.relative_to(case / 'config')): hashlib.sha256(p.read_bytes()).hexdigest()
             for p in sorted((case / 'config').rglob('*.json'))}
    if before != after:
        raise RuntimeError('typed cold reader published or changed configuration')
    runner.write_json(output / 'result.json', dict(status='PASS', family=family, boundary=boundary,
        independentEngine=True, noPageOrReceipt=True, configurationHashesUnchanged=before,
        observed='four bound native runtime Text consumers; absent optional distinct from empty'))


def seed(case, source, family):
    for name in ('config/settings/plugins', 'cache', 'state'):
        (case / name).mkdir(parents=True)
    shutil.copytree(source / 'Scripts/dev/fixtures/plugin-settings-values', case / 'config/plugins/values-fixture')
    shared = dict(flag=True, amount=7, label='shared', items=['shared'],
                  record=dict(flag=True, count=7, note='shared', opaque=dict(keep='record')),
                  untouched='shared-untouched', legacy='shared-content', opaque=dict(keep='shared'))
    content = dict(legacy='instance-content', opaque=dict(keep='placement'))
    other = dict(flag=True, amount=9, label='sibling', optionalLabel='sibling', items=['sibling'],
                 record=dict(flag=True, count=9, note='sibling'), untouched='sibling-untouched')
    rows = [dict(id='plugin:values-fixture', tag='selected', instanceSettings=content),
            dict(id='plugin:values-fixture', tag='inherited'),
            dict(id='plugin:values-fixture', tag='sibling', instanceSettings=other)]
    runner.write_json(case / 'config/settings.json', dict(settingsVersion=62))
    runner.write_json(case / 'config/plugins.json', dict(version=6, states={}, sources=[]))
    runner.write_json(case / 'config/settings/plugins/values-fixture.json', shared)
    runner.write_json(case / 'config/settings/bar.json', dict(widgets=dict(left=rows), screenOverrides=[dict(name='values-screen', widgets=dict(left=rows, center=[], right=[]))]))
    runner.write_json(case / 'config/settings/controlCenter.json', dict(shortcuts=dict(left=rows)))
    runner.write_json(case / 'config/settings/desktopWidgets.json', dict(monitorWidgets=[dict(name='values-screen', widgets=rows)]))
    result = dict(initial=dict(shared=deepcopy(shared), rows=deepcopy(rows)))
    target = dict(flag=False, amount=0, label='', optionalLabel='', items=['', 'item'],
                  record=dict(flag=False, count=0, note='shared', opaque=dict(keep='record')))
    edited = deepcopy(result['initial'])
    (edited['shared'] if family == 'shared' else edited['rows'][0]['instanceSettings']).update(deepcopy(target))
    result['edited'] = edited
    untouched = deepcopy(edited)
    untouched['shared']['untouched'] = 'changed-untouched'
    result['untouched'] = untouched
    result['reset-staged'] = deepcopy(untouched)
    reset = deepcopy(untouched)
    removed = reset['shared'] if family == 'shared' else reset['rows'][0]['instanceSettings']
    for key in KEYS:
        removed.pop(key, None)
    result['reset'] = reset
    if family != 'shared':
        second = deepcopy(reset)
        second['rows'][0]['instanceSettings'].update(deepcopy(target))
        result['second'] = second
        equal = deepcopy(second)
        equal['shared'].update(deepcopy(target))
        result['base-equal'] = equal
        omitted = deepcopy(equal)
        for key in KEYS:
            omitted['rows'][0]['instanceSettings'].pop(key, None)
        result['equal-omitted'] = omitted
        following = deepcopy(omitted)
        following['shared'].update(dict(flag=True, amount=2, label='next', optionalLabel='optional-next', items=['next'],
            record=dict(flag=True, count=2, note='next', opaque=dict(keep='next-record'))))
        result['inherited'] = following
    runner.write_json(case / 'expectations.json', result)
    return result


def run(args, profile, install, family):
    case, out = args.work_root / family, args.output / family
    case.mkdir(); out.mkdir()
    expected = seed(case, args.source, family)
    before = {p.name: p.read_bytes() for p in (case / 'config/settings').glob('*.json')}
    observations = out / 'persisted'
    observations.mkdir()
    cold_boundaries = out / 'cold-boundaries'
    cold_boundaries.mkdir()
    env = dict(PHA_VALUES_FAMILY=family, PHA_VALUES_EXPECTATIONS=str(case / 'expectations.json'),
               PHA_VALUES_DISK=str(args.source / 'Scripts/dev/fixtures/plugin-settings-values-disk.py'),
               PHA_VALUES_OUTPUT=str(observations), PHA_WORK_BASE=str(profile.work_base), PHA_OUTPUT_BASE=str(profile.journal_base),
               PHA_VALUES_PROFILE=str(args.guest_profile), PHA_VALUES_CASE=str(case), PHA_VALUES_INSTALL=str(install),
               PHA_VALUES_COLD_OUTPUT=str(cold_boundaries))
    fixture = args.source / 'Scripts/dev/fixtures/plugin-settings-values.qml'
    bad = ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected', 'is not installed', 'VALUES_ASSERT:')
    started = time.monotonic()
    text = runner.run_fixture(profile, install, case, out, fixture, extra_env=env,
        extra_lint=(case / 'config/plugins/values-fixture/Page.qml',), timeout=135)
    if 'PLUGIN_SETTINGS_VALUES: PASS ' + family not in text or any(marker in text for marker in bad):
        raise RuntimeError('typed field runtime/consumer gate failed: ' + family)
    phases = set(expected)
    actual = {path.stem for path in observations.glob('*.json')}
    if actual != phases:
        raise RuntimeError('missing or unexpected independent persisted boundaries: ' + repr((actual, phases)))
    for phase in phases:
        result = json.loads((observations / (phase + '.json')).read_text())
        if result.get('status') != 'PASS' or json.dumps(result['values'], sort_keys=True) != json.dumps(expected[phase], sort_keys=True):
            raise RuntimeError('typed independent JSON readback failed: ' + phase)
    selected_shard = 'bar.json' if family in ('global-bar', 'monitor-bar') else 'controlCenter.json' if family == 'control-center' else 'desktopWidgets.json'
    for name, original in before.items():
        if (family == 'shared' or name != selected_shard) and (case / 'config/settings' / name).read_bytes() != original:
            raise RuntimeError('typed intent changed an unrelated owning file: ' + name)
    cold = out / 'cold'; cold.mkdir()
    text = runner.run_fixture(profile, install, case, cold, fixture, extra_env=dict(env, PHA_VALUES_COLD='1'), timeout=135)
    if 'PLUGIN_SETTINGS_VALUES: COLD_PASS ' + family not in text or any(marker in text for marker in bad):
        raise RuntimeError('separate cold typed runtime consumer failed: ' + family)
    for boundary in ('edited', 'reset'):
        result = json.loads((cold_boundaries / boundary / 'result.json').read_text())
        if result.get('status') != 'PASS' or result.get('family') != family or result.get('boundary') != boundary:
            raise RuntimeError('missing typed intermediate cold boundary: ' + family + '/' + boundary)
    result = dict(id=family, status='PASS', seconds=round(time.monotonic() - started, 3),
        typedValues=['false', 'integer-zero', 'empty-string', 'absent-optional-vs-empty', 'atomic-list', 'atomic-record'],
        nativeFieldReset=True, nativeEqualOmission=family != 'shared', untouchedInheritance=True,
        protectedAndOpaquePreserved=True, independentPersistedBoundaries=len(phases), separateColdConsumer=True,
        intermediateColdBoundaries=['edited', 'reset'], nonpublishingColdReaders=3,
        input='actual controls own signals; not physical keyboard or device proof')
    runner.write_json(out / 'result.json', result)
    print('CASE values.' + family + ': PASS', flush=True)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    profile_argument(parser)
    for name in ('source', 'work-root', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--plugins', type=Path, help='paired wrapper compatibility; this case uses a reviewed synthetic schema')
    parser.add_argument('--family', choices=FAMILIES)
    parser.add_argument('--negative-control', choices=('truthiness', 'reset-presentation'))
    args = parser.parse_args()
    if args.negative_control and (not args.family or (args.negative_control == 'reset-presentation' and args.family == 'shared')):
        parser.error('negative controls require one explicit family; Reset presentation requires a placement')
    profile = activate_profile(args.guest_profile); profile.prepare_roots()
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or not path.is_relative_to(parent) or path == parent:
            parser.error('fresh roots must belong to the explicit guest profile')
    with (profile.work_base / '.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        args.work_root.mkdir(exist_ok=False); args.output.mkdir(exist_ok=False)
        install = args.work_root / 'install'
        shutil.copytree(args.source, install, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
        expected_rejection = None
        if args.negative_control:
            target = install / 'Services/Plugins/PluginSettingsFields.qml'
            text = target.read_text()
            needle = ('_copy(editor.values[key])' if args.negative_control == 'truthiness' else
                      'return facts && facts.inheritedPresent ? _copy(facts.inheritedValue) : undefined;')
            replacement = ('_copy(editor.values[key] || undefined)' if args.negative_control == 'truthiness' else 'return undefined;')
            if text.count(needle) != 1:
                raise RuntimeError('review the typed field rejecting control anchor')
            target.write_text(text.replace(needle, replacement, 1))
            expected_rejection = ('false zero empty read values preserved' if args.negative_control == 'truthiness' else
                                  'all typed Reset presentations show inherited values')
        inputs = {str(p.relative_to(args.source)): hashlib.sha256(p.read_bytes()).hexdigest()
                  for p in [Path(__file__), args.source / 'Scripts/dev/fixtures/plugin-settings-values.qml',
                            args.source / 'Scripts/dev/fixtures/plugin-settings-values-disk.py',
                            *sorted((args.source / 'Scripts/dev/fixtures/plugin-settings-values').iterdir()),
                            *sorted((args.source / 'Services/Plugins').glob('*'))] if p.is_file()}
        runner.write_json(args.output / 'inputs.json', inputs)
        if args.negative_control:
            runner.write_json(args.output / 'mutation.json', dict(control=args.negative_control,
                target='Services/Plugins/PluginSettingsFields.qml', sha256=hashlib.sha256(target.read_bytes()).hexdigest()))
        families = (args.family,) if args.family else FAMILIES
        results = []
        try:
            for family in families:
                runner.write_json(args.output / 'status.json', dict(status='RUNNING', completed=len(results), expected=len(families), current=family))
                try:
                    result = run(args, profile, install, family)
                except RuntimeError:
                    log = args.output / family / 'runtime.log'
                    code = args.output / family / 'runtime.exit'
                    if not expected_rejection or not log.is_file() or not code.is_file() or code.read_text().strip() != '2' or not any('VALUES_ASSERT:' in line and expected_rejection in line for line in log.read_text().splitlines()):
                        raise
                    result = dict(id=family, status='PASS', kind='rejecting-control', control=args.negative_control,
                                  actualRuntimeExit=2, rejectedAt=expected_rejection, productionCoverage=False)
                    runner.write_json(args.output / family / 'result.json', result)
                else:
                    if expected_rejection:
                        raise RuntimeError('typed rejecting control unexpectedly passed')
                results.append(result)
            runner.remove_completed_installs(args.work_root, args.output)
            runner.write_json(args.output / 'result.json', dict(status='PASS', cases=results,
                kind='rejecting-control' if args.negative_control else 'typed-native-matrix', completePlanAcceptance=False))
            runner.write_json(args.output / 'status.json', dict(status='PASS', completed=len(results), expected=len(families)))
            print('PLUGIN_SETTINGS_VALUES_CONTROL: PASS' if args.negative_control else 'PLUGIN_SETTINGS_VALUES: PASS', flush=True)
        except Exception as error:
            runner.write_json(args.output / 'status.json', dict(status='FAIL', completed=len(results), expected=len(families), error=str(error)))
            raise


if __name__ == '__main__':
    main()
