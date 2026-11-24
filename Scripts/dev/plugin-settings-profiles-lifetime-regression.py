#!/usr/bin/env python3
"""Real disposable profile IO, originating native marker and held action inputs."""
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
spec = importlib.util.spec_from_file_location('profiles_life_runner', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(spec); spec.loader.exec_module(runner)
SH = '''#!/usr/bin/env python3
import json,os,sys,time
from pathlib import Path
case=Path(os.environ['PHA_PROFILES_CASE'])
stage=Path(sys.argv[1]).name if len(sys.argv)>1 else ''
row=dict(pid=os.getpid(),start=Path('/proc/self/stat').read_text().split(') ',1)[1].split()[19],argv=sys.argv[1:],stage=stage)
with (case/'requests.jsonl').open('a') as out: out.write(json.dumps(row)+'\\n')
gate=case/'hold'
while gate.exists() and gate.read_text().strip()==stage: time.sleep(.01)
os.execv('/usr/bin/sh',['sh']+sys.argv[1:])
'''


@receipt_run
def run(args, profile, mode):
    case, out = args.work_root/mode, args.output/mode
    case.mkdir(); out.mkdir()
    install = case/'install'; shutil.copytree(args.source, install, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
    for part in ('config/settings/plugins', 'cache', 'state', 'bin', 'selected/_backups', 'later', 'shared', 'sibling'):
        (case/part).mkdir(parents=True)
    dest = case/'config/plugins/shell-profiles'; shutil.copytree(args.plugins/'shell-profiles', dest)
    wanted = None
    if args.control:
        name, old, new, wanted = {
            'writer': ('Main.qml', 'var api = request.api;', 'var api = pluginApi;', 'originating native marker, never shared writer'),
            'count': ('Main.qml', 'String(request.backupCount)', 'String(request.api.pluginSettings.backupCount)', 'held backup count retains captured policy'),
            'feedback': ('Main.qml', 'if (!_current(request)) return;', 'if (!request) return;', 'retired origin cannot receive late feedback'),
            'retirement': ('ProfileSettingsClient.qml', 'retire(root);', '/* retained wrong client */', 'retired listing leaves exact Main map'),
        }[args.control]
        path = dest/name; text = path.read_text(); assert text.count(old) == 1, args.control
        path.write_text(text.replace(old, new))
    for name in ('01-old', '02-old', '03-old'):
        (case/'selected/_backups'/name).mkdir()
    shared = dict(profilesDir=str(case/'shared'), icon='bookmark', iconColor='primary', includeWallpapers=True,
                  backupEnabled=True, backupCount=5, lastAppliedProfile='previous', opaque=dict(keep='shared'))
    selected = dict(profilesDir=str(case/'selected'), includeWallpapers=False, backupEnabled=True, backupCount=2, opaque=dict(keep='selected'))
    bar = dict(position='bottom', widgets=dict(left=[dict(id='plugin:shell-profiles', tag='selected', instanceSettings=selected),
        dict(id='plugin:shell-profiles', tag='sibling', instanceSettings=dict(profilesDir=str(case/'sibling'), opaque=dict(keep='sibling')))]))
    for name, value in [('config/settings.json', dict(settingsVersion=62)), ('config/plugins.json', dict(version=6, states={}, sources=[])),
                        ('config/settings/plugins/shell-profiles.json', shared), ('config/settings/bar.json', bar)]:
        runner.write_json(case/name, value)
    roles = ['mPrimary','mOnPrimary','mSecondary','mOnSecondary','mTertiary','mOnTertiary','mStandout','mOnStandout','mError','mOnError','mSurface','mOnSurface','mSurfaceVariant','mOnSurfaceVariant','mOutline','mShadow','mHover','mOnHover']
    runner.write_json(case/'config/colors.json', {key:'#123456' for key in roles})
    (case/'config/settings/unknown.json').write_bytes(b'{"opaque":18446744073709551615}\n')
    (case/'requests.jsonl').write_text('')
    script = case/'bin/sh'; script.write_text(SH); script.chmod(0o755)
    if mode == 'start-failure': script.write_text('#!/missing-profile-test-interpreter\n')
    env = dict(PHA_PROFILES_CASE=str(case), PHA_PROFILES_LIFE_MODE=mode, PATH=str(case/'bin')+':'+os.environ['PATH'])
    output = out/'life'; output.mkdir()
    fixture = install/'plugin-settings-profiles-lifetime.qml'
    fixture.write_bytes((args.source/'Scripts/dev/fixtures/plugin-settings-profiles-lifetime.qml').read_bytes().replace(
        b'../../../Services/Plugins/PluginSettingsRead.js', b'./Services/Plugins/PluginSettingsRead.js'))
    try:
        text = runner.run_fixture(profile, install, case, output, fixture, installed=True,
            extra_env=env, extra_lint=tuple(sorted(dest.glob('*.qml'))), timeout=100)
    except RuntimeError:
        if args.start_failure_red: wanted = 'failed-start settles one action and clears busy'
        if not wanted or wanted not in (output/'runtime.log').read_text() or (output/'runtime.exit').read_text().strip() != '2': raise
        stage_receipt(out/'result.json', dict(status='PASS',control=args.control,originalStartFailure=args.start_failure_red,rejectedAt=wanted,completePlanAcceptance=False))
        runner.remove_completed_installs(case,out); return
    assert 'PROFILES_LIFETIME: PASS '+mode in text and not any(key in text for key in ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected', 'PROFILES_LIFE_ASSERT:')), text[-5000:]
    actual = dict(shared=json.loads((case/'config/settings/plugins/shell-profiles.json').read_text()), bar=json.loads((case/'config/settings/bar.json').read_text()))
    expected = dict(shared=shared, bar=deepcopy(bar))
    if mode == 'native':
        expected['bar']['widgets']['left'][0]['instanceSettings']['lastAppliedProfile'] = ''
        assert not (case/'selected/renamed').exists()
    elif mode == 'native-retired':
        expected['bar']['widgets']['left'] = expected['bar']['widgets']['left'][1:]
        assert (case/'selected/saved/_config-files.json').is_file()
    elif mode == 'start-failure':
        assert not (case/'selected/saved').exists()
    else:
        assert (case/'selected/saved/_config-files.json').is_file()
        assert not list((case/'later').iterdir())
        if mode == 'destroyed':
            expected['bar']['position'] = 'top'
        if mode == 'held':
            # Count and directory are from action admission, not the later fake runtime inputs.
            count = len([p for p in (case/'selected/_backups').iterdir() if p.is_dir()])
            if args.control == 'count' and count != 2:
                stage_receipt(out/'result.json', dict(status='PASS',control=args.control,rejectedAt=wanted,observedBackupCount=count,completePlanAcceptance=False))
                runner.remove_completed_installs(case,out); return
            assert count == 2, 'held backup count retains captured policy'
    assert actual == expected, (actual, expected)
    assert (case/'config/settings/unknown.json').read_bytes() == b'{"opaque":18446744073709551615}\n'
    assert (case/'config/settings.json').read_bytes() == b'{\n  "settingsVersion": 62\n}\n'
    if mode == 'native':
        assert len([p for p in (case/'selected/_backups').iterdir() if p.is_dir()]) == 2
    rows = [json.loads(line) for line in (case/'requests.jsonl').read_text().splitlines()]
    for row in rows:
        proc = Path('/proc')/str(row['pid'])/'stat'
        assert not proc.exists() or proc.read_text().split(') ',1)[1].split()[19] != row['start'], ('profile endpoint survived', row)
    stage_receipt(out/'result.json', dict(status='PASS', mode=mode, completeDocuments=actual,
        endpointRows=rows, rawHelperFiles={str(p.relative_to(case)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (case/'selected').rglob('*.json')},
        physicalShellMutation=False, completePlanAcceptance=False))
    if wanted or args.start_failure_red: raise RuntimeError('profile lifetime control escaped')
    runner.remove_completed_installs(case, out)


@receipt_run
def main():
    parser = argparse.ArgumentParser(description=__doc__); profile_argument(parser)
    for name in ('source','plugins','work-root','output'):
        parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--mode',choices=('native','native-retired','held','retired','pre-retired','destroyed','start-failure'),required=True)
    parser.add_argument('--start-failure-red',action='store_true')
    parser.add_argument('--control',choices=('writer','count','feedback','retirement'))
    args=parser.parse_args(); profile=activate_profile(args.guest_profile); profile.prepare_roots()
    if args.control and args.mode != dict(writer='native',count='held',feedback='retired',retirement='retired')[args.control]: parser.error('explicit matching control mode required')
    if args.start_failure_red and args.mode != 'start-failure': parser.error('failed-start mode required')
    if Path(__file__).resolve()!=args.source.resolve()/'Scripts/dev/plugin-settings-profiles-lifetime-regression.py': parser.error('execute supplied source')
    for path,parent in ((args.work_root,profile.work_base),(args.output,profile.journal_base)):
        if path!=path.resolve() or path==parent or not path.is_relative_to(parent): parser.error('fresh owned roots required')
    with (profile.work_base/'.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB); args.work_root.mkdir(); args.output.mkdir()
        inputs=[Path(__file__),args.source/'Scripts/dev/fixtures/plugin-settings-profiles-lifetime.qml']
        runner.write_json(args.output/'inputs.json',dict(source=str(args.source),plugins=str(args.plugins),files={str(p.relative_to(args.source)):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs},pluginFiles={str(p.relative_to(args.plugins)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (args.plugins/'shell-profiles').rglob('*') if p.is_file()}))
        run(args,profile,args.mode); stage_receipt(args.output/'result.json',dict(status='PASS',completePlanAcceptance=False))


if __name__=='__main__': main()
