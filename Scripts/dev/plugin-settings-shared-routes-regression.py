#!/usr/bin/env python3
"""Actual Installed gear, BarService and external plugin IPC shared Settings routes. Guest only."""
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
ROUTES = ('installed', 'bar-service', 'ipc')
BAD = ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected', 'is not installed', 'SHARED_ROUTE_ASSERT:')


def hashes(config):
    return {str(p.relative_to(config)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(config.rglob('*.json'))}


def seed(case, source):
    for part in ('config/settings/plugins', 'cache', 'state'):
        (case / part).mkdir(parents=True)
    shutil.copytree(source / 'Scripts/dev/fixtures/plugin-settings-values', case / 'config/plugins/values-fixture')
    initial = {'settings.json': dict(settingsVersion=62),
               'plugins.json': dict(version=6, states={'values-fixture': dict(enabled=True, sourceUrl=None)}, sources=[]),
               'settings/plugins/values-fixture.json': dict(label='shared', amount=9, untouched='keep', legacy='shared-content', opaque=dict(keep='shared')),
               'settings/bar.json': dict(widgets=dict(left=[dict(id='plugin:values-fixture', tag='inherited'),
                   dict(id='plugin:values-fixture', tag='overridden', instanceSettings=dict(label='sibling', legacy='placement-content', opaque=dict(keep=True)))], center=[], right=[])),
               'settings/controlCenter.json': dict(shortcuts=dict(left=[], right=[])),
               'settings/desktopWidgets.json': dict(monitorWidgets=[])}
    for name, value in initial.items():
        runner.write_json(case / 'config' / name, value)
    edited = deepcopy(initial); edited['settings/plugins/values-fixture.json']['label'] = 'shared-edited'
    reset = deepcopy(edited); reset['settings/plugins/values-fixture.json'].pop('label')
    retry = deepcopy(reset); retry['settings/plugins/values-fixture.json']['label'] = 'shared-retry'
    expected = dict(initial=initial, discard=deepcopy(initial), edited=edited, reset_staged=deepcopy(edited),
                    reset=reset, failed=deepcopy(reset), failed_discarded=deepcopy(reset), failed_again=deepcopy(reset), retry=retry)
    runner.write_json(case / 'expectations.json', expected)
    return expected


def run(args, profile, route):
    case, out = args.work_root / route, args.output / route
    case.mkdir(); out.mkdir()
    install = case / 'install'
    shutil.copytree(args.source, install, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
    expected = seed(case, args.source)
    if args.negative_control:
        target = install / 'Widgets/NPluginSettingsPopup.qml'
        original = target.read_text()
        needle = 'return settingsSession.openPluginSettings(pluginManifest, settingsEntryPoint);'
        replacement = 'return settingsSession.openInstanceSettings(pluginManifest, PluginInstances.apiFor(pluginManifest.id, {kind: "bar", list: "global", section: "left", index: 0}), settingsEntryPoint);'
        if original.count(needle) != 1:
            raise RuntimeError('review the explicit shared-scope mutation anchor')
        target.write_text(original.replace(needle, replacement, 1))
        runner.write_json(out / 'mutation.json', dict(target='Widgets/NPluginSettingsPopup.qml', sha256=hashlib.sha256(target.read_bytes()).hexdigest()))
    (out / 'persisted').mkdir()
    fixture = args.source / 'Scripts/dev/fixtures/plugin-settings-shared-routes.qml'
    env = dict(PHA_SHARED_ROUTE=route, PHA_SHARED_ROUTE_CASE=str(case), PHA_SHARED_ROUTE_OUTPUT=str(out),
               PHA_SHARED_ROUTE_PROBE=str(args.source / 'Scripts/dev/fixtures/plugin-settings-shared-routes-disk.py'))
    try:
        try:
            text = runner.run_fixture(profile, install, case, out, fixture, extra_env=env,
                extra_lint=(case / 'config/plugins/values-fixture/Page.qml',), timeout=105)
        except RuntimeError:
            marker = 'explicit route must select the shared plugin context'
            log, code = out / 'runtime.log', out / 'runtime.exit'
            if not args.negative_control or not log.is_file() or not code.is_file() or code.read_text().strip() != '2' or not any('SHARED_ROUTE_ASSERT:' in line and marker in line for line in log.read_text().splitlines()):
                raise
            result = dict(id=route, status='PASS', kind='rejecting-control', rejectedAt=marker, actualRuntimeExit=2, productionCoverage=False)
            runner.write_json(out / 'result.json', result)
            runner.remove_completed_installs(case, out)
            return result
    finally:
        (case / 'config/settings/plugins').chmod(0o700)
    if args.negative_control:
        raise RuntimeError('implicit-placement shared-route mutation unexpectedly passed')
    if 'SHARED_ROUTES: PASS ' + route not in text or any(item in text for item in BAD):
        raise RuntimeError('actual explicit shared route failed: ' + route)
    if {p.stem for p in (out / 'persisted').glob('*.json')} != set(expected):
        raise RuntimeError('missing independent shared-route file boundary')
    for phase, documents in expected.items():
        actual = json.loads((out / 'persisted' / (phase + '.json')).read_text())
        if actual.get('status') != 'PASS' or actual.get('documents') != documents:
            raise RuntimeError('independent shared-route readback mismatch: ' + phase)
    cold = out / 'cold'; cold.mkdir()
    before = hashes(case / 'config')
    text = runner.run_fixture(profile, install, case, cold, fixture, extra_env=dict(env, PHA_SHARED_ROUTE_COLD='1'), timeout=45)
    if 'SHARED_ROUTES: COLD_PASS ' + route not in text or any(item in text for item in BAD) or hashes(case / 'config') != before:
        raise RuntimeError('separate nonpublishing shared-route consumer failed')
    result = dict(id=route, status='PASS', actualOpeningRoute=True, externalIpc=route == 'ipc',
        scope='plugin', controlSignals=True, physicalInput=False, independentBoundaries=list(expected),
        realIoFailureAndSameEditorRetry=True, failedApplyDiscardRestoresSaved=True, stagedNativeFieldReset=True,
        inheritedConsumerFollows=True, overriddenSiblingAndContentPreserved=True,
        separateNonpublishingColdConsumer=True, coldConfigurationHashes=before, catalogMainProof=False,
        completePlanAcceptance=False)
    result['failedNativeDesiredState'] = [json.loads(line.split('SHARED_ROUTE_FAILED_STATE ', 1)[1])
        for line in (out / 'runtime.log').read_text().splitlines() if 'SHARED_ROUTE_FAILED_STATE ' in line]
    if [state.get('attempt') for state in result['failedNativeDesiredState']] != [1, 2]:
        raise RuntimeError('failed native desired-state observation missing')
    runner.write_json(out / 'result.json', result)
    runner.remove_completed_installs(case, out)
    print('SHARED_ROUTE ' + route + ': PASS', flush=True)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    profile_argument(parser)
    for name in ('source', 'work-root', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--plugins', type=Path, help='wrapper compatibility; reviewed synthetic page')
    parser.add_argument('--route', choices=ROUTES)
    parser.add_argument('--negative-control', action='store_true')
    args = parser.parse_args()
    profile = activate_profile(args.guest_profile); profile.prepare_roots()
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent):
            parser.error('fresh roots must belong to the verified guest profile')
    with (profile.work_base / '.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        args.work_root.mkdir(exist_ok=False); args.output.mkdir(exist_ok=False)
        inputs = [Path(__file__), *sorted((args.source / 'Scripts/dev/fixtures').glob('plugin-settings-shared-routes*')),
                  args.source / 'Services/UI/BarService.qml', args.source / 'Services/Control/IPCService.qml',
                  args.source / 'Modules/Panels/Settings/Tabs/Plugins/InstalledSubTab.qml',
                  args.source / 'Modules/MainScreen/PopupMenuWindow.qml', args.source / 'Widgets/NPluginSettingsPopup.qml']
        runner.write_json(args.output / 'inputs.json', {str(p.relative_to(args.source)): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs})
        results = []
        routes = (args.route,) if args.route else ROUTES
        try:
            for route in routes:
                runner.write_json(args.output / 'status.json', dict(status='RUNNING', completed=len(results), expected=len(routes), current=route))
                results.append(run(args, profile, route))
            runner.write_json(args.output / 'result.json', dict(status='PASS', cases=results, completePlanAcceptance=False,
                kind='rejecting-control' if args.negative_control else 'explicit-shared-routes'))
            runner.write_json(args.output / 'status.json', dict(status='PASS', completed=len(results), expected=len(routes)))
            print('PLUGIN_SETTINGS_SHARED_ROUTES: PASS', flush=True)
        except Exception as error:
            runner.write_json(args.output / 'status.json', dict(status='FAIL', completed=len(results), expected=len(routes), error=str(error)))
            raise


if __name__ == '__main__':
    main()
