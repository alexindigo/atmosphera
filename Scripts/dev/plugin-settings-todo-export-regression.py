#!/usr/bin/env python3
"""Native Todo export policy, actual Panel action and independent output bytes."""
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
import time

from guest_profile import activate_profile, profile_argument
spec = importlib.util.spec_from_file_location('todo_export_runner', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(spec); spec.loader.exec_module(runner)
STUB = '''#!/usr/bin/env python3
import json,os,sys,time
from pathlib import Path
case=Path(os.environ['PHA_TODO_EXPORT_CASE'])
if len(sys.argv)>2 and 'todo_' in sys.argv[2]:
 row=dict(pid=os.getpid(),start=Path('/proc/self/stat').read_text().split(') ',1)[1].split()[19],argv=sys.argv[1:])
 with (case/'requests.jsonl').open('a') as out: out.write(json.dumps(row)+'\\n')
 if 'export-held/' in sys.argv[2]:
  while (case/'hold').exists(): time.sleep(.01)
os.execv('/usr/bin/sh',['sh']+sys.argv[1:])
'''

def hashes(case): return {str(p.relative_to(case)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((case/'config').rglob('*.json'))}
@receipt_run
def run(args, profile, scope):
    case,out=args.work_root/scope,args.output/scope
    case.mkdir(); out.mkdir(); (out/'persisted').mkdir()
    install=case/'install'; shutil.copytree(args.source,install,ignore=shutil.ignore_patterns('.git','.envrc','__pycache__'))
    for part in ('config/settings/plugins','cache','state','home/Documents','bin','export-shared','export-selected','export-edited','export-following','export-held','export-later'): (case/part).mkdir(parents=True)
    dest=case/'config/plugins/todo'; shutil.copytree(args.plugins/'todo',dest)
    tasks=[dict(id=1,text='shared active task',completed=False,createdAt='2026-11-21',pageId=0,priority='high',details='shared details'),dict(id=2,text='shared completed task',completed=True,createdAt='2026-11-21',pageId=0,priority='low',details='')]
    pages=[dict(id=0,name='General'),dict(id=7,name='Empty page')]
    shared=dict(todos=tasks,pages=pages,current_page_id=0,count=2,completedCount=1,showCompleted=True,isExpanded=False,useCustomColors=False,exportPath=str(case/'export-shared'),exportFormat='markdown',exportEmptySections=False,opaque=dict(keep='shared'))
    legacy=dict(todos=[dict(id=91,text='legacy task',completed=False,createdAt='2026-11-21',pageId=0,priority='medium',details=''),dict(id=92,text='legacy completed task',completed=True,createdAt='2026-11-21',pageId=0,priority='low',details='')],pages=[dict(id=0,name='Legacy')],current_page_id=0,count=2,completedCount=1,opaque=dict(keep='selected'),exportPath=str(case/'export-selected'))
    bar=dict(widgets=dict(left=[dict(id='plugin:todo',tag='selected',instanceSettings=legacy),dict(id='plugin:todo',tag='sibling',instanceSettings=dict(exportFormat='markdown',opaque=dict(keep='sibling'))),dict(id='plugin:todo',tag='inherited',instanceSettings=dict(opaque=dict(keep='inherited')))]))
    initial=dict(shared=shared,bar=bar); edited=deepcopy(initial)
    (edited['shared'] if scope=='shared' else edited['bar']['widgets']['left'][0]['instanceSettings']).update(exportFormat='json',exportPath=str(case/'export-edited'),exportEmptySections=True,showCompleted=False)
    reset=deepcopy(edited)
    for key in ('exportFormat','exportPath','exportEmptySections','showCompleted'): (reset['shared'] if scope=='shared' else reset['bar']['widgets']['left'][0]['instanceSettings']).pop(key)
    following=deepcopy(reset); following['shared'].update(exportFormat='json',exportPath=str(case/'export-following'))
    expected=dict(initial=initial,discarded=initial,edited=edited,**{'reset-staged':edited},reset=reset,following=following)
    for name,value in [('input.json',dict(plugin='todo')),('expectations.json',expected),('config/settings.json',dict(settingsVersion=62)),('config/plugins.json',dict(version=6,states={},sources=[])),('config/settings/plugins/todo.json',shared),('config/settings/bar.json',bar)]: runner.write_json(case/name,value)
    wanted='original Panel export uses saved selected policy' if args.old_red else ('failed-start settles request exactly once' if args.start_failure_red else None)
    if args.control:
        name,old,new,wanted={
            'origin':('Panel.qml','mainInstance.doExportTodos(pluginApi.settingsContext);','mainInstance.doExportTodos();','Panel export uses selected path and format'),
            'feedback':('Main.qml','if (!request || !request.context.current())','if (!request)','retired origin cannot acknowledge export feedback'),
            'busy':('Main.qml','if (exportBusy) {','if (false) {','busy refusal preserves admitted request'),
            'empty':('Main.qml','var showEmptySections = request.exportEmptySections;','var showEmptySections = false;','held Markdown output retains admitted empty policy'),
            'display':('Panel.qml','id: todoTextDisplay\n                        visible: !delegateItem.editing\n                        text: modelData.text','id: todoTextDisplay\n                        visible: !delegateItem.editing\n                        text: "wrong rendered task"','actual Panel task Text uses selected filtered content')
        }[args.control]
        path=dest/name; text=path.read_text()
        if text.count(old)!=1: raise RuntimeError('stale Todo control: '+args.control)
        path.write_text(text.replace(old,new))
    env=dict(PHA_TODO_EXPORT_SCOPE=scope,PHA_TODO_EXPORT_CASE=str(case),PHA_TODO_EXPORT_OUTPUT=str(out),PHA_TODO_EXPORT_DISK=str(args.source/'Scripts/dev/fixtures/plugin-settings-query-disk.py'),PHA_TODO_EXPORT_RED='1' if args.old_red else '0',HOME=str(case/'home'))
    if args.lifetime:
        (case/'requests.jsonl').write_text(''); (case/'hold').touch()
        stub=case/'bin/sh'; stub.write_text(STUB); stub.chmod(0o755)
        env['PATH']=str(case/'bin')+':'+os.environ['PATH']
    exports=[]
    for mode,boundary in ([('life','')] if args.lifetime else [('edit',''),('cold','edited'),('reset',''),('cold','reset'),('follow',''),('cold','following')]):
        output=out/(mode+('-'+boundary if boundary else '')); output.mkdir(); before=hashes(case)
        try:
            fixture=args.source/('Scripts/dev/fixtures/plugin-settings-todo-export-lifetime.qml' if args.lifetime else 'Scripts/dev/fixtures/plugin-settings-todo-export-native.qml')
            text=runner.run_fixture(profile,install,case,output,fixture,extra_env=dict(env,PHA_TODO_EXPORT_MODE=mode,PHA_TODO_EXPORT_BOUNDARY=boundary),extra_lint=tuple(sorted(dest.glob('*.qml'))),timeout=100)
        except RuntimeError:
            if not wanted or not (output/'runtime.log').is_file() or wanted not in (output/'runtime.log').read_text() or (output/'runtime.exit').read_text().strip()!='2': raise
            if args.old_red and not (out/'persisted/edited.json').is_file(): raise RuntimeError('Todo original red preceded independent native publication')
            result=dict(status='PASS',originalRed=args.old_red,rejectedAt=wanted,completePlanAcceptance=False)
            stage_receipt(out/'result.json',result); runner.remove_completed_installs(case,out); return result
        marker='TODO_EXPORT_LIFETIME: PASS' if args.lifetime else 'TODO_EXPORT_NATIVE: PASS '+scope+' '+mode
        if marker not in text or any(k in text for k in ('TypeError:','ReferenceError:','SyntaxError:','Binding loop detected','TODO_EXPORT_ASSERT:','TODO_EXPORT_LIFE_ASSERT:')): raise RuntimeError('Todo export consumer/diagnostic failure')
        if args.lifetime:
            paths=list((case/'export-held').glob('*.md'))
            if len(paths)!=1: raise RuntimeError('held export not published to captured directory')
            value=paths[0].read_text()
            if 'Empty page' not in value:
                if args.control=='empty':
                    result=dict(status='PASS',originalRed=False,rejectedAt=wanted,completePlanAcceptance=False)
                    stage_receipt(out/'result.json',result); runner.remove_completed_installs(case,out); return result
                raise RuntimeError('held Markdown output retains admitted empty policy')
            if not all(task['text'] in value for task in tasks) or list((case/'export-later').iterdir()): raise RuntimeError('held export reread replacement content/policy')
            if hashes(case)!=before: raise RuntimeError('explicit-context export changed stored content/configuration')
            rows=[json.loads(line) for line in (case/'requests.jsonl').read_text().splitlines()]
            for row in rows:
                proc=Path('/proc')/str(row['pid'])/'stat'
                if proc.exists() and proc.read_text().split(') ',1)[1].split()[19]==row['start']: raise RuntimeError('export endpoint survived engine')
            result=dict(status='PASS',lifetime=True,endpointRows=rows,configurationBefore=before,configurationAfter=hashes(case),heldOutputSha256=hashlib.sha256(paths[0].read_bytes()).hexdigest(),completePlanAcceptance=False)
            if wanted: raise RuntimeError('Todo lifetime control escaped')
            stage_receipt(out/'result.json',result); runner.remove_completed_installs(case,out); return result
        if mode=='cold' and hashes(case)!=before: raise RuntimeError('Todo cold reader published configuration')
        stage_receipt(output/'observed.json',dict(status='PASS',configurationBefore=before,configurationAfter=hashes(case)))
        rows=[json.loads(line.split('TODO_EXPORT_OUTPUT ',1)[1]) for line in text.splitlines() if 'TODO_EXPORT_OUTPUT ' in line]
        if len(rows)!=1: raise RuntimeError('missing actual Panel export output')
        row=rows[0]; path=Path(row['path'])
        if not path.is_relative_to(case): raise RuntimeError('export escaped disposable workspace')
        payload=path.read_bytes()
        if row['format']=='json':
            if json.loads(payload)!=tasks: raise RuntimeError('export did not retain the common task owner')
        else:
            value=payload.decode()
            if not all(task['text'] in value for task in tasks) or 'legacy task' in value or ('Empty page' in value)!=row['empty']: raise RuntimeError('selected Markdown content/empty policy mismatch')
        row.update(sha256=hashlib.sha256(payload).hexdigest(),bytes=len(payload)); exports.append(row)
        shutil.copy2(path,output/path.name)
    if wanted: raise RuntimeError('Todo original control escaped')
    for boundary,value in expected.items():
        if json.loads((out/('persisted/'+boundary+'.json')).read_text())!=dict(status='PASS',values=value): raise RuntimeError('Todo independent document mismatch: '+boundary)
    result=dict(status='PASS',scope=scope,exports=exports,independentBoundaries=sorted(expected),coldReaders=['edited','reset','following'],physicalProof=False,completePlanAcceptance=False)
    stage_receipt(out/'result.json',result); runner.remove_completed_installs(case,out)
    print('TODO_EXPORT_NATIVE '+scope+': PASS',flush=True); return result

@receipt_run
def main():
    parser=argparse.ArgumentParser(description=__doc__); profile_argument(parser)
    for key in ('source','plugins','work-root','output'): parser.add_argument('--'+key,type=Path,required=True)
    parser.add_argument('--scope',choices=('instance','shared'))
    oracle = parser.add_mutually_exclusive_group()
    oracle.add_argument('--old-red',action='store_true')
    oracle.add_argument('--control',choices=('origin','feedback','busy','empty','display'))
    oracle.add_argument('--start-failure-red',action='store_true')
    parser.add_argument('--lifetime',action='store_true')
    args=parser.parse_args()
    if args.old_red and args.lifetime: parser.error('original red requires the policy witness, not --lifetime')
    profile=activate_profile(args.guest_profile); profile.prepare_roots()
    if Path(__file__).resolve()!=args.source.resolve()/'Scripts/dev/plugin-settings-todo-export-regression.py': parser.error('execute supplied source')
    if args.old_red and args.scope!='instance': parser.error('explicit instance original control required')
    if args.start_failure_red and not args.lifetime: parser.error('failed-start red requires lifetime mode')
    if args.control and (args.scope!='instance' or (args.control not in ('origin','display') and not args.lifetime)): parser.error('explicit matching control mode required')
    for path,parent in ((args.work_root,profile.work_base),(args.output,profile.journal_base)):
        if path!=path.resolve() or path==parent or not path.is_relative_to(parent): parser.error('fresh owned profile roots required')
    with (profile.work_base/'.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB); args.work_root.mkdir(); args.output.mkdir()
        paths=[Path(__file__),args.source/'Scripts/dev/fixtures/plugin-settings-todo-export-native.qml',args.source/'Scripts/dev/fixtures/plugin-settings-todo-export-lifetime.qml',args.source/'Scripts/dev/fixtures/plugin-settings-query-disk.py']
        runner.write_json(args.output/'inputs.json',dict(source=str(args.source),plugins=str(args.plugins),files={str(f.relative_to(args.source)):hashlib.sha256(f.read_bytes()).hexdigest() for f in paths},pluginFiles={str(f.relative_to(args.plugins)):hashlib.sha256(f.read_bytes()).hexdigest() for f in (args.plugins/'todo').rglob('*') if f.is_file()}))
        rows=[run(args,profile,scope) for scope in ((args.scope,) if args.scope else ('instance','shared'))]
        stage_receipt(args.output/'result.json',dict(status='PASS',cases=rows,completePlanAcceptance=False))
if __name__=='__main__': main()
