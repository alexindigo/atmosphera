#!/usr/bin/env python3
"""Existing Air/Contributions/Arch clients, both native scopes and held generations."""
import argparse
from copy import deepcopy
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import time
from guest_profile import activate_profile, profile_argument
spec=importlib.util.spec_from_file_location('worker_matrix_runner',Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner=importlib.util.module_from_spec(spec);spec.loader.exec_module(runner)
MEMBERS=('air-quality','github-contributions','arch-updater')
ENDPOINT='''#!/usr/bin/python3
import fcntl,json,os,sys,time
from pathlib import Path
from urllib.parse import urlparse,parse_qs
from datetime import date,timedelta
case=Path(os.environ['WORKER_MATRIX_CASE']);name=Path(sys.argv[0]).name;args=sys.argv[1:]
with (case/'requests.jsonl').open('a') as log:
 fcntl.flock(log,fcntl.LOCK_EX);log.write(json.dumps(dict(pid=os.getpid(),start=Path('/proc/self/stat').read_text().split()[21],name=name,argv=args))+'\\n');log.flush()
if name=='curl':
 urls=[value for value in args if value.startswith('https://')];assert len(urls)==1;url=urlparse(urls[0])
 if url.netloc=='air-quality-api.open-meteo.com':source=parse_qs(url.query)['latitude'][0];assert source in ['1','3']
 elif url.netloc=='github.com':source=url.path.split('/')[2];assert source in ['synthetic-alpha','synthetic-beta']
 elif url.netloc=='api.waqi.info':source='aqicn';assert parse_qs(url.query)['token'][0] in ['synthetic','invalid']
 elif url.netloc=='api.github.com':source='graphql';assert url.path=='/graphql';assert json.loads(args[args.index('-d')+1])['variables']['login']=='synthetic-beta'
 else:raise SystemExit('unreviewed network endpoint')
elif name=='flatpak':
 if args==['update','--no-deploy','--noninteractive']:pass
 elif args==['remote-ls','--updates','--columns=application,name,version']:print('app.id\\tflatpak-pkg\\t2')
 elif args==['list','--columns=application,version']:print('app.id\\t1')
 else:raise SystemExit('unreviewed Flatpak operation')
 raise SystemExit(0)
elif name=='checkupdates':
 assert args==[];source='alpha'
else:
 assert name=='matrix-check' and args in [['alpha'],['beta'],['empty'],['aur']];source=args[0]
hold=case/'hold'
if (hold/'hold').exists() and source in ['1','synthetic-alpha','alpha']:
 (hold/'entered').write_text('entered\\n');deadline=time.monotonic()+30
 while not (hold/'release').exists():
  if time.monotonic()>deadline:raise SystemExit('held endpoint deadline')
  time.sleep(.02)
if name!='curl':
 if source!='empty':print(source+'-pkg 1 -> 2')
elif url.netloc=='air-quality-api.open-meteo.com':print(json.dumps(dict(current=dict(us_aqi=17 if source=='1' else 151,european_aqi=9 if source=='1' else 81,pm2_5=4))))
elif source=='aqicn':
 print(json.dumps(dict(status='ok',data=dict(aqi=63,city=dict(name='Controlled station'),iaqi=dict(pm25=dict(v=4))))) if parse_qs(url.query)['token'][0]=='synthetic' else json.dumps(dict(status='error',data='invalid synthetic token')))
elif source=='graphql':
 assert 'Authorization: Bearer synthetic' in args or 'Authorization: Bearer invalid' in args
 days=[dict(date=(date(2026,11,18)-timedelta(days=364-i)).isoformat(),contributionCount=1,contributionLevel='SECOND_QUARTILE') for i in range(365)]
 print(json.dumps(dict(data=dict(user=dict(contributionsCollection=dict(contributionCalendar=dict(totalContributions=31,weeks=[dict(contributionDays=days)])))))) if 'Authorization: Bearer synthetic' in args else json.dumps(dict(errors=[dict(message='invalid synthetic token')])))
else:
 count=7 if source=='synthetic-alpha' else 29;print(str(count)+' contributions in the last year')
 for i in range(365):
  day=(date(2026,11,18)-timedelta(days=364-i)).isoformat();print('<td data-date="'+day+'" id="day-'+str(i)+'" data-level="2"></td>');print('<tool-tip for="day-'+str(i)+'">'+str(count)+' contributions</tool-tip>')
'''
def hashes(case):return {str(p.relative_to(case)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (case/'config').rglob('*.json')}
def run(a,profile,plugin,scope):
    name=plugin+'-'+scope;case,out=a.work_root/name,a.output/name;case.mkdir();out.mkdir();(out/'persisted').mkdir()
    install=case/'install';shutil.copytree(a.source,install,ignore=shutil.ignore_patterns('.git','.envrc','__pycache__'))
    for part in ['config/settings/plugins','cache','state','bin','hold']:(case/part).mkdir(parents=True)
    dest=case/'config/plugins'/plugin;shutil.copytree(a.plugins/plugin,dest)
    command=str(case/'bin/matrix-check')
    if plugin=='air-quality':
        field,base,edit,sibling,lifetime,label='customLatitude','1','3','3','','settings.customLatitude'
        shared=dict(dataSource='open-meteo',customLatitude=base,customLongitude='2',useNoctaliaLocation=False,refreshInterval=60,aqiScale='us')
    elif plugin=='github-contributions':
        field,base,edit,sibling,lifetime,label='username','synthetic-alpha','synthetic-beta','synthetic-beta','','settings.username.label'
        shared=dict(username=base,token='',weeksShown=10,refreshInterval=60,layout='graph')
    else:
        field,base,edit,sibling,lifetime,label='systemCmd',command+' alpha',command+' beta',command+' beta',command+' beta','settings.general.systemCmd.text'
        shared=dict(systemCmd=base,aurCmd=command+' empty',flatpak=False,noctalia=False,toast=False,refreshInterval=120,boldVer=False,desktopTip=False,refreshTimer=False)
    shared['opaque']={'keep':'shared'}
    bar=dict(widgets=dict(left=[dict(id='plugin:'+plugin,tag='selected',instanceSettings={'opaque':{'keep':'selected'}}),dict(id='plugin:'+plugin,tag='sibling',instanceSettings={field:sibling,'opaque':{'keep':'sibling'}}),dict(id='plugin:'+plugin,tag='inherited',instanceSettings={'opaque':{'keep':'inherited'}})]))
    current=dict(shared=shared,bar=bar);expected={'initial':deepcopy(current)}
    leaf=current['shared'] if scope=='shared' else current['bar']['widgets']['left'][0]['instanceSettings'];leaf[field]=edit;expected['edited']=deepcopy(current)
    current['shared'][field]=base;expected['base']=deepcopy(current);leaf.pop(field);expected['reset']=deepcopy(current)
    current['shared'][field]=edit;expected['following']=deepcopy(current)
    current['shared'][field]=base;expected['stale']=deepcopy(current)
    current['bar']['widgets']['left'][0]['instanceSettings'][field]=lifetime;expected['replacement']=deepcopy(current)
    current['bar']['widgets']['left']=current['bar']['widgets']['left'][1:];expected['retired']=deepcopy(current)
    edges={
        'air-quality':[dict(name='scale',patch=dict(aqiScale='eu'),hasData=True,value=9),dict(name='provider',patch=dict(dataSource='aqicn',aqicnToken='synthetic',aqiScale='us'),hasData=True,value=63,station='Controlled station'),dict(name='invalid-token',patch=dict(aqicnToken='invalid'),hasData=False),dict(name='missing-token',patch=dict(aqicnToken=''),hasData=False),dict(name='disabled-location',patch=dict(dataSource='open-meteo',useNoctaliaLocation=True),hasData=False)],
        'github-contributions':[dict(name='graphql',patch=dict(username='synthetic-beta',token='synthetic'),hasData=True,value=31,columns=10),dict(name='invalid-token',patch=dict(token='invalid'),hasData=False),dict(name='public-graph',patch=dict(token='',weeksShown=4),hasData=True,value=29,columns=4),dict(name='stats-layout',patch=dict(layout='stats',weeksShown=20),hasData=True,value=29,columns=13),dict(name='cleared-account',patch=dict(username=''),hasData=False)],
        'arch-updater':[dict(name='aur-flatpak',patch=dict(aurCmd=command+' aur',flatpak=True),names=['alpha-pkg','aur-pkg','flatpak-pkg']),dict(name='system-replaced',patch=dict(systemCmd=command+' beta',aurCmd=command+' empty'),names=['beta-pkg','flatpak-pkg']),dict(name='flatpak-disabled',patch=dict(flatpak=False),names=['beta-pkg'])]}[plugin]
    if a.edges:
        expected={'initial':expected['initial']};current=deepcopy(expected['initial'])
        inherited_values=dict(json.loads((dest/'manifest.json').read_text())['metadata']['defaultSettings'],**current['shared'])
        for edge in edges:
            leaf=current['bar']['widgets']['left'][0]['instanceSettings']
            for key,value in edge['patch'].items():
                # Scalar, test-only expected documents for native omit-equal.
                if inherited_values.get(key)==value:leaf.pop(key,None)
                else:leaf[key]=value
            expected[edge['name']]=deepcopy(current)
    for path,value in [('input.json',dict(plugin=plugin,field=field,base=base,edit=edit,lifetime=lifetime,label=label,edges=edges)),('expectations.json',expected),('config/settings.json',dict(settingsVersion=62)),('config/plugins.json',dict(version=6,states={},sources=[])),('config/settings/plugins/'+plugin+'.json',expected['initial']['shared']),('config/settings/bar.json',expected['initial']['bar'])]:runner.write_json(case/path,value)
    (case/'requests.jsonl').write_text('')
    for cmd in ['curl','matrix-check','checkupdates','flatpak']:
        path=case/'bin'/cmd;path.write_text(ENDPOINT);path.chmod(0o755)
    wanted=None
    if a.control:
        path=dest/'DesktopWidget.qml'
        old,new='settingsConsumerFor(pluginApi.settingsContext)','settingsConsumerFor(pluginApi.mainInstance.pluginApi.settingsContext)'
        wanted='Desktop exact selected worker client'
        if a.control=='child':
            anchors={'air-quality':('text: root.hasData ? root.aqi.toString() : "--"','text: "wrong-aqi"','actual Desktop AQI Text'),'github-contributions':('var name = "@" + (mainInstance?.username ?? "");','var name = "wrong-account";','actual Desktop account Text'),'arch-updater':('text: modelData.name','text: "wrong-update"','actual Desktop update row Text')}
            old,new,wanted=anchors[plugin]
        text=path.read_text();assert text.count(old)==1,(plugin,old,text.count(old));path.write_text(text.replace(old,new));runner.write_json(out/'mutation.json',dict(path=str(path.relative_to(dest)),old=old,new=new))
    fixture=a.source/'Scripts/dev/fixtures/plugin-settings-worker-matrix.qml';disk=a.source/'Scripts/dev/fixtures/plugin-settings-query-disk.py'
    env=dict(WORKER_MATRIX_PLUGIN=plugin,WORKER_MATRIX_SCOPE=scope,WORKER_MATRIX_CASE=str(case),WORKER_MATRIX_OUTPUT=str(out),WORKER_MATRIX_DISK=str(disk),PATH=str(case/'bin')+':'+os.environ['PATH'])
    runner.write_json(out/'inputs.json',dict(source=str(a.source),plugins=str(a.plugins),files={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in [Path(__file__),fixture,disk,*sorted(dest.glob('*.qml'))]},physicalProof=False))
    for mode in (['edges'] if a.edges else ['warm','cold','lifetime']):
        leg=out/mode;leg.mkdir();before=hashes(case)
        try:text=runner.run_fixture(profile,install,case,leg,fixture,extra_env=dict(env,WORKER_MATRIX_LEG=mode),extra_lint=tuple(dest.glob('*.qml')),timeout=180)
        except RuntimeError:
            if not wanted or wanted not in (leg/'runtime.log').read_text() or (leg/'runtime.exit').read_text().strip()!='2':raise
            after=hashes(case)
            assert all(after.get(key)==value for key,value in before.items()),'rejecting control changed an existing configuration file'
            assert set(after)-set(before)<={'config/colors.json'},'unreviewed bootstrap configuration addition'
            actual=dict(shared=json.loads((case/('config/settings/plugins/'+plugin+'.json')).read_text()),bar=json.loads((case/'config/settings/bar.json').read_text()))
            assert actual==expected['initial'],'rejecting control changed native settings documents'
            runner.write_json(out/'result.json',dict(status='PASS',control=a.control,rejectedAt=wanted,configurationBefore=before,configurationAfter=after,bootstrapAdditions=sorted(set(after)-set(before)),independentInitialDocuments=actual));runner.remove_completed_installs(case,out);return
        finally:(case/('config/settings/plugins' if scope=='shared' else 'config/settings')).chmod(0o700)
        if wanted:raise RuntimeError('worker matrix control escaped')
        if 'WORKER_MATRIX: PASS '+plugin+' '+scope+' '+mode not in text or any(x in text for x in ['TypeError:','ReferenceError:','SyntaxError:','Binding loop detected','WORKER_MATRIX_ASSERT:']):raise RuntimeError('worker matrix runtime failure')
        after=hashes(case)
        if mode=='cold' and before!=after:raise RuntimeError('cold reader published')
        runner.write_json(leg/'observed.json',dict(status='PASS',configurationBefore=before,configurationAfter=after,checks=text.count('WORKER_MATRIX_CHECK:')))
    for boundary,value in expected.items():
        if a.edges and boundary=='initial':continue
        assert json.loads((out/'persisted'/(boundary+'.json')).read_text())==dict(status='PASS',values=value),boundary
    # Reap/verify every inert endpoint by PID plus start identity, not PID alone.
    rows=[json.loads(line) for line in (case/'requests.jsonl').read_text().splitlines()]
    for _ in range(100):
        live=[r for r in rows if Path('/proc/'+str(r['pid'])+'/stat').exists() and Path('/proc/'+str(r['pid'])+'/stat').read_text().split()[21]==r['start']]
        if not live:break
        time.sleep(.05)
    if live:raise RuntimeError('worker matrix endpoint still alive')
    shutil.copy2(case/'requests.jsonl',out/'requests.jsonl')
    runner.write_json(out/'result.json',dict(status='PASS',plugin=plugin,scope=scope,independentDocuments=[key for key in expected if not a.edges or key!='initial'],coldReaders=0 if a.edges else 1,endpointIdentitiesAbsent=len(rows),physicalProof=False,completePlanAcceptance=False));runner.remove_completed_installs(case,out)
    print('WORKER_MATRIX '+name+': PASS',flush=True)
def main():
    p=argparse.ArgumentParser(description=__doc__);profile_argument(p)
    for name in ['source','plugins','work-root','output']:p.add_argument('--'+name,type=Path,required=True)
    p.add_argument('--plugin',choices=MEMBERS);p.add_argument('--scope',choices=['instance','shared']);p.add_argument('--control',choices=['reader','child']);p.add_argument('--edges',action='store_true');a=p.parse_args();profile=activate_profile(a.guest_profile);profile.prepare_roots()
    if a.edges and (a.control or a.scope!='instance'):p.error('source edges use explicit instance scope, no control')
    if Path(__file__).resolve()!=a.source/'Scripts/dev/plugin-settings-worker-matrix-regression.py':p.error('execute supplied source')
    if a.control and (not a.plugin or a.scope!='instance'):p.error('explicit instance/plugin control')
    for path,parent in [(a.work_root,profile.work_base),(a.output,profile.journal_base)]:
        if path!=path.resolve() or path==parent or not path.is_relative_to(parent):p.error('fresh named guest roots')
    with (profile.work_base/'.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB);a.work_root.mkdir();a.output.mkdir()
        for plugin in ([a.plugin] if a.plugin else MEMBERS):
            for scope in ([a.scope] if a.scope else ['instance','shared']):run(a,profile,plugin,scope)
        runner.write_json(a.output/'result.json',dict(status='PASS',completePlanAcceptance=False))
if __name__=='__main__':main()
