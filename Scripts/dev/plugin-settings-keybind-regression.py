#!/usr/bin/env python3
"""Keybind real native controls, selected parser and complete cold documents."""
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

spec = importlib.util.spec_from_file_location('keybind_runner', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(spec); spec.loader.exec_module(runner)

def hashes(case):
    return {str(p.relative_to(case)): hashlib.sha256(p.read_bytes()).hexdigest() for p in (case/'config').rglob('*.json')}

@receipt_run
def run(args, profile, scope):
    case, out = args.work_root/scope, args.output/scope
    case.mkdir(); out.mkdir(); (out/'persisted').mkdir(); install = case/'install'
    shutil.copytree(args.source, install, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
    for part in ('config/settings/plugins', 'cache', 'state'): (case/part).mkdir(parents=True)
    dest = case/'config/plugins/keybind-cheatsheet'; shutil.copytree(args.plugins/'keybind-cheatsheet', dest)
    controls = {
        'reader': ('Panel.qml', 'pluginApi?.mainInstance?.clientFor(pluginApi)', 'pluginApi?.mainInstance?.settingsConsumer', 'selected entries share exact parser'),
        'child': ('Panel.qml', 'text: bindRow.itemData.desc', 'text: "wrong"', 'actual rendered selected bind Text'),
        'reset': ('Settings.qml', 'onResetRequested: pluginApi.resetFields(["keyColorSuper", "keyTextSuper"])', 'onResetRequested: pluginApi.field("keyColorSuper").set("#123456")', 'actual row Reset removes selected overrides'),
    }
    if args.control:
        name, old, new, _ = controls[args.control]; path = dest/name; text = path.read_text(); assert text.count(old) == 1
        path.write_text(text.replace(old,new)); runner.write_json(out/'mutation.json',dict(file=name,old=old,new=new,sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
    for name, key in (('base', 'B'), ('selected', 'S'), ('sibling', 'O'), ('following', 'F')):
        (case/(name+'.kdl')).write_text('binds {\n    Mod+'+key+' hotkey-overlay-title="'+name+' bind" { spawn "inert"; }\n}\n')
    home=case/'home'; (home/'.config/niri').mkdir(parents=True)
    (home/'.config/niri/config.kdl').write_text('binds {\n    Mod+R hotkey-overlay-title="reference bind" { spawn "inert"; }\n}\n')
    fields = json.loads((dest/'manifest.json').read_text())['metadata']['settingsSchema']['fields']
    edits = dict(windowWidth=1200,windowHeight=600,autoHeight=False,columnCount=2,modKeyVariable='$meta',hyprlandConfigPath=str(case/'selected.conf'),hyprlandLuaConfigPath=str(case/'selected.lua'),hyprlandParserMode='conf',niriConfigPath=str(case/'selected.kdl'),mangoConfigPath=str(case/'mango.conf'),mergeSequentialBinds=False,showUndescribedBinds=False,splitLargeWorkspaceCategory=False,workspaceSplitThreshold=4,bindOverrides={'synthetic':dict(desc='',hidden=False)})
    for key in fields:
        if key.startswith(('keyColor','keyText')) or key == 'descriptionTextColor': edits[key] = '#112233' if key.startswith('keyColor') else '#ddeeff'
        if key.startswith('keyLabelMod'): edits[key] = 'Meta'+key[-1]
    # keyLabelColor is declared/hidden in the source page, not an invented control.
    keys = list(edits)
    following = {key: ('#334455' if key.startswith(('keyColor','keyText')) or key=='descriptionTextColor' else value) for key,value in edits.items()}
    following.update(niriConfigPath=str(case/'following.kdl'),columnCount=4,windowWidth=1300,windowHeight=700)
    shared = dict(niriConfigPath=str(case/'base.kdl'),columnCount=3,bindOverrides={'synthetic':dict(desc='keep description',hidden=True)},keyLabelColor='#abcdef',cheatsheetData=[dict(title='legacy',binds=[dict(keys='L',desc='legacy unqualified')])],detectedCompositor='mango',opaque={'keep':'shared'})
    bar = dict(widgets=dict(left=[dict(id='plugin:keybind-cheatsheet',tag='selected',instanceSettings={'opaque':{'keep':'selected'}}),dict(id='plugin:keybind-cheatsheet',tag='sibling',instanceSettings=dict(niriConfigPath=str(case/'sibling.kdl'),columnCount=1,opaque={'keep':'sibling'})),dict(id='plugin:keybind-cheatsheet',tag='inherited',instanceSettings={'opaque':{'keep':'inherited'}})]))
    initial = dict(shared=shared,bar=bar); edited = deepcopy(initial)
    (edited['shared'] if scope=='shared' else edited['bar']['widgets']['left'][0]['instanceSettings']).update(edits)
    reset = deepcopy(edited)
    for key in keys: (reset['shared'] if scope=='shared' else reset['bar']['widgets']['left'][0]['instanceSettings']).pop(key)
    following_doc = deepcopy(reset); following_doc['shared'].update(following)
    expected = dict(initial=initial,discarded=initial,edited=edited,**{'reset-staged':edited},reset=reset,following=following_doc)
    for name,value in [('input.json',dict(plugin='keybind-cheatsheet',keys=keys,edits=edits,following=following)),('expectations.json',expected),('config/settings.json',dict(settingsVersion=62)),('config/plugins.json',dict(version=6,states={},sources=[])),('config/settings/plugins/keybind-cheatsheet.json',shared),('config/settings/bar.json',bar)]: runner.write_json(case/name,value)
    fixture = args.source/'Scripts/dev/fixtures/plugin-settings-keybind-native.qml'
    env = dict(HOME=str(home),PHA_KEYBIND_SCOPE=scope,PHA_KEYBIND_CASE=str(case),PHA_KEYBIND_OUTPUT=str(out),PHA_KEYBIND_DISK=str(args.source/'Scripts/dev/fixtures/plugin-settings-query-disk.py'),PHA_KEYBIND_RED='1' if args.old_red else '0')
    wanted = 'original parser consumes saved selected source' if args.old_red else controls[args.control][3] if args.control else None
    modes = [('edit',''),('reset','')] if args.control=='reset' else [('edit','')] if wanted else [('edit',''),('cold','edited'),('reset',''),('cold','reset'),('follow',''),('cold','following')]
    for mode,boundary in modes:
        output=out/(mode+('-'+boundary if boundary else '')); output.mkdir(); before=hashes(case)
        try:
            text = runner.run_fixture(profile,install,case,output,fixture,extra_env=dict(env,PHA_KEYBIND_MODE=mode,PHA_KEYBIND_BOUNDARY=boundary),extra_lint=tuple(sorted(dest.glob('*.qml'))),timeout=100)
        except RuntimeError:
            if not wanted or wanted not in (output/'runtime.log').read_text() or (output/'runtime.exit').read_text().strip()!='2' or not (out/'persisted/edited.json').is_file(): raise
            result=dict(status='PASS',originalRed=args.old_red,control=args.control,rejectedAt=wanted,completePlanAcceptance=False)
            stage_receipt(out/'result.json',result); runner.remove_completed_installs(case,out); return result
        if 'KEYBIND_NATIVE: PASS '+scope+' '+mode not in text or any(v in text for v in ('TypeError:','ReferenceError:','SyntaxError:','KEYBIND_ASSERT:','Binding loop detected')): raise RuntimeError('keybind endpoint failure')
        if mode=='cold' and hashes(case)!=before: raise RuntimeError('cold reader published')
        stage_receipt(output/'observed.json',dict(status='PASS',configurationBefore=before,configurationAfter=hashes(case)))
    if wanted: raise RuntimeError('negative control escaped')
    for name,value in expected.items():
        if json.loads((out/'persisted'/(name+'.json')).read_text()) != dict(status='PASS',values=value): raise RuntimeError('independent boundary: '+name)
    result=dict(status='PASS',scope=scope,fields=keys,hidden=['keyLabelColor'],independentBoundaries=sorted(expected),coldReaders=['edited','reset','following'],physicalProof=False,completePlanAcceptance=False)
    stage_receipt(out/'result.json',result); runner.remove_completed_installs(case,out); return result

@receipt_run
def main():
    p=argparse.ArgumentParser(description=__doc__); profile_argument(p)
    for name in ('source','plugins','work-root','output'): p.add_argument('--'+name,type=Path,required=True)
    p.add_argument('--scope',choices=('instance','shared')); p.add_argument('--old-red',action='store_true'); p.add_argument('--control',choices=('reader','child','reset'))
    args=p.parse_args(); profile=activate_profile(args.guest_profile); profile.prepare_roots()
    if Path(__file__).resolve()!=args.source.resolve()/'Scripts/dev/plugin-settings-keybind-regression.py': p.error('execute supplied source')
    if (args.old_red or args.control) and args.scope!='instance': p.error('explicit instance control required')
    for path,parent in ((args.work_root,profile.work_base),(args.output,profile.journal_base)):
        if path!=path.resolve() or path==parent or not path.is_relative_to(parent): p.error('fresh owned guest roots required')
    with (profile.work_base/'.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB); args.work_root.mkdir(); args.output.mkdir()
        fixture=args.source/'Scripts/dev/fixtures/plugin-settings-keybind-native.qml'
        paths=[Path(__file__),fixture,args.source/'.qmllint.ini',args.source/'Scripts/dev/fixtures/plugin-settings-query-disk.py']
        runner.write_json(args.output/'inputs.json',dict(source=str(args.source),plugins=str(args.plugins),files={str(path.relative_to(args.source)):hashlib.sha256(path.read_bytes()).hexdigest() for path in paths},pluginFiles={str(path.relative_to(args.plugins)):hashlib.sha256(path.read_bytes()).hexdigest() for path in (args.plugins/'keybind-cheatsheet').rglob('*') if path.is_file()}))
        rows=[run(args,profile,scope) for scope in ((args.scope,) if args.scope else ('instance','shared'))]
        stage_receipt(args.output/'result.json',dict(status='PASS',cases=rows,completePlanAcceptance=False))
if __name__=='__main__': main()
