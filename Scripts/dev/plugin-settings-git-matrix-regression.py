#!/usr/bin/env python3
"""Git selected-client failure/source/inheritance/query matrix. Named guest only."""
import argparse
from copy import deepcopy
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import time

from guest_profile import activate_profile, profile_argument

SPEC = importlib.util.spec_from_file_location('host_runner', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)
SCENARIOS = ('io-retry', 'stale-base', 'source-replacement', 'inheritance', 'held-response', 'platform-group', 'unconfigured')
BAD = ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected', 'is not installed', 'GIT_MATRIX_ASSERT:')


def runtime_errors(text):
    """Keep source + exact error, but remove per-run URL and line-number noise."""
    errors = []
    for line in text.splitlines():
        if not any(marker in line for marker in BAD):
            continue
        match = re.search(r'(BarWidget\.qml|DraggableDesktopWidget\.qml)\[\d+:-?\d+\]: (.*)', line)
        errors.append('/'.join(match.groups()) if match else line.strip())
    return sorted(set(errors))


def observe_runtime(text, inherited):
    errors = runtime_errors(text)
    new = sorted(set(errors) - set(inherited))
    if new:
        raise RuntimeError('new Git presentation/page runtime diagnostics: ' + repr(new))
    return dict(clean=not errors, inheritedDiagnostics=errors, newDiagnostics=new)


def presentation_observations(text):
    observations = [json.loads(line.split('GIT_PRESENTATIONS ', 1)[1])
                    for line in text.splitlines() if 'GIT_PRESENTATIONS ' in line]
    if not observations or any([item['scope'] for item in row['consumers']] != ['shared', 'selected', 'sibling', 'inherited'] for row in observations):
        raise RuntimeError('missing actual presentation endpoint observations')
    return observations


def diagnostic_canaries():
    original = 'WARN scene: file:///original/BarWidget.qml[59:-1]: ReferenceError: isBarVertical is not defined'
    candidate = 'WARN scene: file:///candidate/BarWidget.qml[59:-1]: ReferenceError: isBarVertical is not defined'
    inherited = runtime_errors(original)
    qualified = observe_runtime(candidate, inherited)
    if qualified['clean'] or qualified['newDiagnostics'] or qualified['inheritedDiagnostics'] != inherited:
        raise RuntimeError('inherited diagnostic must be reported, never relabeled clean')
    controls = dict(unqualified=candidate,
                    new_bar='WARN scene: file:///candidate/BarWidget.qml[65:-1]: ReferenceError: newMissingName is not defined',
                    settings='WARN scene: file:///candidate/Settings.qml[10:-1]: TypeError: wrong page contract',
                    main='WARN scene: file:///candidate/Main.qml[10:-1]: TypeError: wrong selected client',
                    syntax='WARN scene: file:///candidate/BarWidget.qml[10:-1]: SyntaxError: invalid source')
    for name, text in controls.items():
        try:
            observe_runtime(text, [] if name == 'unqualified' else inherited)
        except RuntimeError:
            continue
        raise RuntimeError('diagnostic negative canary escaped: ' + name)
    return dict(status='PASS', inheritedRemainsUnclean=True, rejectingControls=list(controls))


