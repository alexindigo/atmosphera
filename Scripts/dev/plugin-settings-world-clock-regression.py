#!/usr/bin/env python3
"""World Clock direct selected consumers, native pages and cold readers. Guest only."""
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
BAD = ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected', 'is not installed', 'WORLD_ASSERT:')


def hashes(case):
    return {str(p.relative_to(case)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted((case / 'config').rglob('*.json'))}


def zones(*names):
    return [dict(name=name, timezone=timezone, enabled=True) for name, timezone in names]


def run(args, profile, scope):
    case, out = args.work_root / scope, args.output / scope
    case.mkdir(); out.mkdir(); (out / 'persisted').mkdir()
    install = case / 'install'
    shutil.copytree(args.source, install, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
    for part in ('config/settings/plugins', 'cache', 'state', 'bin'):
        (case / part).mkdir(parents=True)
    shutil.copytree(args.plugins / 'world-clock', case / 'config/plugins/world-clock')
    adapter = case / 'bin/date'
    shutil.copy2(args.source / 'Scripts/dev/fixtures/plugin-settings-world-clock-date.py', adapter)
    adapter.chmod(0o700)
    shared = dict(rotationInterval=5000, timeFormat='h:mm A', showDate=False,
                  timezones=zones(('New York', 'America/New_York'), ('London', 'Europe/London')), opaque=dict(keep='shared'))
    bar = dict(widgets=dict(left=[dict(id='plugin:world-clock', tag='selected', instanceSettings=dict(opaque=dict(keep='selected'))),
                                 dict(id='plugin:world-clock', tag='sibling', instanceSettings=dict(rotationInterval=12000, timeFormat='HH:mm', showDate=False,
                                      timezones=zones(('Tokyo', 'Asia/Tokyo'), ('Sydney', 'Australia/Sydney')))),
                                 dict(id='plugin:world-clock', tag='inherited')]))
    initial = dict(shared=shared, bar=bar)
    edited = deepcopy(initial)
    (edited['shared'] if scope == 'shared' else edited['bar']['widgets']['left'][0]['instanceSettings']).update(rotationInterval=1000, timeFormat='HH:mm:ss')
    reset = deepcopy(edited)
    target = reset['shared'] if scope == 'shared' else reset['bar']['widgets']['left'][0]['instanceSettings']
    for key in ('rotationInterval', 'timeFormat'):
        target.pop(key)
    following = deepcopy(reset)
    following['shared'].update(rotationInterval=2000, timeFormat='h:mm:ss A')
    expected = dict(initial=initial, discarded=initial, edited=edited, **{'reset-staged': edited}, reset=reset, following=following)
    runner.write_json(case / 'expectations.json', expected)
    runner.write_json(case / 'config/settings.json', dict(settingsVersion=62))
    runner.write_json(case / 'config/plugins.json', dict(version=6, states={}, sources=[]))
    runner.write_json(case / 'config/settings/plugins/world-clock.json', shared)
    runner.write_json(case / 'config/settings/bar.json', bar)
    wanted = None
    if args.negative_control:
        path = case / 'config/plugins/world-clock/BarWidget.qml'
        text = path.read_text()
        if args.negative_control == 'shared-reader':
            needle = 'property var cfg: pluginApi?.pluginSettings || ({})'
            replacement = 'property var cfg: pluginApi?.mainInstance?.pluginApi?.pluginSettings || ({})'
            wanted = 'actual rotation Timer follows selected interval'
        else:
            needle = 'text: root.currentTime\n        color:'
            replacement = 'text: "wrong rendered time"\n        color:'
            wanted = 'actual child time Text follows selected result'
        if text.count(needle) != 1:
            raise RuntimeError('review World Clock rejecting-control anchor')
        path.write_text(text.replace(needle, replacement, 1))
        runner.write_json(out / 'mutation.json', dict(control=args.negative_control, sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
    fixture = args.source / 'Scripts/dev/fixtures/plugin-settings-world-clock.qml'
    env = dict(PHA_WORLD_SCOPE=scope, PHA_WORLD_CASE=str(case), PHA_WORLD_OUTPUT=str(out),
               PHA_WORLD_DISK=str(args.source / 'Scripts/dev/fixtures/plugin-settings-world-clock-disk.py'),
               PATH=str(case / 'bin') + ':' + os.environ['PATH'])
    for mode, boundary in (('edit', ''), ('cold', 'edited'), ('reset', ''), ('cold', 'reset'), ('follow', ''), ('cold', 'following')):
        output = out / (mode + ('-' + boundary if boundary else '')); output.mkdir()
        before = hashes(case)
        try:
            text = runner.run_fixture(profile, install, case, output, fixture,
                extra_env=dict(env, PHA_WORLD_MODE=mode, PHA_WORLD_BOUNDARY=boundary), timeout=130,
                extra_lint=tuple(sorted((case / 'config/plugins/world-clock').glob('*.qml'))))
        except RuntimeError:
            log, code = output / 'runtime.log', output / 'runtime.exit'
            if not wanted or not log.is_file() or not code.is_file() or code.read_text().strip() != '2' or wanted not in log.read_text():
                raise
            result = dict(status='PASS', kind='rejecting-control', control=args.negative_control, rejectedAt=wanted, productionCoverage=False)
            runner.write_json(out / 'result.json', result)
            return result
        if args.negative_control:
            raise RuntimeError('World Clock rejecting control escaped')
        marker = 'WORLD: COLD_PASS ' + scope + ' ' + boundary if mode == 'cold' else 'WORLD: PASS ' + scope + ' ' + mode
        if marker not in text or any(item in text for item in BAD):
            raise RuntimeError('World Clock actual consumer failed: ' + mode + '/' + boundary)
        if mode == 'edit' and 'WORLD_ROTATION' not in text:
            raise RuntimeError('actual selected Timer rotation was not observed')
        if mode == 'cold' and hashes(case) != before:
            raise RuntimeError('World Clock cold reader changed configuration')
        runner.write_json(output / 'observed.json', dict(status='PASS', mode=mode, boundary=boundary, configurationHashes=hashes(case)))
    observed = {p.stem for p in (out / 'persisted').glob('*.json')}
    if observed != set(expected):
        raise RuntimeError('missing independent World Clock document boundaries')
    for name in expected:
        if json.loads((out / 'persisted' / (name + '.json')).read_text()) != dict(status='PASS', values=expected[name]):
            raise RuntimeError('independent World Clock readback differs: ' + name)
    requests = [json.loads(line) for line in (out / 'date.jsonl').read_text().splitlines()]
    if {row['timezone'] for row in requests} != {'America/New_York', 'Europe/London', 'Asia/Tokyo', 'Australia/Sydney'} or {row['format'] for row in requests} != {'+%H:%M', '+%H:%M:%S', '+%I:%M %p', '+%I:%M:%S %p'}:
        raise RuntimeError('missing actual timezone/format endpoint requests')
    result = dict(status='PASS', scope=scope, realMainPageBar=True, supportedFields=['rotationInterval', 'timeFormat'],
                  preservedFields=['timezones', 'showDate', 'opaque'], knownUnrepairedFindings=['P023', 'P088', 'P107', 'P128'],
                  independentBoundaries=sorted(observed), unchangedHashColdReaders=['edited', 'reset', 'following'],
                  actualRotation=True, completePlanAcceptance=False)
    runner.write_json(out / 'result.json', result); runner.remove_completed_installs(case, out)
    print('WORLD ' + scope + ': PASS', flush=True)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    profile_argument(parser)
    for name in ('source', 'plugins', 'work-root', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--scope', choices=('shared', 'instance'))
    parser.add_argument('--negative-control', choices=('shared-reader', 'rendered-time'))
    args = parser.parse_args()
    profile = activate_profile(args.guest_profile); profile.prepare_roots()
    if Path(__file__).resolve() != args.source.resolve() / 'Scripts/dev/plugin-settings-world-clock-regression.py':
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
        inputs = dict(native=runner.input_fingerprints(args), files={str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
                      for root, paths in ((args.source, [Path(__file__), *sorted((args.source / 'Scripts/dev/fixtures').glob('plugin-settings-world-clock*'))]),
                                          (args.plugins, sorted((args.plugins / 'world-clock').rglob('*')))) for p in paths if p.is_file()})
        runner.write_json(args.output / 'inputs.json', inputs)
        results = [run(args, profile, scope) for scope in ((args.scope,) if args.scope else ('instance', 'shared'))]
        runner.write_json(args.output / 'result.json', dict(status='PASS', cases=results, completePlanAcceptance=False))
        print('PLUGIN_SETTINGS_WORLD_CLOCK: PASS', flush=True)


if __name__ == '__main__':
    main()
