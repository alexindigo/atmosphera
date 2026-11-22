#!/usr/bin/env python3
"""Actual Hermes pages/native documents/cold readers and model HTTP consumers."""
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

spec = importlib.util.spec_from_file_location('hermes_life', Path(__file__).with_name('plugin-settings-hermes-regression.py'))
life = importlib.util.module_from_spec(spec); spec.loader.exec_module(life)
runner = life.runner


def run(args, profile, scope):
    case, out = args.work_root/scope, args.output/scope
    case.mkdir(); out.mkdir(); (out/'persisted').mkdir()
    for name in ('config/settings/plugins', 'cache', 'state', 'home'):
        (case/name).mkdir(parents=True)
    install = case/'install'
    shutil.copytree(args.source, install, copy_function=os.link, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
    product = args.plugins/'hermes-agent'
    shutil.copytree(product, case/'config/plugins/hermes-agent')
    if args.omit_origin:
        path=case/'config/plugins/hermes-agent/Settings.qml';text=path.read_text()
        old='applySettings(root.pluginApi.runtimeContext, trim)';assert text.count(old)==1
        path.write_text(text.replace(old,'applySettings(undefined, trim)'))
    if args.original_page:
        shutil.copy2(args.original_page,case/'config/plugins/hermes-agent/Settings.qml')
    runner.write_json(case/'config/settings.json', dict(settingsVersion=62))
    runner.write_json(case/'config/plugins.json', dict(version=6, states={}, sources=[]))
    # Seed appearance too: a first-run Color owner may create this unrelated
    # file, which is not a publication by a retired Hermes detection request.
    runner.write_json(case/'config/colors.json',dict(mPrimary='#0a84ff',mOnPrimary='#ffffff',mSecondary='#bf5af2',mOnSecondary='#ffffff',mTertiary='#30d158',mOnTertiary='#ffffff',mStandout='#f88349',mOnStandout='#571f00',mError='#ff453a',mOnError='#ffffff',mSurface='#1e1e1e',mOnSurface='#f5f5f7',mSurfaceVariant='#2c2c2e',mOnSurfaceVariant='#98989d',mOutline='#3a3a3c',mShadow='#000000',mHover='#0a84ff',mOnHover='#ffffff'))
    (case/'requests.jsonl').write_text('')
    peer, thread = life.peer(case, 'shared'); port = peer.server_address[1]
    probe_peer, probe_thread = life.peer(case, 'selected') if args.scenario in ('probe','pending') else (None,None)
    if args.scenario=='probe':(case/'hold').write_text('hold');(case/'hold-health').write_text('hold')
    manifest = json.loads((product/'manifest.json').read_text())
    manifest['metadata']['defaultSettings'].update(clientOnlyMode=True, bridgePort=port, defaultModel='default-model')
    runner.write_json(case/'config/plugins/hermes-agent/manifest.json', manifest)
    shared = dict(clientOnlyMode=True, bridgeHost='127.0.0.1', bridgePort=port, bridgeTokenManual='native-token', autoStartBridge=False, autoStartGateway=False, configured=True, statusPollIntervalSec=3600, defaultProvider='fixture', defaultModel='base-model', panelPinned=False, opaque='shared')
    if args.scenario.startswith('detect'):
        shared.update(clientOnlyMode=False,configured=False,stateFile=str(case/'bridge-state/state.json'))
        (case/'bridge-state').mkdir();(case/'bridge-state/bridge.token').write_text('native-token')
        if args.scenario=='detect-retire':
            (case/'hold').write_text('hold');(case/'hold-detect').write_text('hold')
    bar = dict(widgets=dict(left=[dict(id='plugin:hermes-agent', instanceSettings=row) for row in ({'opaque':'selected'}, {'defaultModel':'sibling-model','opaque':'sibling'}, {'opaque':'inherited'})]))
    initial = dict(shared=shared, bar=bar); edited=deepcopy(initial)
    (edited['shared'] if scope=='shared' else edited['bar']['widgets']['left'][0]['instanceSettings'])['defaultModel']='selected-model'
    reset=deepcopy(edited); (reset['shared'] if scope=='shared' else reset['bar']['widgets']['left'][0]['instanceSettings']).pop('defaultModel')
    following=deepcopy(reset); following['shared']['defaultModel']='following-model'
    expected=dict(initial=initial,discarded=initial,edited=edited,**{'reset-staged':edited},reset=reset,following=following)
    pinned=deepcopy(edited)
    (pinned['shared'] if scope=='shared' else pinned['bar']['widgets']['left'][0]['instanceSettings'])['panelPinned']=True
    expected.update({'runtime-pinned':pinned,'runtime-unpinned':edited})
    if args.scenario != 'native':
        detected=deepcopy(initial)
        if args.scenario=='detect':
            detected['shared'].update(configured=True,hermesHome=str(case/'detected-home'),hermesCommand='detected-literal-command',defaultModel='detected-model',defaultProvider='detected-provider')
        expected={'detected':detected}
    if args.scenario=='pending':
        changed=deepcopy(initial)
        (changed['shared'] if scope=='shared' else changed['bar']['widgets']['left'][0]['instanceSettings'])['bridgePort']=probe_peer.server_address[1]
        expected=dict(initial=initial,edited=changed,**{'session-replaced':changed})
    runner.write_json(case/'expectations.json',expected)
    runner.write_json(case/'input.json',dict(plugin='hermes-agent'))
    runner.write_json(case/'config/settings/plugins/hermes-agent.json',shared); runner.write_json(case/'config/settings/bar.json',bar)
    runner.write_json(out/'sources.json',{str(f.relative_to(product)):hashlib.sha256(f.read_bytes()).hexdigest() for f in product.rglob('*') if f.is_file()})
    try:
        modes=[('edit','')] if args.omit_origin or args.original_page else [(args.scenario,'')] if args.scenario!='native' else [('edit',''),('cold','edited'),('reset',''),('cold','reset'),('follow',''),('cold','following')]
        for mode,boundary in modes:
            part=out/(mode+('-'+boundary if boundary else ''));part.mkdir()
            hashes=lambda:{str(f.relative_to(case)):hashlib.sha256(f.read_bytes()).hexdigest() for f in (case/'config').rglob('*.json')}
            before=hashes()
            try:
                text=runner.run_fixture(profile,install,case,part,args.source/'Scripts/dev/fixtures/plugin-settings-hermes-native.qml',extra_env=dict(PHA_HERMES_CASE=str(case),PHA_HERMES_SCOPE=scope,PHA_HERMES_MODE=mode,PHA_HERMES_BOUNDARY=boundary,PHA_HERMES_OUTPUT=str(out),PHA_HERMES_DISK=str(args.source/'Scripts/dev/fixtures/plugin-settings-query-disk.py'),PHA_HERMES_PROBE_PORT=str(probe_peer.server_address[1] if probe_peer else 0),HOME=str(case/'home')),extra_lint=tuple(sorted((case/'config/plugins/hermes-agent').rglob('*.qml'))),timeout=120)
            except RuntimeError:
                if not (args.omit_origin or args.original_page):raise
                text=(part/'runtime.log').read_text()
                assert (part/'runtime.exit').read_text().strip()=='2'
                wanted='instance/edit/consumer: finite phase' if args.omit_origin else 'runtime detected model cannot mask selected field'
                assert 'HERMES_NATIVE_ASSERT:' in text and wanted in text,text
                assert not any(term in text for term in ('TypeError:','ReferenceError:','SyntaxError:')),text
                boundaries=['initial','discarded','edited'] if args.omit_origin else ['initial']
                for name in boundaries:assert json.loads((out/'persisted'/(name+'.json')).read_text())==dict(status='PASS',values=expected[name])
                shutil.copy2(case/'requests.jsonl',out/'requests.jsonl')
                runner.write_json(out/'result.json',dict(status='PASS',kind='omitted-origin-control' if args.omit_origin else 'original-page-red',rejectedAt=wanted,failedEngineRetained=True,documents=boundaries))
                return
            assert not (args.omit_origin or args.original_page),'Hermes negative control escaped'
            assert 'HERMES_NATIVE: PASS '+scope+' '+mode in text
            assert not any(term in text for term in ('TypeError:','ReferenceError:','SyntaxError:','Binding loop detected')),text
            after=hashes();runner.write_json(part/'configuration-hashes.json',dict(before=before,after=after))
            if args.scenario!='native':
                if args.scenario in ('detect-retire','probe'):assert before==after,'retired detection or draft probe published'
                continue
            if mode=='cold':assert before==after,'cold reader published'
            name=boundary or {'edit':'edited','reset':'reset','follow':'following'}[mode]
            values=dict(manifest['metadata']['defaultSettings'],**expected[name]['shared'])
            if scope=='instance':values.update(expected[name]['bar']['widgets']['left'][0]['instanceSettings'])
            observed=json.loads(text.split('HERMES_NATIVE_CONSUMER ')[1].splitlines()[0])
            assert observed['model']==values['defaultModel'] and observed['rendered'] and observed['selectedClientIdentity'],observed
            runner.write_json(part/'consumer.json',dict(status='PASS',expected=values['defaultModel'],observed=observed))
        for boundary,values in expected.items():assert json.loads((out/'persisted'/(boundary+'.json')).read_text())==dict(status='PASS',values=values)
        shutil.copy2(case/'requests.jsonl',out/'requests.jsonl')
        rows=[json.loads(line) for line in (out/'requests.jsonl').read_text().splitlines()]
        assert all(row['token']=='native-token' for row in rows if row['path']=='/model')
        if args.scenario=='native':assert {'selected-model','following-model'} <= {row['body']['model'] for row in rows if row['path']=='/model'}
        elif args.scenario.startswith('detect'):assert len([row for row in rows if row['path']=='/detect'])==1
        elif args.scenario=='probe':assert len([row for row in rows if row['peer']=='selected' and row['path']=='/health'])==2
        else:
            creates=[row for row in rows if row['path']=='/session/create']
            assert len(creates)==1 and creates[0]['peer']=='selected' and creates[0]['token']=='native-token'
        runner.write_json(out/'result.json',dict(status='PASS',scope=scope,scenario=args.scenario,engines=len(modes),documents=list(expected),coldReaders=['edited','reset','following'] if args.scenario=='native' else [],httpRows=len(rows)))
    finally:
        (case/'release').write_text('release')
        peer.done.set();peer.shutdown();peer.server_close();thread.join(timeout=5);assert not thread.is_alive()
        if probe_peer:
            probe_peer.done.set();probe_peer.shutdown();probe_peer.server_close();probe_thread.join(timeout=5);assert not probe_thread.is_alive()
    runner.remove_completed_installs(case,out)


def main():
    parser=argparse.ArgumentParser(description=__doc__);profile_argument(parser)
    for name in ('source','plugins','work-root','output'):parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--scope',choices=('instance','shared'))
    parser.add_argument('--scenario',choices=('native','detect','detect-retire','probe','pending'),default='native')
    parser.add_argument('--omit-origin',action='store_true')
    parser.add_argument('--original-page',type=Path)
    args=parser.parse_args();profile=activate_profile(args.guest_profile);profile.prepare_roots()
    if Path(__file__).resolve()!=args.source.resolve()/'Scripts/dev/plugin-settings-hermes-native-regression.py':parser.error('execute supplied source')
    for path,parent in ((args.work_root,profile.work_base),(args.output,profile.journal_base)):
        if path!=path.resolve() or path==parent or not path.is_relative_to(parent):parser.error('fresh owned guest roots required')
    with (profile.work_base/'.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB);args.work_root.mkdir();args.output.mkdir()
        runner.write_json(args.output/'inputs.json',{str(f.relative_to(args.source)):hashlib.sha256(f.read_bytes()).hexdigest() for f in (Path(__file__),args.source/'Scripts/dev/plugin-settings-hermes-regression.py',args.source/'Scripts/dev/fixtures/plugin-settings-hermes-native.qml',args.source/'Scripts/dev/fixtures/plugin-settings-query-disk.py')})
        for scope in ((args.scope,) if args.scope else ('instance','shared')):run(args,profile,scope)
        runner.write_json(args.output/'result.json',dict(status='PASS',fullMemberAcceptance=False))


if __name__=='__main__':main()
