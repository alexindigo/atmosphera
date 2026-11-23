#!/usr/bin/env python3
"""Scoped real Profiles page/native documents/listing and rendered consumers."""
from fixture_receipts import receipt_run, stage_receipt
import argparse
from copy import deepcopy
import fcntl
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
from guest_profile import activate_profile, profile_argument

spec = importlib.util.spec_from_file_location('profiles_runner', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


def hashes(case):
    return {str(p.relative_to(case)): hashlib.sha256(p.read_bytes()).hexdigest() for p in (case/'config').rglob('*.json')}


@receipt_run
def run(args, profile, scope):
    case, out = args.work_root/scope, args.output/scope
    case.mkdir(); out.mkdir(); (out/'persisted').mkdir()
    install = case/'install'
    shutil.copytree(args.source, install, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
    for part in ('config/settings/plugins', 'cache', 'state'):
        (case/part).mkdir(parents=True)
    dest = case/'config/plugins/shell-profiles'
    shutil.copytree(args.plugins/'shell-profiles', dest)
    wanted = None
    if args.control:
        name, old, new, wanted = {
            'listing': ('Panel.qml', 'settingsConsumerFor(pluginApi.settingsContext)', 'settingsConsumerFor(pluginApi.mainInstance.pluginApi.settingsContext)', 'Panel uses exact Main-owned selected client'),
            'child': ('ProfileRow.qml', 'text: root.profileName', 'text: "wrong rendered profile"', 'actual Panel profile Text'),
        }[args.control]
        path = dest/name; text = path.read_text(); assert text.count(old) == 1, args.control
        path.write_text(text.replace(old, new))
    dirs = {key: str(case/key) for key in ('shared', 'selected', 'sibling', 'following')}
    for key, path in dirs.items():
        (Path(path)/('profile-'+key)).mkdir(parents=True)
    shared = dict(profilesDir=dirs['shared'], icon='bookmark', iconColor='primary', includeWallpapers=True,
                  backupEnabled=True, backupCount=5, lastAppliedProfile='old', opaque=dict(keep='shared'))
    bar = dict(widgets=dict(left=[dict(id='plugin:shell-profiles', tag='selected', instanceSettings=dict(opaque=dict(keep='selected'))),
        dict(id='plugin:shell-profiles', tag='sibling', instanceSettings=dict(profilesDir=dirs['sibling'], opaque=dict(keep='sibling'))),
        dict(id='plugin:shell-profiles', tag='inherited', instanceSettings=dict(opaque=dict(keep='inherited')))]))
    initial = dict(shared=shared, bar=bar); edited = deepcopy(initial)
    (edited['shared'] if scope == 'shared' else edited['bar']['widgets']['left'][0]['instanceSettings']).update(profilesDir=dirs['selected'], includeWallpapers=False, backupEnabled=False, backupCount=2)
    reset = deepcopy(edited)
    for key in ('profilesDir', 'includeWallpapers', 'backupEnabled', 'backupCount'):
        (reset['shared'] if scope == 'shared' else reset['bar']['widgets']['left'][0]['instanceSettings']).pop(key)
    following = deepcopy(reset); following['shared'].update(profilesDir=dirs['following'], includeWallpapers=False, backupEnabled=False, backupCount=3)
    # Shared Reset returns the manifest's default empty directory.
    (case/'config/profiles/profile-default').mkdir(parents=True)
    expected = dict(initial=initial, discarded=initial, edited=edited, **{'reset-staged': edited}, reset=reset, following=following)
    for name, value in [('input.json', dict(plugin='shell-profiles')), ('expectations.json', expected), ('directories.json', dirs),
                        ('config/settings.json', dict(settingsVersion=62)), ('config/plugins.json', dict(version=6, states={}, sources=[])),
                        ('config/settings/plugins/shell-profiles.json', shared), ('config/settings/bar.json', bar)]:
        runner.write_json(case/name, value)
    env = dict(PHA_PROFILES_SCOPE=scope, PHA_PROFILES_CASE=str(case), PHA_PROFILES_OUTPUT=str(out),
               PHA_PROFILES_DISK=str(args.source/'Scripts/dev/fixtures/plugin-settings-query-disk.py'), PHA_PROFILES_RED='1' if args.old_red else '0')
    for mode, boundary in [('edit', ''), ('cold', 'edited'), ('reset', ''), ('cold', 'reset'), ('follow', ''), ('cold', 'following')]:
        output = out/(mode+('-'+boundary if boundary else '')); output.mkdir(); before = hashes(case)
        try:
            text = runner.run_fixture(profile, install, case, output, args.source/'Scripts/dev/fixtures/plugin-settings-profiles-native.qml',
                extra_env=dict(env, PHA_PROFILES_MODE=mode, PHA_PROFILES_BOUNDARY=boundary),
                extra_lint=tuple(sorted(dest.rglob('*.qml'))), timeout=100)
        except RuntimeError:
            wanted = 'original listing consumes saved selected directory' if args.old_red else wanted
            if not wanted or not (output/'runtime.log').is_file() or wanted not in (output/'runtime.log').read_text() or (output/'runtime.exit').read_text().strip() != '2':
                raise
            if not (out/'persisted/edited.json').is_file():
                raise RuntimeError('profiles red preceded actual native publication')
            result = dict(status='PASS', originalRed=args.old_red, control=args.control, rejectedAt=wanted, completePlanAcceptance=False)
            stage_receipt(out/'result.json', result); runner.remove_completed_installs(case, out); return result
        if 'PROFILES_NATIVE: PASS '+scope+' '+mode not in text or any(v in text for v in ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected', 'PROFILES_ASSERT:')):
            raise RuntimeError('profiles consumer/diagnostic failure')
        if mode == 'cold' and hashes(case) != before:
            raise RuntimeError('profiles cold reader published')
        stage_receipt(output/'observed.json', dict(status='PASS', configurationBefore=before, configurationAfter=hashes(case)))
    if args.old_red or wanted:
        raise RuntimeError('profiles original red escaped')
    for boundary, value in expected.items():
        if json.loads((out/'persisted'/(boundary+'.json')).read_text()) != dict(status='PASS', values=value):
            raise RuntimeError('independent profiles documents: '+boundary)
    result = dict(status='PASS', scope=scope, independentBoundaries=sorted(expected), coldReaders=['edited', 'reset', 'following'], physicalProof=False, completePlanAcceptance=False)
    stage_receipt(out/'result.json', result); runner.remove_completed_installs(case, out); return result


@receipt_run
def main():
    parser = argparse.ArgumentParser(description=__doc__); profile_argument(parser)
    for name in ('source', 'plugins', 'work-root', 'output'):
        parser.add_argument('--'+name, type=Path, required=True)
    parser.add_argument('--scope', choices=('instance', 'shared')); parser.add_argument('--old-red', action='store_true')
    parser.add_argument('--control',choices=('listing','child'))
    args = parser.parse_args(); profile = activate_profile(args.guest_profile); profile.prepare_roots()
    if Path(__file__).resolve() != args.source.resolve()/'Scripts/dev/plugin-settings-profiles-regression.py':
        parser.error('execute supplied source')
    if args.old_red and args.scope != 'instance':
        parser.error('explicit instance red required')
    if args.control and args.scope != 'instance': parser.error('explicit instance control required')
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent):
            parser.error('fresh owned guest roots required')
    with (profile.work_base/'.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB); args.work_root.mkdir(); args.output.mkdir()
        inputs = [Path(__file__), args.source/'Scripts/dev/fixtures/plugin-settings-profiles-native.qml', args.source/'Scripts/dev/fixtures/plugin-settings-query-disk.py']
        runner.write_json(args.output/'inputs.json', dict(source=str(args.source), plugins=str(args.plugins), files={str(p.relative_to(args.source)): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs},
            pluginFiles={str(p.relative_to(args.plugins)): hashlib.sha256(p.read_bytes()).hexdigest() for p in (args.plugins/'shell-profiles').rglob('*') if p.is_file()}))
        rows = [run(args, profile, scope) for scope in ((args.scope,) if args.scope else ('instance', 'shared'))]
        stage_receipt(args.output/'result.json', dict(status='PASS', cases=rows, completePlanAcceptance=False))


if __name__ == '__main__':
    main()