def seed(case, plugins, scenario):
    for part in ('config/settings/plugins', 'cache', 'state', 'bin'):
        (case / part).mkdir(parents=True)
    shutil.copytree(plugins / 'git-companion', case / 'config/plugins/git-companion', ignore=shutil.ignore_patterns('*.bak'))
    runner.write_json(case / 'config/settings.json', dict(settingsVersion=62))
    runner.write_json(case / 'config/plugins.json', dict(version=6, states={}, sources=[]))
    shared = dict(platform='github', repo='synthetic/alpha', group='', refreshInterval=60, opaque=dict(keep='shared'))
    bar = dict(widgets=dict(left=[dict(id='plugin:git-companion', tag='selected', instanceSettings=dict(opaque=dict(keep='selected'))),
                                dict(id='plugin:git-companion', tag='sibling', instanceSettings=dict(repo='synthetic/other')),
                                dict(id='plugin:git-companion', tag='inherited')]))
    runner.write_json(case / 'config/settings/plugins/git-companion.json', shared)
    runner.write_json(case / 'config/settings/bar.json', bar)
    initial = dict(shared=deepcopy(shared), bar=deepcopy(bar))
    edited = deepcopy(initial)
    overrides = edited['bar']['widgets']['left'][0]['instanceSettings']
    overrides['repo'] = 'synthetic/beta'
    cold = dict(platform='github', repo='synthetic/beta', group='', interval=60, scope='synthetic/beta', base='synthetic/alpha')
    if scenario == 'io-retry':
        expectations = dict(failed=initial, edited=edited)
    elif scenario in ('stale-base', 'source-replacement'):
        stale = deepcopy(initial)
        stale['shared']['repo'] = 'synthetic/gamma'
        expectations = dict(stale=stale)
        cold.update(repo='synthetic/gamma', scope='synthetic/gamma', base='synthetic/gamma')
    elif scenario == 'inheritance':
        changed = deepcopy(edited)
        changed['shared']['repo'] = 'synthetic/gamma'
        reset = deepcopy(changed)
        reset['bar']['widgets']['left'][0]['instanceSettings'].pop('repo')
        following = deepcopy(reset)
        following['shared']['repo'] = 'synthetic/delta'
        expectations = {'edited': edited, 'base-changed': changed, 'reset-staged': deepcopy(changed), 'reset': reset, 'inherited': following}
        cold.update(repo='synthetic/delta', scope='synthetic/delta', base='synthetic/delta')
    elif scenario == 'held-response':
        replacement = deepcopy(edited)
        replacement['bar']['widgets']['left'][0]['instanceSettings']['repo'] = 'synthetic/gamma'
        expectations = dict(held=edited, replacement=replacement)
        cold.update(repo='synthetic/gamma', scope='synthetic/gamma')
    elif scenario == 'platform-group':
        overrides.update(platform='gitlab', group='synthetic-team', refreshInterval=90)
        expectations = dict(edited=edited)
        cold.update(platform='gitlab', group='synthetic-team', interval=90, scope='synthetic-team')
    else:
        overrides.update(platform='gitlab', repo='')
        expectations = dict(edited=edited)
        cold.update(platform='gitlab', repo='', scope='')
    runner.write_json(case / 'expectations.json', expectations)
    runner.write_json(case / 'cold.json', cold)
    return expectations, cold


def hashes(config):
    return {str(path.relative_to(config)): hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(config.rglob('*.json'))}


