#!/usr/bin/env python3
"""Native originating description/hide writer, real failure/Retry and retirement."""
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
spec=importlib.util.spec_from_file_location('kbd_action_runner',Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner=importlib.util.module_from_spec(spec); spec.loader.exec_module(runner)

@receipt_run
def run(args,profile,scope):
    case,out=args.work_root/scope,args.output/scope; case.mkdir(); out.mkdir()
    install=case/'install'; shutil.copytree(args.source,install,ignore=shutil.ignore_patterns('.git','.envrc','__pycache__'))
    compositor=install/'Services/Compositor/CompositorService.qml'
    compositor.write_text('pragma Singleton\nimport QtQuick\nQtObject { readonly property bool isNiri: false; readonly property bool isHyprland: true; readonly property bool isMango: false; readonly property bool isSway: false; readonly property bool isLabwc: false }\n')
    for part in ('config/settings/plugins','cache','state','bin','hypr'): (case/part).mkdir(parents=True)
    dest=case/'config/plugins/keybind-cheatsheet'; shutil.copytree(args.plugins/'keybind-cheatsheet',dest)
    if args.control:
        path=dest/'Main.qml'; text=path.read_text(); old='const context = api?.settingsContext;'; assert text.count(old)==1
        text=text.replace(old,'api = pluginApi;\n    '+old); path.write_text(text)
        runner.write_json(out/'mutation.json',dict(file=str(path),old=old,sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
    endpoint=args.source/'Scripts/dev/fixtures/plugin-settings-keybind-endpoint.py'; shutil.copy2(endpoint,case/'bin/hyprctl'); (case/'bin/hyprctl').chmod(0o755)
    (case/'endpoints.jsonl').touch(); source=case/'hypr/main.lua'; source.write_text('-- 1. Lua\ndescription = "lua bind"\n')
    shared=dict(hyprlandLuaConfigPath=str(source),hyprlandParserMode='lua',bindOverrides={},opaque={'keep':'shared'},cheatsheetData=[],detectedCompositor='')
    bar=dict(widgets=dict(left=[dict(id='plugin:keybind-cheatsheet',tag='selected',instanceSettings={'opaque':{'keep':'selected'}}),dict(id='plugin:keybind-cheatsheet',tag='sibling',instanceSettings=dict(bindOverrides={},opaque={'keep':'sibling'}))]))
    # An explicit empty atomic map equals base and is normalized only when edited;
    # the sibling starts with its own described synthetic map to keep scope distinct.
    bar['widgets']['left'][1]['instanceSettings']['bindOverrides']={'synthetic':{'desc':'sibling'},'|32|b|000|exec:fixture':{'hidden':False,'desc':''}}
    initial=dict(shared=shared,bar=bar); expected={}; current=deepcopy(initial)
    bind='|32|b|000|exec:fixture'
    for name,overrides in [('initial',{}),('described',{bind:{'desc':'Selected description'}}),('failed',{bind:{'desc':'Selected description'}}),('retried',{bind:{'desc':'Retry description'}}),('cleared',{}),('hidden',{bind:{'hidden':True}})]:
        leaf=current['shared'] if scope=='shared' else current['bar']['widgets']['left'][0]['instanceSettings']
        if overrides or scope=='shared': leaf['bindOverrides']=overrides
        else: leaf.pop('bindOverrides',None)
        expected[name]=deepcopy(current)
    current['bar']['widgets']['left']=current['bar']['widgets']['left'][1:]; expected['retired']=deepcopy(current)
    for name,value in [('input.json',dict(scope=scope)),('expectations.json',expected),('config/settings.json',dict(settingsVersion=62)),('config/plugins.json',dict(version=6,states={},sources=[])),('config/settings/plugins/keybind-cheatsheet.json',shared),('config/settings/bar.json',bar)]: runner.write_json(case/name,value)
    fixture=args.source/'Scripts/dev/fixtures/plugin-settings-keybind-actions.qml'; disk=args.source/'Scripts/dev/fixtures/plugin-settings-keybind-action-disk.py'
    env=dict(PATH=str(case/'bin')+':'+os.environ['PATH'],KBD_ENDPOINT_CASE=str(case),KBD_ACTION_CASE=str(case),KBD_ACTION_SCOPE=scope,KBD_ACTION_DISK=str(disk),KBD_ACTION_OUTPUT=str(out))
    runner.write_json(out/'inputs.json',dict(source=str(args.source),plugins=str(args.plugins),files={str(path):hashlib.sha256(path.read_bytes()).hexdigest() for path in [Path(__file__),fixture,disk,endpoint,*sorted(dest.glob('*.qml')),dest/'MangoParser.js']},compositorCollaborator=str(compositor),physicalProof=False))
    warm=out/'warm'; warm.mkdir()
    try:
        text=runner.run_fixture(profile,install,case,warm,fixture,extra_env=dict(env,KBD_ACTION_MODE='warm'),extra_lint=tuple(sorted(dest.glob('*.qml'))),timeout=120)
    except RuntimeError:
        if not args.control or 'runtime writer publishes through originating native API' not in (warm/'runtime.log').read_text() or (warm/'runtime.exit').read_text().strip()!='2': raise
        actual=dict(shared=json.loads((case/'config/settings/plugins/keybind-cheatsheet.json').read_text()),bar=json.loads((case/'config/settings/bar.json').read_text()))
        if actual==expected['described'] or actual['shared'].get('bindOverrides',{}).get(bind,{}).get('desc')!='Selected description': raise RuntimeError('wrong-writer control lacks independent wrong-owner publication')
        runner.write_json(out/'wrong-owner.json',actual)
        stage_receipt(out/'result.json',dict(status='PASS',control='writer',rejected=True,completePlanAcceptance=False)); runner.remove_completed_installs(case,out); return
    finally:
        (case/('config/settings/plugins' if scope=='shared' else 'config/settings')).chmod(0o700)
    if args.control: raise RuntimeError('wrong writer control escaped')
    if 'KEYBIND_ACTIONS: PASS' not in text or any(s in text for s in ('TypeError:','ReferenceError:','SyntaxError:','Binding loop detected','KEYBIND_ACTION_ASSERT:')): raise RuntimeError('native action endpoint failure')
    paths=[case/'config/settings/bar.json',case/'config/settings/plugins/keybind-cheatsheet.json']
    before={str(path):hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}
    checks=text.count('KEYBIND_ACTION_CHECK:')
    for mode in ['cold','retire']:
        leg=out/mode; leg.mkdir()
        text=runner.run_fixture(profile,install,case,leg,fixture,extra_env=dict(env,KBD_ACTION_MODE=mode),extra_lint=tuple(sorted(dest.glob('*.qml'))),timeout=120)
        if 'KEYBIND_ACTIONS: PASS' not in text or any(s in text for s in ('TypeError:','ReferenceError:','SyntaxError:','Binding loop detected','KEYBIND_ACTION_ASSERT:')): raise RuntimeError('native '+mode+' endpoint failure')
        if mode=='cold' and before!={str(path):hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}: raise RuntimeError('cold action consumer published')
        checks+=text.count('KEYBIND_ACTION_CHECK:')
    if not set(expected).issubset(p.stem for p in out.glob('*.json')): raise RuntimeError('missing independent documents')
    stage_receipt(out/'result.json',dict(status='PASS',scope=scope,boundaries=list(expected),checks=checks,coldReaders=1,completePlanAcceptance=False))
    runner.remove_completed_installs(case,out)

@receipt_run
def main():
    p=argparse.ArgumentParser(description=__doc__); profile_argument(p)
    for name in ('source','plugins','work-root','output'): p.add_argument('--'+name,type=Path,required=True)
    p.add_argument('--scope',choices=('instance','shared')); p.add_argument('--control',action='store_true')
    args=p.parse_args(); profile=activate_profile(args.guest_profile); profile.prepare_roots()
    if Path(__file__).resolve()!=args.source/'Scripts/dev/plugin-settings-keybind-actions-regression.py': p.error('execute supplied source')
    if args.control and args.scope!='instance': p.error('explicit instance control')
    for path,parent in ((args.work_root,profile.work_base),(args.output,profile.journal_base)):
        if path!=path.resolve() or path==parent or not path.is_relative_to(parent): p.error('fresh owned roots required')
    with (profile.work_base/'.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB); args.work_root.mkdir(); args.output.mkdir()
        for scope in ([args.scope] if args.scope else ['instance','shared']): run(args,profile,scope)
        stage_receipt(args.output/'result.json',dict(status='PASS',completePlanAcceptance=False))
if __name__=='__main__': main()
