#!/usr/bin/env python3
"""Actual Bar/monitor/Control Center section-editor routes, native files and cold readers. Guest only."""
from fixture_receipts import receipt_run, stage_receipt
from fixture_cold_observation import read_cold_observation, write_cold_observation
import argparse
from copy import deepcopy
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess

from guest_profile import activate_profile, profile_argument

SPEC = importlib.util.spec_from_file_location('route_runner', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)
ROUTES = ('global-bar', 'monitor-bar', 'monitor-inherited', 'control-left', 'control-right')
COLD_REJECTED = ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected', 'ENTRY_ROUTE_ASSERT:')


def cold_boundary_from_environment(boundary):
    if boundary not in ('edited', 'whole-reset', 'retry'):
        raise RuntimeError('unreviewed route cold boundary')
    profile = activate_profile(Path(os.environ['PHA_ROUTE_PROFILE']))
    case, install = Path(os.environ['PHA_ROUTE_CASE']), Path(os.environ['PHA_ROUTE_INSTALL'])
    output = Path(os.environ['PHA_ROUTE_COLD_OUTPUT']) / boundary
    for path, parent in ((case, profile.work_base), (install, profile.work_base), (output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent):
            raise RuntimeError('route cold reader escaped the verified guest roots')
    output.mkdir(exist_ok=False)
    before = {str(p.relative_to(case / 'config')): hashlib.sha256(p.read_bytes()).hexdigest()
              for p in (case / 'config').rglob('*.json')}
    text = runner.run_fixture(profile, install, case, output, install / 'plugin-settings-entry-routes.qml', installed=True,
                             extra_env=dict(PHA_ROUTE_COLD='1', PHA_ROUTE_BOUNDARY=boundary), timeout=45)
    route = os.environ['PHA_ROUTE']
    if 'PLUGIN_SETTINGS_ENTRY_ROUTES: COLD_PASS ' + route + ' ' + boundary not in text or any(
            marker in text for marker in COLD_REJECTED):
        raise RuntimeError('intermediate cold route consumer failed: ' + route + '/' + boundary)
    after = {str(p.relative_to(case / 'config')): hashlib.sha256(p.read_bytes()).hexdigest()
             for p in (case / 'config').rglob('*.json')}
    if before != after:
        raise RuntimeError('intermediate route cold reader changed configuration')
    write_cold_observation(output, dict(route=route, boundary=boundary), before, after)


def seed(case, source, route, screen):
    for name in ('config/settings/plugins', 'cache', 'state'):
        (case / name).mkdir(parents=True)
    shutil.copytree(source / 'Scripts/dev/fixtures/plugin-settings-values', case / 'config/plugins/values-fixture')
    def rows(label):
        return [dict(id='plugin:values-fixture', tag='selected', instanceSettings=dict(label=label, amount=9,
                    legacy='instance-content', opaque=dict(keep='placement'))),
                dict(id='plugin:values-fixture', tag='sibling', instanceSettings=dict(label='sibling-' + label))]
    documents = {'bar.json': dict(marginHorizontal=4, marginVertical=4, widgets=dict(left=rows('global'), center=[], right=[]),
        screenOverrides=[dict(name=screen, enabled=route != 'monitor-inherited',
                              widgets=dict(left=rows('monitor'), center=[], right=[]))]),
        'controlCenter.json': dict(shortcuts=dict(left=rows('control-left'), right=rows('control-right'))),
        'desktopWidgets.json': dict(monitorWidgets=[])}
    shared = dict(flag=True, amount=7, label='shared', items=['shared'], record=dict(flag=True, count=7, note='shared'),
                  untouched='shared-untouched', legacy='shared-content', opaque=dict(keep='shared'))
    runner.write_json(case / 'config/settings.json', dict(settingsVersion=62))
    runner.write_json(case / 'config/plugins.json', dict(version=6, states={}, sources=[]))
    runner.write_json(case / 'config/settings/plugins/values-fixture.json', shared)
    for name, value in documents.items():
        runner.write_json(case / 'config/settings' / name, value)
    def selected(data):
        if route == 'monitor-bar':
            return data['bar.json']['screenOverrides'][0]['widgets']['left']
        if route in ('global-bar', 'monitor-inherited'):
            return data['bar.json']['widgets']['left']
        return data['controlCenter.json']['shortcuts'][route.removeprefix('control-')]
    stages = dict(initial=deepcopy(documents), discard=deepcopy(documents))
    edited = deepcopy(documents)
    selected(edited)[0]['instanceSettings']['label'] = 'route-edited'
    stages['edited'] = edited
    reset = deepcopy(edited)
    selected(reset)[0]['instanceSettings'].pop('label')
    stages['field-reset'] = reset
    whole = deepcopy(reset)
    selected(whole)[0]['instanceSettings'].pop('amount')
    stages['whole-reset'] = whole
    stages['failed'] = deepcopy(whole)
    retry = deepcopy(whole)
    selected(retry)[0]['instanceSettings']['label'] = 'route-retry'
    stages['retry'] = retry
    replaced = deepcopy(retry)
    selected(replaced)[0] = dict(id='plugin:values-fixture', tag='replacement', instanceSettings=dict(label='replacement'))
    stages['replacement'] = replaced
    runner.write_json(case / 'expectations.json', stages)
    return stages


@receipt_run
def run(args, profile, route):
    case, out = args.work_root / route, args.output / route
    case.mkdir(); out.mkdir()
    install = case / 'install'
    shutil.copytree(args.source, install, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
    if args.negative_control:
        if route.startswith('control-'):
            target = install / 'Modules/Panels/Settings/Tabs/ControlCenter/ControlCenterTab.qml'
            needle = '"kind": "controlCenter",\n      "section": section,'
            replacement = '"kind": "controlCenter",\n      "section": "' + ('left' if route == 'control-right' else 'right') + '",'
        elif route == 'global-bar':
            target = install / 'Modules/Panels/Settings/Tabs/Bar/BarTab.qml'
            needle, replacement = '"list": "global",', '"list": Quickshell.screens[0].name,'
        else:
            target = install / 'Modules/Panels/Settings/Bar/MonitorWidgetsConfig.qml'
            needle = '"list": PluginInstances.barList(screenName),'
            replacement = '"list": ' + ('"global"' if route == 'monitor-bar' else 'screenName') + ','
        original = target.read_text()
        if original.count(needle) != 1:
            raise RuntimeError('review the route-selection mutation anchor')
        target.write_text(original.replace(needle, replacement, 1))
        runner.write_json(out / 'mutation.json', dict(target=str(target.relative_to(install)),
            originalSha256=hashlib.sha256(original.encode()).hexdigest(), sha256=hashlib.sha256(target.read_bytes()).hexdigest()))
    outputs = subprocess.run(['niri', 'msg', '--json', 'outputs'], env=profile.session_environment(),
                             capture_output=True, text=True, check=True, timeout=10)
    # The seeded monitor list and the fixture's screen must be the same output.
    screen = sorted(json.loads(outputs.stdout))[0]
    expected = seed(case, args.source, route, screen)
    shared = case / 'config/settings/plugins/values-fixture.json'
    before = shared.read_bytes()
    observations = out / 'persisted'
    observations.mkdir()
    cold_boundaries = out / 'cold-boundaries'; cold_boundaries.mkdir()
    env = dict(PHA_ROUTE=route, PHA_ROUTE_EXPECTATIONS=str(case / 'expectations.json'), PHA_ROUTE_OUTPUT=str(observations),
               PHA_ROUTE_PROBE=str(args.source / 'Scripts/dev/fixtures/plugin-settings-entry-routes-disk.py'),
               PHA_ROUTE_PROFILE=str(args.guest_profile), PHA_ROUTE_CASE=str(case), PHA_ROUTE_INSTALL=str(install),
               PHA_ROUTE_COLD_OUTPUT=str(cold_boundaries), PHA_ROUTE_SCREEN=screen)
    fixture = args.source / 'Scripts/dev/fixtures/plugin-settings-entry-routes.qml'
    try:
        text = runner.run_fixture(profile, install, case, out, fixture,
            extra_env=env, extra_lint=(case / 'config/plugins/values-fixture/Page.qml',), timeout=100)
    except RuntimeError:
        if not args.negative_control or (out / 'runtime.exit').read_text().strip() != '2' or not any(
                'ENTRY_ROUTE_ASSERT:' in line and 'route captures exact selected instance' in line
                for line in (out / 'runtime.log').read_text().splitlines()):
            raise
        result = dict(id=route, status='PASS', kind='rejecting-control', productionCoverage=False,
                      actualRuntimeExit=2, rejectedAt='route captures exact selected instance')
        stage_receipt(out / 'result.json', result)
        runner.remove_completed_installs(case, out)
        print('CASE entry-route-control.' + route + ': PASS', flush=True)
        return result
    if args.negative_control:
        raise RuntimeError('route-selection mutation unexpectedly passed')
    bad = ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected', 'is not installed', 'ENTRY_ROUTE_ASSERT:')
    if 'PLUGIN_SETTINGS_ENTRY_ROUTES: PASS ' + route not in text or any(marker in text for marker in bad):
        raise RuntimeError('actual entry route failed: ' + route)
    if shared.read_bytes() != before or {p.stem for p in observations.glob('*.json')} != set(expected):
        raise RuntimeError('entry route changed shared settings or omitted a file boundary')
    for phase, value in expected.items():
        actual = json.loads((observations / (phase + '.json')).read_text())
        if actual.get('status') != 'PASS' or actual.get('documents') != value:
            raise RuntimeError('independent route readback failed: ' + route + '/' + phase)
    cold = out / 'cold'; cold.mkdir()
    config_before = {str(p.relative_to(case / 'config')): hashlib.sha256(p.read_bytes()).hexdigest()
                     for p in (case / 'config').rglob('*.json')}
    text = runner.run_fixture(profile, install, case, cold, fixture, extra_env=dict(env, PHA_ROUTE_COLD='1'), timeout=45)
    if 'PLUGIN_SETTINGS_ENTRY_ROUTES: COLD_PASS ' + route not in text or any(marker in text for marker in bad):
        raise RuntimeError('cold actual route consumer failed: ' + route)
    if config_before != {str(p.relative_to(case / 'config')): hashlib.sha256(p.read_bytes()).hexdigest()
                         for p in (case / 'config').rglob('*.json')}:
        raise RuntimeError('cold route consumer changed configuration')
    for phase in ('edited', 'whole-reset', 'retry'):
        output = cold_boundaries / phase
        identity = dict(route=route, boundary=phase)
        hashes = read_cold_observation(output, identity, 'PLUGIN_SETTINGS_ENTRY_ROUTES: COLD_PASS ' + route + ' ' + phase,
                                      COLD_REJECTED)
        stage_receipt(output / 'result.json', dict(status='PASS', **identity,
            independentEngine=True, configurationHashesUnchanged=hashes))
    result = dict(id=route, status='PASS', actualSectionEditor=True, actualTabSignalRoute=True,
        scope='captured placement', controlSignals=True, physicalInput=False, catalogMainProof=False,
        independentPersistedBoundaries=len(expected), realIoFailureAndSameEditorRetry=True,
        sameIdReplacementRefused=True, protectedAndUnselectedPreserved=True, separateColdConsumer=True,
        intermediateColdBoundaries=['edited', 'whole-reset', 'retry'], coldReaders=4)
    stage_receipt(out / 'result.json', result)
    runner.remove_completed_installs(case, out)
    print('CASE entry-route.' + route + ': PASS', flush=True)
    return result


@receipt_run
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    profile_argument(parser)
    for name in ('source', 'work-root', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--plugins', type=Path, help='wrapper compatibility; reviewed synthetic page')
    parser.add_argument('--route', choices=ROUTES)
    parser.add_argument('--negative-control', action='store_true')
    args = parser.parse_args()
    if args.negative_control and not args.route:
        parser.error('selection control requires one explicit route')
    profile = activate_profile(args.guest_profile); profile.prepare_roots()
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent):
            parser.error('fresh roots must belong to the verified guest profile')
    with (profile.work_base / '.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        args.work_root.mkdir(); args.output.mkdir()
        inputs = [Path(__file__), args.source / 'Scripts/dev/fixtures/plugin-settings-entry-routes.qml',
                  args.source / 'Scripts/dev/fixtures/plugin-settings-entry-routes-disk.py',
                  args.source / 'Widgets/NSectionEditor.qml', args.source / 'Modules/Panels/Settings/Tabs/Bar/BarTab.qml',
                  args.source / 'Modules/Panels/Settings/Bar/MonitorWidgetsConfig.qml',
                  args.source / 'Modules/Panels/Settings/Tabs/ControlCenter/ControlCenterTab.qml']
        runner.write_json(args.output / 'inputs.json', {str(p.relative_to(args.source)): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs})
        results = []
        routes = (args.route,) if args.route else ROUTES
        try:
            for route in routes:
                runner.write_json(args.output / 'status.json', dict(status='RUNNING', completed=len(results), expected=len(routes), current=route))
                results.append(run(args, profile, route))
            stage_receipt(args.output / 'result.json', dict(status='PASS', cases=results, completePlanAcceptance=False,
                kind='rejecting-control' if args.negative_control else 'actual-entry-routes'))
            stage_receipt(args.output / 'status.json', dict(status='PASS', completed=len(results), expected=len(routes)))
        except Exception as error:
            stage_receipt(args.output / 'status.json', dict(status='FAIL', completed=len(results), expected=len(routes), error=str(error)))
            raise
        print('PLUGIN_SETTINGS_ENTRY_ROUTES_CONTROL: PASS' if args.negative_control else 'PLUGIN_SETTINGS_ENTRY_ROUTES: PASS', flush=True)


if __name__ == '__main__':
    main()
