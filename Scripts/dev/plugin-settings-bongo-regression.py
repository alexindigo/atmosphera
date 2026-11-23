#!/usr/bin/env python3
"""Selected Bongo page/native documents and real Bar animation over inert IO."""
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

spec = importlib.util.spec_from_file_location('bongo_runner', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(spec); spec.loader.exec_module(runner)


def hashes(case):
    return {str(p.relative_to(case)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((case / 'config').rglob('*.json'))}


@receipt_run
def run(args, profile, scope):
    case, out = args.work_root / scope, args.output / scope
    case.mkdir(); out.mkdir(); (out / 'persisted').mkdir()
    install = case / 'install'
    shutil.copytree(args.source, install, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
    for part in ('config/settings/plugins', 'cache', 'state', 'bin', 'home'):
        (case / part).mkdir(parents=True)
    dest = case / 'config/plugins/slowbongo'; shutil.copytree(args.plugins / 'slowbongo', dest)
    substitutions = {}
    for fixture, target in [('spectrum', 'SpectrumService.qml'), ('media', 'MediaService.qml')]:
        path = install / 'Services/Media' / target
        replacement = args.source / ('Scripts/dev/fixtures/plugin-settings-bongo-' + fixture + '.qml')
        substitutions[str(path.relative_to(install))] = dict(original=hashlib.sha256(path.read_bytes()).hexdigest(), replacement=hashlib.sha256(replacement.read_bytes()).hexdigest())
        shutil.copy2(replacement, path)
    endpoint = (args.source / 'Scripts/dev/fixtures/plugin-settings-bongo-endpoint.py').read_text()
    for name in ('which', 'id', 'sh', 'evtest', 'test'):
        path = case / 'bin' / name; path.write_text(endpoint); path.chmod(0o755)
    # Substitute only the reviewed plugin's argv. Do not intercept the shell's
    # own Registry/settings IO or permit a fallback to real input enumeration.
    counts = dict.fromkeys(('which', 'id', 'sh', 'evtest', 'test'), 0)
    for path in dest.glob('*.qml'):
        original = path.read_text(); text = original
        for name in counts:
            old = '["' + name + '",'
            counts[name] += text.count(old)
            text = text.replace(old, '[' + json.dumps(str(case / 'bin' / name)) + ',')
        if original != text:
            path.write_text(text)
            substitutions[str(path.relative_to(case))] = dict(original=hashlib.sha256(original.encode()).hexdigest(), replacement=hashlib.sha256(text.encode()).hexdigest())
    if counts != dict(which=1, id=1, sh=3, evtest=1, test=1): raise RuntimeError('review Bongo endpoint substitution: ' + repr(counts))
    runner.write_json(out / 'substitutions.json', substitutions)
    (case / 'requests.jsonl').write_text('')
    shared = dict(catSize=1.0, catOffsetY=0.0, catColor='primary', idleTimeout=150, waitingTimeout=30000, inputDevices=[], raveMode=False, tappyMode=False, useMprisFilter=False, widthPadding=0.2, opaque=dict(keep='shared'))
    bar = dict(widgets=dict(left=[dict(id='plugin:slowbongo', tag='selected', instanceSettings=dict(opaque=dict(keep='selected'))), dict(id='plugin:slowbongo', tag='sibling', instanceSettings=dict(catSize=0.7, catColor='secondary', opaque=dict(keep='sibling'))), dict(id='plugin:slowbongo', tag='inherited', instanceSettings=dict(opaque=dict(keep='inherited')))]))
    initial = dict(shared=shared, bar=bar)
    edited = deepcopy(initial)
    (edited['shared'] if scope == 'shared' else edited['bar']['widgets']['left'][0]['instanceSettings'])['catSize'] = 1.25
    reset = deepcopy(edited)
    (reset['shared'] if scope == 'shared' else reset['bar']['widgets']['left'][0]['instanceSettings']).pop('catSize')
    following = deepcopy(reset); following['shared']['catSize'] = 1.25
    policy = deepcopy(following)
    (policy['shared'] if scope == 'shared' else policy['bar']['widgets']['left'][0]['instanceSettings']).update(catColor='tertiary', catOffsetY=0.2, inputDevices=['/dev/input/event90'], raveMode=True, tappyMode=True, useMprisFilter=True)
    expected = dict(initial=initial, discarded=initial, edited=edited, **{'reset-staged': edited}, reset=reset, following=following, policy=policy)
    for path, value in [('input.json', dict(plugin='slowbongo')), ('expectations.json', expected), ('config/settings.json', dict(settingsVersion=62)), ('config/plugins.json', dict(version=6, states={}, sources=[])), ('config/settings/plugins/slowbongo.json', shared), ('config/settings/bar.json', bar)]: runner.write_json(case / path, value)
    wanted = 'original Bar child uses saved selected size' if args.old_red else None
    if args.control:
        controls = {
            'shared-client': ('BarWidget.qml', 'settingsConsumerFor(pluginApi.settingsContext)', 'settingsConsumerFor(mainInstance.pluginApi.settingsContext)', 'actual Bars share exact captured client'),
            'child': ('BarWidget.qml', 'font.pixelSize: root.capsuleHeight * root.activeCatSize', 'font.pixelSize: root.capsuleHeight', 'actual Bar child font uses selected size'),
            'retirement': ('Main.qml', 'root._settingsConsumers.delete(context)', 'context', 'retired held check cannot restart or notify'),
            'device-filter': ('Main.qml', '!client.current || client.inputDevices.indexOf(device) < 0', '!client.current', 'only selected source receives actual input'),
        }
        name, old, new, wanted = controls[args.control]; path = dest / name; text = path.read_text()
        if text.count(old) != 1: raise RuntimeError('stale Bongo control: ' + old)
        path.write_text(text.replace(old, new))
    env = dict(PHA_BONGO_SCOPE=scope, PHA_BONGO_CASE=str(case), PHA_BONGO_OUTPUT=str(out), PHA_BONGO_DISK=str(args.source / 'Scripts/dev/fixtures/plugin-settings-query-disk.py'), PHA_BONGO_OLD_RED='1' if args.old_red else '0', HOME=str(case / 'home'))
    modes = [('life', '')] if args.lifetime else [('edit', ''), ('cold', 'edited'), ('reset', ''), ('cold', 'reset'), ('follow', ''), ('cold', 'following'), ('policy', ''), ('cold', 'policy')]
    for mode, boundary in modes:
        output = out / (mode + ('-' + boundary if boundary else '')); output.mkdir(); before = hashes(case)
        try:
            text = runner.run_fixture(profile, install, case, output, args.source / 'Scripts/dev/fixtures/plugin-settings-bongo-native.qml', extra_env=dict(env, PHA_BONGO_MODE=mode, PHA_BONGO_BOUNDARY=boundary), extra_lint=tuple(sorted(dest.glob('*.qml'))), timeout=115)
        except RuntimeError:
            if not wanted or not (output / 'runtime.log').is_file() or wanted not in (output / 'runtime.log').read_text() or (output / 'runtime.exit').read_text().strip() != '2': raise
            if args.old_red and not (out / 'persisted/edited.json').is_file(): raise RuntimeError('Bongo red precedes native publication')
            result = dict(status='PASS', rejectedAt=wanted, originalRed=args.old_red, completePlanAcceptance=False)
            stage_receipt(out / 'result.json', result); runner.remove_completed_installs(case, out); return result
        if 'BONGO_NATIVE: PASS ' + scope + ' ' + mode not in text or any(x in text for x in ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected', 'BONGO_ASSERT:')): raise RuntimeError('Bongo consumer/diagnostic failure')
        if mode == 'cold' and hashes(case) != before: raise RuntimeError('Bongo cold reader published configuration')
        stage_receipt(output / 'observed.json', dict(status='PASS', configurationBefore=before, configurationAfter=hashes(case)))
    if wanted: raise RuntimeError('Bongo control escaped')
    if not args.lifetime:
        for boundary, value in expected.items():
            if json.loads((out / ('persisted/' + boundary + '.json')).read_text()) != dict(status='PASS', values=value): raise RuntimeError('Bongo independent documents differ')
    shutil.copy2(case / 'requests.jsonl', out / 'requests.jsonl')
    for row in map(json.loads, (case / 'requests.jsonl').read_text().splitlines()):
        path = Path('/proc') / str(row['pid']) / 'stat'
        if path.exists() and path.read_text().split(') ', 1)[1].split()[19] == row['start']: raise RuntimeError('Bongo endpoint survived engine')
    result = dict(status='PASS', scope=scope, independentBoundaries=[] if args.lifetime else sorted(expected), coldReaders=[] if args.lifetime else ['edited', 'reset', 'following', 'policy'], lifetime=args.lifetime, physicalProof=False, completePlanAcceptance=False)
    stage_receipt(out / 'result.json', result); runner.remove_completed_installs(case, out)
    print('BONGO_NATIVE ' + scope + ': PASS', flush=True); return result


@receipt_run
def main():
    parser = argparse.ArgumentParser(description=__doc__); profile_argument(parser)
    for key in ('source', 'plugins', 'work-root', 'output'): parser.add_argument('--' + key, type=Path, required=True)
    parser.add_argument('--scope', choices=('shared', 'instance')); parser.add_argument('--old-red', action='store_true'); parser.add_argument('--lifetime', action='store_true')
    parser.add_argument('--control', choices=('shared-client', 'child', 'retirement', 'device-filter'))
    args = parser.parse_args(); profile = activate_profile(args.guest_profile); profile.prepare_roots()
    if Path(__file__).resolve() != args.source.resolve() / 'Scripts/dev/plugin-settings-bongo-regression.py': parser.error('execute supplied source')
    if (args.old_red or args.control or args.lifetime) and args.scope != 'instance': parser.error('explicit instance scope required')
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent): parser.error('fresh owned profile roots required')
    with (profile.work_base / '.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB); args.work_root.mkdir(); args.output.mkdir()
        paths = [Path(__file__), *sorted((args.source / 'Scripts/dev/fixtures').glob('plugin-settings-bongo-*')), args.source / 'Scripts/dev/fixtures/plugin-settings-query-disk.py']
        runner.write_json(args.output / 'inputs.json', dict(source=str(args.source), plugins=str(args.plugins), files={str(p.relative_to(args.source)): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths if p.is_file()}, pluginFiles={str(p.relative_to(args.plugins)): hashlib.sha256(p.read_bytes()).hexdigest() for p in (args.plugins / 'slowbongo').rglob('*') if p.is_file()}))
        results = [run(args, profile, scope) for scope in ((args.scope,) if args.scope else ('instance', 'shared'))]
        stage_receipt(args.output / 'result.json', dict(status='PASS', cases=results, completePlanAcceptance=False))


if __name__ == '__main__': main()
