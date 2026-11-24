#!/usr/bin/env python3
"""Native selected-session conflict, preview and release matrix. Named guest only."""
from fixture_receipts import receipt_run, stage_receipt
import argparse
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
SCENARIOS = ('base-change', 'base-equal', 'base-aba', 'source-replace', 'source-change', 'unload', 'held', 'destroy-delayed', 'destroy-busy', 'release-delayed', 'reorder', 'replace', 'preview-chain')


def seed(case, source):
    for part in ('config/settings/plugins', 'config/plugins/lifetime-fixture', 'cache', 'state'):
        (case / part).mkdir(parents=True)
    manifest = dict(id='lifetime-fixture', name='Lifetime fixture', author='Atmosphera fixture',
                    description='Native selected-session lifetime contract', version='1.0.0',
                    entryPoints=dict(settings='Page.qml'), metadata=dict(defaultSettings=dict(label='default'),
                    settingsSchema=dict(version=1, fields=dict(label=dict(type='String', editorUsage='configuration')))))
    runner.write_json(case / 'config/plugins/lifetime-fixture/manifest.json', manifest)
    runner.write_json(case / 'config/settings.json', dict(settingsVersion=62))
    runner.write_json(case / 'config/plugins.json', dict(version=6, states={}, sources=[]))
    runner.write_json(case / 'config/settings/plugins/lifetime-fixture.json', dict(label='base', opaque=dict(keep=True)))
    rows = [dict(id='plugin:lifetime-fixture', tag='selected'),
            dict(id='plugin:lifetime-fixture', tag='sibling', instanceSettings=dict(label='sibling'))]
    runner.write_json(case / 'config/settings/bar.json', dict(widgets=dict(left=rows), screenOverrides=[dict(name='lifetime-screen', widgets=dict(left=rows, center=[], right=[]))]))
    runner.write_json(case / 'config/settings/controlCenter.json', dict(shortcuts=dict(left=rows)))
    runner.write_json(case / 'config/settings/desktopWidgets.json', dict(monitorWidgets=[dict(name='lifetime-screen', widgets=rows)]))
    shutil.copy2(source / 'Scripts/dev/fixtures/plugin-settings-lifetime-page.qml', case / 'config/plugins/lifetime-fixture/Page.qml')


def disk(case, family):
    shared = json.loads((case / 'config/settings/plugins/lifetime-fixture.json').read_text())
    path = case / ('config/settings/' + ('bar' if family in ('global-bar', 'monitor-bar') else 'controlCenter' if family == 'control-center' else 'desktopWidgets') + '.json')
    document = json.loads(path.read_text())
    rows = (document['widgets']['left'] if family == 'global-bar' else document['screenOverrides'][0]['widgets']['left']
            if family == 'monitor-bar' else document['shortcuts']['left'] if family == 'control-center' else document['monitorWidgets'][0]['widgets'])
    return shared, rows


@receipt_run
def run(args, profile, install, scenario, family):
    name = scenario + '-' + family
    case, out = args.work_root / name, args.output / name
    case.mkdir(); out.mkdir()
    seed(case, args.source)
    before = {str(p.relative_to(case)): p.read_bytes() for p in (case / 'config/settings').rglob('*.json')}
    env = dict(PHA_LIFETIME_SCENARIO=scenario, PHA_LIFETIME_FAMILY=family, PHA_WORK_BASE=str(profile.work_base),
               PHA_LIFETIME_MUTATOR=str(args.source / 'Scripts/dev/fixtures/plugin-settings-lifetime-source.py'))
    fixture = args.source / 'Scripts/dev/fixtures/plugin-settings-lifetime.qml'
    start = time.monotonic()
    text = runner.run_fixture(profile, install, case, out, fixture, extra_env=env, timeout=75,
                              extra_lint=[install / 'Services/Plugins/PluginSettingsSession.qml', case / 'config/plugins/lifetime-fixture/Page.qml'])
    bad = ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected', 'is not installed')
    if 'PLUGIN_SETTINGS_LIFETIME: PASS ' not in text or any(marker in text for marker in bad):
        raise RuntimeError(name + ': missing endpoint or runtime diagnostics')
    shared, rows = disk(case, family)
    applied = scenario in ('held', 'destroy-delayed', 'destroy-busy', 'release-delayed') or (scenario == 'source-replace' and family == 'shared')
    expected_shared = dict(label='foreign' if scenario == 'base-change' else 'foreign-source' if scenario == 'source-change' else 'local' if family == 'shared' and applied else 'base', opaque=dict(keep=True))
    if shared != expected_shared:
        raise RuntimeError(name + ': independent shared-file outcome mismatch: ' + repr(shared))
    expected_rows = [dict(id='plugin:lifetime-fixture', tag='selected'), dict(id='plugin:lifetime-fixture', tag='sibling', instanceSettings=dict(label='sibling'))]
    if scenario == 'reorder': expected_rows.reverse()
    if scenario == 'replace': expected_rows[0] = dict(id='plugin:lifetime-fixture', tag='replacement', instanceSettings=dict(label='replacement'))
    if family != 'shared' and applied: expected_rows[0]['instanceSettings'] = dict(label='local')
    if rows != expected_rows:
        raise RuntimeError(name + ': independent placement-file outcome mismatch: ' + repr(rows))
    selected_shard = 'bar' if family in ('global-bar', 'monitor-bar') else 'controlCenter' if family == 'control-center' else 'desktopWidgets'
    for relative, original in before.items():
        if relative == 'config/settings/plugins/lifetime-fixture.json' or (family != 'shared' and relative == 'config/settings/' + selected_shard + '.json'): continue
        if (case / relative).read_bytes() != original:
            raise RuntimeError(name + ': unrelated source bytes changed: ' + relative)
    expected = 'sibling' if scenario == 'reorder' else 'replacement' if scenario == 'replace' else 'local' if applied else shared['label']
    cold = out / 'cold'; cold.mkdir()
    text = runner.run_fixture(profile, install, case, cold, fixture,
                              extra_env=dict(env, PHA_LIFETIME_COLD='1', PHA_LIFETIME_EXPECTED=expected), timeout=75)
    if 'PLUGIN_SETTINGS_LIFETIME: COLD_PASS ' not in text or any(marker in text for marker in bad):
        raise RuntimeError(name + ': independent cold consumer failed')
    rejected = scenario in ('base-change', 'base-equal', 'base-aba', 'source-replace', 'source-change', 'unload', 'reorder', 'replace') and not applied
    result = dict(id=name, status='PASS', seconds=round(time.monotonic() - start, 3), nativeApplyReceipt=scenario != 'preview-chain',
                  boundRuntimeConsumer=True, readableInputBeforeExplicitDiscard=rejected, newerBufferedInput=scenario == 'held',
                  previewChain=scenario == 'preview-chain', independentFiles=True, separateColdConsumer=True)
    stage_receipt(out / 'result.json', result)
    print('CASE lifetime.' + name + ': PASS', flush=True)
    return result


