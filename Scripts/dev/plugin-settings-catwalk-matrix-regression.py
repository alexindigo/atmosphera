#!/usr/bin/env python3
"""Both-scope Catwalk sparse/reset/inheritance/failure/stale/native-lifetime matrix."""
import argparse
from copy import deepcopy
import fcntl
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
from guest_profile import activate_profile,profile_argument
spec=importlib.util.spec_from_file_location('cat_matrix_runner',Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner=importlib.util.module_from_spec(spec);spec.loader.exec_module(runner)
def run(args,profile,scope):
    case,out=args.work_root/scope,args.output/scope;case.mkdir();out.mkdir();(out/'persisted').mkdir()
    install=case/'install';shutil.copytree(args.source,install,ignore=shutil.ignore_patterns('.git','.envrc','__pycache__'))
    for part in ['config/settings/plugins','cache','state']:(case/part).mkdir(parents=True)
    dest=case/'config/plugins/catwalk';shutil.copytree(args.plugins/'catwalk',dest)
    controls={
        'bar':('BarWidget.qml','settingsConsumerFor(pluginApi.settingsContext)','settingsConsumerFor(pluginApi.mainInstance.pluginApi.settingsContext)','exact context client shared by native Bar/Desktop'),
        'desktop':('DesktopWidget.qml','settingsConsumerFor(pluginApi.settingsContext)','settingsConsumerFor(pluginApi.mainInstance.pluginApi.settingsContext)','exact context client shared by native Bar/Desktop'),
        'child':('DesktopWidget.qml','source: root.currentIconSource','source: Qt.resolvedUrl("icons/my-idle-0-symbolic.svg")','actual selected desktop Image source')}
    if args.control:
        name,old,new,_=controls[args.control];path=dest/name;text=path.read_text();assert text.count(old)==1;path.write_text(text.replace(old,new))
        runner.write_json(out/'mutation.json',dict(file=name,old=old,new=new,sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
    shared=dict(minimumThreshold=12,hideBackground=False,opaque={'keep':'shared'})
    bar=dict(widgets=dict(left=[dict(id='plugin:catwalk',tag='selected',instanceSettings={'opaque':{'keep':'selected'}}),dict(id='plugin:catwalk',tag='sibling',instanceSettings=dict(minimumThreshold=22,hideBackground=True,opaque={'keep':'sibling'})),dict(id='plugin:catwalk',tag='inherited',instanceSettings={'opaque':{'keep':'inherited'}})]))
    current=dict(shared=shared,bar=bar);expected={'initial':deepcopy(current)}
    (current['shared'] if scope=='shared' else current['bar']['widgets']['left'][0]['instanceSettings']).update(minimumThreshold=18,hideBackground=True);expected['edited']=deepcopy(current)
    current['shared'].update(minimumThreshold=8,hideBackground=False);expected['base']=deepcopy(current)
    leaf=current['shared'] if scope=='shared' else current['bar']['widgets']['left'][0]['instanceSettings']
    for key in ['minimumThreshold','hideBackground']:leaf.pop(key,None)
    expected['reset']=deepcopy(current)
    current['shared'].update(minimumThreshold=19,hideBackground=True);expected['following']=deepcopy(current)
    current['shared'].update(minimumThreshold=11,hideBackground=False);expected['stale']=deepcopy(current)
    current['bar']['widgets']['left']=current['bar']['widgets']['left'][1:];expected['retired']=deepcopy(current)
    for name,value in [('input.json',dict(plugin='catwalk',scope=scope)),('expectations.json',expected),('config/settings.json',dict(settingsVersion=62)),('config/plugins.json',dict(version=6,states={},sources=[])),('config/settings/plugins/catwalk.json',expected['initial']['shared']),('config/settings/bar.json',expected['initial']['bar'])]:runner.write_json(case/name,value)
    fixture=args.source/'Scripts/dev/fixtures/plugin-settings-catwalk-matrix.qml';disk=args.source/'Scripts/dev/fixtures/plugin-settings-query-disk.py'
    env=dict(CAT_MATRIX_CASE=str(case),CAT_MATRIX_SCOPE=scope,CAT_MATRIX_OUTPUT=str(out),CAT_MATRIX_DISK=str(disk))
    runner.write_json(out/'inputs.json',dict(source=str(args.source),plugins=str(args.plugins),files={str(path):hashlib.sha256(path.read_bytes()).hexdigest() for path in [Path(__file__),fixture,disk,*sorted(dest.glob('*.qml'))]},physicalProof=False))
    checks=0
    for mode in ['warm','cold','retire']:
        leg=out/mode;leg.mkdir();before={str(path):hashlib.sha256(path.read_bytes()).hexdigest() for path in (case/'config').rglob('*.json')}
        try:
            text=runner.run_fixture(profile,install,case,leg,fixture,extra_env=dict(env,CAT_MATRIX_LEG=mode),extra_lint=tuple(dest.glob('*.qml')),timeout=180)
        except RuntimeError:
            marker=controls[args.control][3] if args.control else None
            if not marker or marker not in (leg/'runtime.log').read_text() or (leg/'runtime.exit').read_text().strip()!='2':raise
            actual=dict(shared=json.loads((case/'config/settings/plugins/catwalk.json').read_text()),bar=json.loads((case/'config/settings/bar.json').read_text()))
            if actual!=expected['initial']:raise RuntimeError('rejecting consumer changed native configuration')
            runner.write_json(out/'result.json',dict(status='PASS',control=args.control,rejectedAt=marker,independentInitialDocuments=actual,completePlanAcceptance=False));runner.remove_completed_installs(case,out);return
        finally:(case/('config/settings/plugins' if scope=='shared' else 'config/settings')).chmod(0o700)
        if args.control:raise RuntimeError('Catwalk matrix control escaped')
        if 'CATWALK_MATRIX: PASS '+scope+' '+mode not in text or any(s in text for s in ['TypeError:','ReferenceError:','SyntaxError:','Binding loop detected','CAT_MATRIX_ASSERT:']):raise RuntimeError('matrix runtime failure')
        after={str(path):hashlib.sha256(path.read_bytes()).hexdigest() for path in (case/'config').rglob('*.json')}
        if mode=='cold' and before!=after:raise RuntimeError('cold runtime reader published')
        runner.write_json(leg/'observed.json',dict(status='PASS',configurationBefore=before,configurationAfter=after))
        checks+=text.count('CAT_MATRIX_CHECK:')
    for name,value in expected.items():
        if json.loads((out/'persisted'/(name+'.json')).read_text())!=dict(status='PASS',values=value):raise RuntimeError('independent complete document boundary '+name)
    runner.write_json(out/'result.json',dict(status='PASS',scope=scope,independentDocuments=list(expected),checks=checks,coldReaders=1,completePlanAcceptance=False))
    runner.remove_completed_installs(case,out)
def main():
    p=argparse.ArgumentParser(description=__doc__);profile_argument(p)
    for name in ['source','plugins','work-root','output']:p.add_argument('--'+name,type=Path,required=True)
    p.add_argument('--scope',choices=['instance','shared']);p.add_argument('--control',choices=['bar','desktop','child']);args=p.parse_args();profile=activate_profile(args.guest_profile);profile.prepare_roots()
    if args.control and args.scope!='instance':p.error('explicit instance control required')
    if Path(__file__).resolve()!=args.source/'Scripts/dev/plugin-settings-catwalk-matrix-regression.py':p.error('execute supplied source')
    for path,parent in [(args.work_root,profile.work_base),(args.output,profile.journal_base)]:
        if path!=path.resolve() or path==parent or not path.is_relative_to(parent):p.error('fresh named guest roots required')
    with (profile.work_base/'.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB);args.work_root.mkdir();args.output.mkdir()
        for scope in ([args.scope] if args.scope else ['instance','shared']):run(args,profile,scope)
        runner.write_json(args.output/'result.json',dict(status='PASS',completePlanAcceptance=False))
if __name__=='__main__':main()