def run(args, profile, scenario):
    started = time.monotonic()
    case, out = args.work_root / scenario, args.output / scenario
    case.mkdir(); out.mkdir()
    install = case / 'install'
    shutil.copytree(args.source, install, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
    expectations, cold_expected = seed(case, args.plugins, scenario)
    if args.negative_control:
        name = {'shared-client': 'Main.qml', 'shared-bar': 'BarWidget.qml', 'shared-desktop': 'DesktopWidget.qml', 'desktop-text': 'DesktopWidget.qml'}[args.negative_control]
        target = case / 'config/plugins/git-companion' / name
        original = target.read_text()
        if args.negative_control == 'shared-client':
            needle = 'function settingsConsumerFor(context) {'
            replacement = needle + '\n    context = pluginApi.settingsContext;'
        elif args.negative_control == 'desktop-text':
            needle = 'text: root.text'
            replacement = 'text: "wrong-rendered-count"'
        else:
            needle = 'settingsConsumerFor(pluginApi.settingsContext)'
            replacement = 'settingsConsumerFor(pluginApi.mainInstance.pluginApi.settingsContext)'
        if original.count(needle) != 1:
            raise RuntimeError('review the selected Git control anchor')
        target.write_text(original.replace(needle, replacement, 1))
        runner.write_json(out / 'mutation.json', dict(control=args.negative_control,
            target='git-companion/' + name, sha256=hashlib.sha256(target.read_bytes()).hexdigest()))
    (out / 'persisted').mkdir()
    endpoint = case / 'bin/endpoint.py'
    shutil.copy2(args.source / 'Scripts/dev/fixtures/plugin-settings-git-matrix-endpoint.py', endpoint)
    endpoint.chmod(0o700)
    for name in ('gh', 'glab'):
        (case / 'bin' / name).symlink_to(endpoint)
    env = dict(PATH=str(case / 'bin') + os.pathsep + os.environ['PATH'], PHA_GIT_SCENARIO=scenario,
               PHA_GIT_CASE=str(case), PHA_GIT_OUTPUT=str(out),
               PHA_GIT_DISK=str(args.source / 'Scripts/dev/fixtures/plugin-settings-git-matrix-disk.py'),
               PHA_GIT_REPLACE=str(args.source / 'Scripts/dev/fixtures/plugin-settings-git-matrix-replace.py'))
    fixture = args.source / 'Scripts/dev/fixtures/plugin-settings-git-matrix.qml'
    inherited = []
    if args.baseline_plugins and not args.negative_control:
        baseline_widgets = case / 'baseline-widgets'; baseline_widgets.mkdir()
        for name in ('BarWidget.qml', 'DesktopWidget.qml'):
            shutil.copy2(args.baseline_plugins / 'git-companion' / name, baseline_widgets / name)
        baseline = out / 'presentation-baseline'; baseline.mkdir()
        before = hashes(case / 'config')
        text = runner.run_fixture(profile, install, case, baseline, fixture,
            extra_env=dict(env, PHA_GIT_PRESENTATION_BASELINE='1'), timeout=105)
        after = hashes(case / 'config')
        generated = set(after) - set(before)
        # First rendering initializes the existing shell color owner. It is not
        # a plugin/placement preference publication and is reported separately.
        if ('GIT_MATRIX: PRESENTATION_BASELINE ' + scenario not in text
                or any(after.get(name) != digest for name, digest in before.items())
                or generated - {'colors.json'}):
            raise RuntimeError('original widget diagnostic characterization failed or published configuration')
        inherited = runtime_errors(text)
        # Only these unchanged presentation sources may qualify diagnostics;
        # generic Settings/Main/session errors always remain fatal.
        if any(not item.startswith(('BarWidget.qml/', 'DraggableDesktopWidget.qml/')) for item in inherited):
            raise RuntimeError('baseline failed outside the inherited presentation sources')
        runner.write_json(baseline / 'result.json', dict(status='CHARACTERIZED', productionCoverage=False,
            diagnostics=inherited, seededConfigurationHashesUnchanged=before, generatedFiles=sorted(generated),
            sourceHashes={name: hashlib.sha256((baseline_widgets / name).read_bytes()).hexdigest()
                          for name in ('BarWidget.qml', 'DesktopWidget.qml')}))
    try:
        try:
            text = runner.run_fixture(profile, install, case, out, fixture, extra_env=env, timeout=105)
        except RuntimeError:
            rejected_at = {'shared-client': 'selected client must not use shared Main configuration',
                           'desktop-text': 'actual desktop Text must render the selected result'}.get(
                               args.negative_control, 'Bar/Desktop must use their exact selected client')
            log, code = out / 'runtime.log', out / 'runtime.exit'
            if not args.negative_control or not log.is_file() or not code.is_file() or code.read_text().strip() != '2' or not any('GIT_MATRIX_ASSERT:' in line and rejected_at in line for line in log.read_text().splitlines()):
                raise
            result = dict(id=scenario, status='PASS', kind='rejecting-control', control=args.negative_control,
                          actualRuntimeExit=2, rejectedAt=rejected_at, productionCoverage=False)
            runner.write_json(out / 'result.json', result)
            runner.remove_completed_installs(case, out)
            return result
    finally:
        (case / 'config/settings').chmod(0o700)
    if args.negative_control:
        raise RuntimeError('selected Git shared-client mutation unexpectedly passed')
    warm_runtime = observe_runtime(text, inherited)
    warm_presentations = presentation_observations(text)
    if 'GIT_MATRIX: PASS ' + scenario not in text:
        raise RuntimeError('Git selected-client warm assertion failed: ' + scenario)
    if {path.stem for path in (out / 'persisted').glob('*.json')} != set(expectations):
        raise RuntimeError('Git independent boundary coverage mismatch')
    for phase, expected in expectations.items():
        observed = json.loads((out / 'persisted' / (phase + '.json')).read_text())
        if observed.get('status') != 'PASS' or observed.get('values') != expected:
            raise RuntimeError('Git independent persisted readback failed: ' + phase)
    recorded = [json.loads(line) for line in (out / 'calls.jsonl').read_text().splitlines()]
    queries = [item for item in recorded if item['argv'][:2] in (['search', 'issues'], ['search', 'prs'], ['issue', 'list'], ['mr', 'list'])]
    if scenario in ('stale-base', 'source-replacement') and any('synthetic/beta' in item['argv'] for item in queries):
        raise RuntimeError('refused local configuration reached the query endpoint')
    if scenario == 'platform-group' and not any(item['endpoint'] == 'glab' and '--group' in item['argv'] and 'synthetic-team' in item['argv'] for item in queries):
        raise RuntimeError('actual selected GitLab group endpoint not observed')
    if scenario == 'held-response' and not (out / 'entered').is_file():
        raise RuntimeError('old query never reached the deterministic hold boundary')
    before = hashes(case / 'config')
    cold = out / 'cold'; cold.mkdir()
    text = runner.run_fixture(profile, install, case, cold, fixture, extra_env=dict(env, PHA_GIT_COLD='1'), timeout=105)
    cold_runtime = observe_runtime(text, inherited)
    cold_presentations = presentation_observations(text)
    if 'GIT_MATRIX: COLD_PASS ' + scenario not in text or hashes(case / 'config') != before:
        raise RuntimeError('separate nonpublishing cold Git consumer failed: ' + scenario)
    result = dict(id=scenario, status='PASS', seconds=round(time.monotonic()-started, 3),
                   actualSettingsAndPanel=True, actualNativeOwner=True, inertGitEndpoints=True,
                   actualBarAndDesktopCounts=True, presentationContexts=['shared', 'selected', 'sibling', 'inherited'],
                   runtime=dict(warm=warm_runtime, cold=cold_runtime), desktopHeadingAliasRepaired=False,
                   presentationObservations=dict(warm=warm_presentations, cold=cold_presentations),
                  independentPersistedBoundaries=list(expectations), separateNonpublishingColdConsumer=True,
                  coldConfigurationHashes=before, coldExpected=cold_expected,
                  input='real controls own committed/selection signals; original keyboard witness remains separate',
                  completeCatalog=False, completePlanAcceptance=False)
    runner.write_json(out / 'result.json', result)
    runner.remove_completed_installs(case, out)
    print('GIT_MATRIX ' + scenario + ': PASS', flush=True)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    profile_argument(parser)
    for name in ('source', 'plugins', 'work-root', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--scenario', choices=SCENARIOS)
    parser.add_argument('--baseline-plugins', type=Path, help='pinned original widget sources for independent inherited-diagnostic characterization')
    parser.add_argument('--negative-control', choices=('shared-client', 'shared-bar', 'shared-desktop', 'desktop-text'))
    args = parser.parse_args()
    if args.negative_control and args.scenario != 'io-retry':
        parser.error('shared-client control requires explicit --scenario io-retry')
    profile = activate_profile(args.guest_profile); profile.prepare_roots()
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent):
            parser.error('fresh roots must belong to the verified profile')
    with (profile.work_base / '.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        args.work_root.mkdir(exist_ok=False); args.output.mkdir(exist_ok=False)
        runner.write_json(args.output / 'diagnostic-canaries.json', diagnostic_canaries())
        inputs = {str(p.relative_to(args.source)): hashlib.sha256(p.read_bytes()).hexdigest()
                  for p in [Path(__file__), *sorted((args.source / 'Scripts/dev/fixtures').glob('plugin-settings-git-matrix*'))] if p.is_file()}
        inputs['plugins'] = {str(p.relative_to(args.plugins)): hashlib.sha256(p.read_bytes()).hexdigest()
                             for p in sorted((args.plugins / 'git-companion').rglob('*')) if p.is_file()}
        inputs['desktopContextOwner'] = hashlib.sha256((args.source / 'Modules/DesktopWidgets/DraggableDesktopWidget.qml').read_bytes()).hexdigest()
        if args.baseline_plugins:
            inputs['baselineWidgets'] = {name: hashlib.sha256((args.baseline_plugins / 'git-companion' / name).read_bytes()).hexdigest()
                                        for name in ('BarWidget.qml', 'DesktopWidget.qml')}
        runner.write_json(args.output / 'inputs.json', inputs)
        results = []
        scenarios = (args.scenario,) if args.scenario else SCENARIOS
        try:
            for scenario in scenarios:
                runner.write_json(args.output / 'status.json', dict(status='RUNNING', completed=len(results), expected=len(scenarios), current=scenario))
                results.append(run(args, profile, scenario))
            runner.write_json(args.output / 'result.json', dict(status='PASS', cases=results,
                kind='rejecting-control' if args.negative_control else 'selected-git-matrix', completePlanAcceptance=False))
            runner.write_json(args.output / 'status.json', dict(status='PASS', completed=len(results), expected=len(scenarios)))
            print('PLUGIN_SETTINGS_GIT_MATRIX: PASS', flush=True)
        except Exception as error:
            runner.write_json(args.output / 'status.json', dict(status='FAIL', completed=len(results), expected=len(scenarios), error=str(error)))
            raise


if __name__ == '__main__':
    main()