@receipt_run
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    profile_argument(parser)
    for name in ('source', 'work-root', 'output'): parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--plugins', type=Path, help='wrapper compatibility; no catalog code is used')
    parser.add_argument('--install-source', type=Path, help='optional pinned product tree; current fixtures still come from --source')
    parser.add_argument('--negative-control', choices=('preview-release', 'completion-fence'))
    parser.add_argument('--scenario', choices=SCENARIOS)
    parser.add_argument('--family', choices=FAMILIES)
    args = parser.parse_args()
    if args.negative_control:
        required = 'destroy-delayed' if args.negative_control == 'preview-release' else 'release-delayed'
        if args.scenario != required or not args.family:
            parser.error('negative controls require --scenario ' + required + ' and one --family')
    profile = activate_profile(args.guest_profile); profile.prepare_roots()
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or not path.is_relative_to(parent) or path == parent: parser.error('fresh roots must belong to explicit guest profile')
    with (profile.work_base / '.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        args.work_root.mkdir(exist_ok=False); args.output.mkdir(exist_ok=False)
        install = args.work_root / 'install'
        shutil.copytree(args.install_source or args.source, install, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
        rejected_at = None
        if args.negative_control:
            target = install / 'Services/Plugins/PluginSettingsSession.qml'
            text = target.read_text()
            anchor = ('    if (_preview)\n      _preview.close();\n' if args.negative_control == 'preview-release' else
                      'if (lifetime.alive && selected && root.editor === selected)')
            replacement = '' if args.negative_control == 'preview-release' else 'if (lifetime.alive)'
            if text.count(anchor) != 1:
                raise RuntimeError('negative control anchor changed; review the selected-session contract')
            target.write_text(text.replace(anchor, replacement))
            rejected_at = ('no session preview or admission leaks after release' if args.negative_control == 'preview-release' else
                           'late callback cannot reach released selection')
        cases = [(s, f) for s in ([args.scenario] if args.scenario else SCENARIOS) for f in ([args.family] if args.family else FAMILIES)
                 if f != 'shared' or s not in ('reorder', 'replace', 'preview-chain')]
        if not cases: parser.error('the selected scenario requires a placement family')
        results = []
        inputs = {str(p.relative_to(install)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((install / 'Services/Plugins').glob('*')) if p.is_file()}
        fixture_inputs = {str(p.relative_to(args.source)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((args.source / 'Scripts/dev/fixtures').glob('plugin-settings-lifetime*')) if p.is_file()}
        runner.write_json(args.output / 'inputs.json', dict(product=inputs, fixtures=fixture_inputs,
            driver=hashlib.sha256(Path(__file__).read_bytes()).hexdigest()))
        try:
            for scenario, family in cases:
                runner.write_json(args.output / 'status.json', dict(status='RUNNING', completed=len(results), expected=len(cases), current=scenario + '-' + family))
                try:
                    result = run(args, profile, install, scenario, family)
                except RuntimeError:
                    out = args.output / (scenario + '-' + family)
                    log = out / 'runtime.log'
                    if not rejected_at or not log.is_file() or not any('LIFETIME_ASSERT:' in line and rejected_at in line for line in log.read_text().splitlines()):
                        raise
                    result = dict(id=scenario + '-' + family, status='PASS', negativeControl=args.negative_control,
                                  rejectedAt=rejected_at, nativeRuntimeStatus='FAIL', catalogCoverage=False)
                    stage_receipt(out / 'result.json', result)
                else:
                    if rejected_at: raise RuntimeError('negative control unexpectedly passed its actual consumer gate')
                results.append(result)
            runner.remove_completed_installs(args.work_root, args.output)
            stage_receipt(args.output / 'result.json', dict(status='PASS', cases=results, inputs=inputs, negativeControl=args.negative_control, catalogCoverage=False))
            stage_receipt(args.output / 'status.json', dict(status='PASS', completed=len(results), expected=len(cases)))
            print(('PLUGIN_SETTINGS_LIFETIME_CONTROL: PASS (' + args.negative_control + '; actual native result FAIL as expected)')
                  if args.negative_control else 'PLUGIN_SETTINGS_LIFETIME: PASS', flush=True)
        except Exception as error:
            stage_receipt(args.output / 'status.json', dict(status='FAIL', completed=len(results), expected=len(cases), error=str(error)))
            raise


if __name__ == '__main__':
    main()
