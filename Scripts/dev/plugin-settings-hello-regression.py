#!/usr/bin/env python3
"""Hello World both-scope real page/native/Panel/Bar consumers. Guest only."""
import argparse
from copy import deepcopy
import fcntl
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil

from guest_profile import activate_profile, profile_argument

SPEC = importlib.util.spec_from_file_location('host_runner', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)
BAD = ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected', 'is not installed', 'HELLO_ASSERT:')


def hashes(case):
    return {str(p.relative_to(case)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted((case / 'config').rglob('*.json'))}


def run(args, profile, scope):
    case, out = args.work_root / scope, args.output / scope
    case.mkdir(); out.mkdir(); (out / 'persisted').mkdir()
    install = case / 'install'
    shutil.copytree(args.source, install, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
    for part in ('config/settings/plugins', 'cache', 'state'):
        (case / part).mkdir(parents=True)
    shutil.copytree(args.plugins / 'hello-world', case / 'config/plugins/hello-world')
    shared = dict(message='shared', iconColor='secondary', opaque=dict(keep='shared'))
    bar = dict(widgets=dict(left=[dict(id='plugin:hello-world', tag='selected', instanceSettings=dict(opaque=dict(keep='selected'))),
                                 dict(id='plugin:hello-world', tag='sibling', instanceSettings=dict(message='sibling', iconColor='primary')),
                                 dict(id='plugin:hello-world', tag='inherited')]))
    initial = dict(shared=shared, bar=bar)
    edited = deepcopy(initial)
    (edited['shared'] if scope == 'shared' else edited['bar']['widgets']['left'][0]['instanceSettings']).update(message='', iconColor='tertiary')
    reset = deepcopy(edited)
    target = reset['shared'] if scope == 'shared' else reset['bar']['widgets']['left'][0]['instanceSettings']
    for key in ('message', 'iconColor'):
        target.pop(key)
    following = deepcopy(reset)
    following['shared'].update(message='next', iconColor='secondary')
    expected = dict(initial=initial, discarded=initial, edited=edited, **{'reset-staged': edited}, reset=reset, following=following)
    runner.write_json(case / 'expectations.json', expected)
    runner.write_json(case / 'config/settings.json', dict(settingsVersion=62))
    runner.write_json(case / 'config/plugins.json', dict(version=6, states={}, sources=[]))
    runner.write_json(case / 'config/settings/plugins/hello-world.json', shared)
    runner.write_json(case / 'config/settings/bar.json', bar)
    expected_rejection = None
    if args.negative_control:
        path = case / 'config/plugins/hello-world' / ('BarWidget.qml' if args.negative_control == 'shared-bar' else 'Panel.qml')
        text = path.read_text()
        needle = 'text: pluginApi?.pluginSettings?.message ?? pluginApi?.manifest?.metadata?.defaultSettings?.message ?? ""'
        replacement = ('text: pluginApi?.mainInstance?.pluginApi?.pluginSettings?.message || ""' if args.negative_control == 'shared-reader'
                       else 'text: "wrong rendered message"')
        if args.negative_control == 'shared-bar':
            needle = 'property var cfg: pluginApi?.pluginSettings || ({})'
            replacement = 'property var cfg: pluginApi?.mainInstance?.pluginApi?.pluginSettings || ({})'
        if text.count(needle) != 1:
            raise RuntimeError('review Hello World rejecting-control anchor')
        path.write_text(text.replace(needle, replacement, 1))
        expected_rejection = ('actual Bar foreground follows selected field' if args.negative_control == 'shared-bar' else
                              'actual child Panel Text follows selected field')
        runner.write_json(out / 'mutation.json', dict(control=args.negative_control, sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
    fixture = args.source / 'Scripts/dev/fixtures/plugin-settings-hello.qml'
    env = dict(PHA_HELLO_SCOPE=scope, PHA_HELLO_CASE=str(case), PHA_HELLO_OUTPUT=str(out),
               PHA_HELLO_DISK=str(args.source / 'Scripts/dev/fixtures/plugin-settings-hello-disk.py'))
    for mode, boundary in (('edit', ''), ('cold', 'edited'), ('reset', ''), ('cold', 'reset'), ('follow', ''), ('cold', 'following')):
        output = out / (mode + ('-' + boundary if boundary else '')); output.mkdir()
        before = hashes(case)
        try:
            text = runner.run_fixture(profile, install, case, output, fixture,
                extra_env=dict(env, PHA_HELLO_MODE=mode, PHA_HELLO_BOUNDARY=boundary), timeout=100,
                extra_lint=tuple(sorted((case / 'config/plugins/hello-world').glob('*.qml'))))
        except RuntimeError:
            log, code = output / 'runtime.log', output / 'runtime.exit'
            if not expected_rejection or not log.is_file() or not code.is_file() or code.read_text().strip() != '2' or expected_rejection not in log.read_text():
                raise
            result = dict(status='PASS', kind='rejecting-control', control=args.negative_control,
                          rejectedAt=expected_rejection, productionCoverage=False)
            runner.write_json(out / 'result.json', result); runner.remove_completed_installs(case, out)
            return result
        if args.negative_control:
            raise RuntimeError('Hello World rejecting control escaped')
        marker = 'HELLO: COLD_PASS ' + scope + ' ' + boundary if mode == 'cold' else 'HELLO: PASS ' + scope + ' ' + mode
        if marker not in text or any(item in text for item in BAD):
            raise RuntimeError('Hello World actual consumer failed: ' + mode + '/' + boundary)
        if mode == 'cold' and hashes(case) != before:
            raise RuntimeError('Hello World cold reader changed configuration')
        runner.write_json(output / 'observed.json', dict(status='PASS', mode=mode, boundary=boundary, configurationHashes=hashes(case)))
    observed = {p.stem for p in (out / 'persisted').glob('*.json')}
    if observed != set(expected):
        raise RuntimeError('missing independent Hello World document boundaries')
    for name in expected:
        if json.loads((out / 'persisted' / (name + '.json')).read_text()) != dict(status='PASS', values=expected[name]):
            raise RuntimeError('independent Hello World readback differs: ' + name)
    result = dict(status='PASS', scope=scope, realMainPagePanelBar=True, bothConfigurationFields=True,
                  independentBoundaries=sorted(observed), unchangedHashColdReaders=['edited', 'reset', 'following'],
                  discardResetInheritance=True, completePlanAcceptance=False)
    runner.write_json(out / 'result.json', result); runner.remove_completed_installs(case, out)
    print('HELLO ' + scope + ': PASS', flush=True)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    profile_argument(parser)
    for name in ('source', 'plugins', 'work-root', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--scope', choices=('shared', 'instance'))
    parser.add_argument('--negative-control', choices=('shared-reader', 'shared-bar', 'rendered-text'))
    args = parser.parse_args()
    profile = activate_profile(args.guest_profile); profile.prepare_roots()
    if Path(__file__).resolve() != args.source.resolve() / 'Scripts/dev/plugin-settings-hello-regression.py':
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
                      for root, paths in ((args.source, [Path(__file__), *sorted((args.source / 'Scripts/dev/fixtures').glob('plugin-settings-hello*'))]),
                                          (args.plugins, sorted((args.plugins / 'hello-world').rglob('*')))) for p in paths if p.is_file()})
        runner.write_json(args.output / 'inputs.json', inputs)
        results = [run(args, profile, scope) for scope in ((args.scope,) if args.scope else ('instance', 'shared'))]
        runner.write_json(args.output / 'result.json', dict(status='PASS', cases=results, completePlanAcceptance=False))
        print('PLUGIN_SETTINGS_HELLO: PASS', flush=True)


if __name__ == '__main__':
    main()
