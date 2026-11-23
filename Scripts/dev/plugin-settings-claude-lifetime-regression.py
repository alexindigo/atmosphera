#!/usr/bin/env python3
"""Actual ACP generations, manual permissions and originating native writers."""
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

spec=importlib.util.spec_from_file_location('claude_runner',Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner=importlib.util.module_from_spec(spec);spec.loader.exec_module(runner)
MODES=('prompt','queued','handshake','replace','native-retired','destroyed','permission-allow','permission-deny','permission-retired','permission-new-session','cache','slash','start-failure','notification-session','stop')


@receipt_run
def run(args,profile,mode):
    case,out=args.work_root/mode,args.output/mode;case.mkdir();out.mkdir()
    install=case/'install';shutil.copytree(args.source,install,copy_function=os.link,ignore=shutil.ignore_patterns('.git','.envrc','__pycache__'))
    for part in ('config/settings/plugins','cache/plugins/claude-code-panel','state','bin','home','shared','selected','sibling','replacement'):(case/part).mkdir(parents=True)
    dest=case/'config/plugins/claude-code-panel';shutil.copytree(args.plugins/'claude-code-panel',dest)
    wanted=None
    if args.control:
        name,old,new,wanted={
            'origin':('Main.qml','var policy = _consumer(context)?.capture();','var policy = _consumer(undefined)?.capture();','selected ACP prefix/cwd reaches common conversation'),
            'retirement':('Main.qml','if (acpProcess?.policy.context === client.settingsContext) {','if (false) {','request generation settled after source/owner/action change'),
            'permission':('Main.qml','pending.worker !== acpProcess || !_acpCurrent(pending.worker) || pending.sessionId !== sessionId','false','stale permission refused'),
            'history':('Main.qml','_saveHistoryLength = client.maxHistoryLength;','_saveHistoryLength = settingsConsumer.maxHistoryLength;','debounced history keeps captured originating limit'),
            'writer':('Main.qml','originApi = originApi === undefined ? pluginApi : originApi;','originApi = pluginApi;','complete native originating writer documents'),
        }[args.control]
        path=dest/name;text=path.read_text();assert old in text;path.write_text(text.replace(old,new))
    endpoint=case/'bin/claude-code-acp'
    endpoint.write_text('''#!/usr/bin/env python3
import json,os,sys,time
from pathlib import Path
c=Path(os.environ['PHA_CLAUDE_CASE']);mode=os.environ['PHA_CLAUDE_LIFE_MODE'];sid='inert-'+str(os.getpid());pending=None
def record(event):
 with (c/'requests.jsonl').open('a') as f:f.write(json.dumps(dict(pid=os.getpid(),start=Path('/proc/self/stat').read_text().split(') ',1)[1].split()[19],cwd=os.getcwd(),event=event))+'\\n')
def send(value):print(json.dumps(dict(jsonrpc='2.0',**value)),flush=True)
def reply(identifier,text):
 send(dict(method='session/update',params=dict(sessionId=sid,update=dict(sessionUpdate='agent_message_chunk',content=dict(type='text',text=text)))))
 send(dict(id=identifier,result=dict(stopReason='end_turn')))
record(dict(start=True))
for line in sys.stdin:
 m=json.loads(line);record(m);method=m.get('method')
 if method=='initialize':
  if mode=='handshake' and os.getcwd()==str(c/'selected'):
   while not (c/'release').exists():time.sleep(.02)
  send(dict(id=m['id'],result=dict(protocolVersion=1)))
 elif method=='session/new':send(dict(id=m['id'],result=dict(sessionId=sid)))
 elif method=='session/prompt':
  if mode.startswith('permission'):
   pending=m['id'];send(dict(id=900,method='session/request_permission',params=dict(sessionId=sid,toolCall=dict(toolCallId='held-tool',toolName='Bash',input=dict(command='inert-only')),options=[dict(kind='allow_once',optionId='manual-yes'),dict(kind='reject_once',optionId='manual-no')])))
  elif mode in ('replace','native-retired','destroyed','stop'):
   send(dict(method='session/update',params=dict(sessionId=sid,update=dict(sessionUpdate='agent_message_chunk',content=dict(type='text',text='partial')))))
   while True:time.sleep(.02)
  else:
   if mode=='queued' and os.getcwd()==str(c/'selected'):
    send(dict(method='session/update',params=dict(sessionId=sid,update=dict(sessionUpdate='agent_message_chunk',content=dict(type='text',text='queued-partial')))))
    while not (c/'release').exists():time.sleep(.02)
   if mode=='notification-session':send(dict(method='session/update',params=dict(sessionId='foreign-session',update=dict(sessionUpdate='agent_message_chunk',content=dict(type='text',text='FOREIGN')))))
   reply(m['id'],'reply:'+os.getcwd())
 elif m.get('id')==900 and 'result' in m:reply(pending,'permission-settled')
''')
    endpoint.chmod(0o755)
    if mode=='start-failure':
        # Discovery succeeds at the existing fixed name; exec fails after capture.
        which=case/'bin/which';which.write_text('#!/usr/bin/env python3\nimport os\nprint(os.environ["PHA_CLAUDE_CASE"]+"/bin/missing-acp")\n');which.chmod(0o755)
    claude=dict(workingDir=str(case/'shared'),appendSystemPrompt='shared prefix',injectNoctaliaContext=False,permissionMode='default')
    selected=dict(claude=dict(claude,workingDir=str(case/'selected'),appendSystemPrompt='selected prefix',permissionMode='plan'),maxHistoryLength=1)
    sibling=dict(claude=dict(claude,workingDir=str(case/'sibling'),appendSystemPrompt='sibling prefix'))
    shared=dict(claude=claude,maxHistoryLength=200,opaque=dict(keep='shared'))
    bar=dict(widgets=dict(left=[dict(id='plugin:claude-code-panel',tag='selected',instanceSettings=selected),dict(id='plugin:claude-code-panel',tag='sibling',instanceSettings=sibling)]))
    docs={'settings.json':dict(settingsVersion=62),'plugins.json':dict(version=6,states={},sources=[]),'settings/plugins/claude-code-panel.json':shared,'settings/bar.json':bar}
    for name,value in docs.items():runner.write_json(case/'config'/name,value)
    shutil.copy2(args.source/'Assets/ColorScheme/MacOS/MacOS.json',case/'config/colors.json')
    expected=deepcopy(docs)
    if mode in ('replace','handshake','permission-retired'):expected['settings/bar.json']['widgets']['left'][0]['instanceSettings']['claude']['workingDir']=str(case/'replacement')
    if mode=='native-retired':expected['settings/bar.json']['widgets']['left']=expected['settings/bar.json']['widgets']['left'][1:]
    if mode=='cache':expected['settings/bar.json']['widgets']['left'][0]['instanceSettings']['maxHistoryLength']=9
    if mode=='slash':expected['settings/bar.json']['widgets']['left'][0]['instanceSettings']['claude']['workingDir']=str(case/'replacement')
    runner.write_json(case/'expected.json',expected)
    env=dict(PATH=str(case/'bin')+os.pathsep+os.environ['PATH'],HOME=str(case/'home'),PHA_CLAUDE_CASE=str(case),PHA_CLAUDE_OUTPUT=str(out),PHA_CLAUDE_LIFE_MODE=mode,
             PHA_CLAUDE_PROBE=str(args.source/'Scripts/dev/fixtures/plugin-settings-claude-probe.py'))
    try:
        text=runner.run_fixture(profile,install,case,out,args.source/'Scripts/dev/fixtures/plugin-settings-claude-lifetime.qml',extra_env=env,extra_lint=tuple(sorted(dest.glob('*.qml'))),timeout=100)
    except RuntimeError:
        if not wanted or not (out/'runtime.log').is_file() or wanted not in (out/'runtime.log').read_text() or (out/'runtime.exit').read_text().strip()!='2':raise
        result=dict(status='PASS',control=args.control,rejectedAt=wanted,completePlanAcceptance=False)
        stage_receipt(out/'result.json',result);runner.remove_completed_installs(case,out);return
    if wanted:raise RuntimeError('Claude lifetime control escaped '+args.control)
    assert 'CLAUDE_LIFETIME: PASS '+mode in text and not any(s in text for s in ('TypeError:','ReferenceError:','SyntaxError:','Binding loop detected')),text[-3000:]
    assert {name:json.loads((case/'config'/name).read_text()) for name in docs}==expected,'complete native documents'
    joined=json.loads((out/'joined.json').read_text());assert joined['status']=='PASS' and joined['excludedPid']==0
    rows=[json.loads(line) for line in (case/'requests.jsonl').read_text().splitlines()] if (case/'requests.jsonl').exists() else []
    prompts=[r for r in rows if r['event'].get('method')=='session/prompt']
    if mode in ('prompt','queued','notification-session'):
        assert prompts[0]['cwd']==str(case/'selected') and prompts[0]['event']['params']['prompt'][0]['text']=='<system>\nselected prefix\n</system>\n\nrequest-one'
        if mode=='queued':assert len(prompts)==2 and prompts[1]['cwd']==str(case/'sibling') and 'sibling prefix' in prompts[1]['event']['params']['prompt'][0]['text']
    permission=[r for r in rows if r['event'].get('id')==900 and 'result' in r['event']]
    if mode in ('permission-allow','permission-deny'):assert len(permission)==1 and permission[0]['event']['result']['outcome']['optionId']==('manual-yes' if mode.endswith('allow') else 'manual-no')
    elif mode.startswith('permission'):assert not permission,'retired permission cannot reach any successor'
    if mode=='cache':assert json.loads((case/'cache/plugins/claude-code-panel/state.json').read_text())['messages']==[dict(role='user',text='last')]
    result=dict(status='PASS',mode=mode,requests=rows,documents=expected,beforeEngineExitJoin=True,completePlanAcceptance=False)
    stage_receipt(out/'result.json',result);runner.remove_completed_installs(case,out)


@receipt_run
def main():
    parser=argparse.ArgumentParser(description=__doc__);profile_argument(parser)
    for name in ('source','plugins','work-root','output'):parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--mode',choices=MODES);parser.add_argument('--control',choices=('origin','retirement','permission','history','writer'))
    args=parser.parse_args();profile=activate_profile(args.guest_profile);profile.prepare_roots()
    if Path(__file__).resolve()!=args.source.resolve()/'Scripts/dev/plugin-settings-claude-lifetime-regression.py':parser.error('execute supplied source')
    if args.control and args.mode!={'origin':'prompt','retirement':'replace','permission':'permission-new-session','history':'cache','writer':'slash'}[args.control]:parser.error('explicit matching mode for control')
    for path,parent in ((args.work_root,profile.work_base),(args.output,profile.journal_base)):
        if path!=path.resolve() or path==parent or not path.is_relative_to(parent):parser.error('fresh owned guest roots')
    with (profile.work_base/'.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB);args.work_root.mkdir();args.output.mkdir()
        files=[Path(__file__),args.source/'Scripts/dev/fixtures/plugin-settings-claude-lifetime.qml',args.source/'Scripts/dev/fixtures/plugin-settings-claude-probe.py']
        runner.write_json(args.output/'inputs.json',dict(source=str(args.source),plugins=str(args.plugins),files={str(p.relative_to(args.source)):hashlib.sha256(p.read_bytes()).hexdigest() for p in files},pluginFiles={str(p.relative_to(args.plugins)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (args.plugins/'claude-code-panel').rglob('*') if p.is_file()}))
        for mode in ((args.mode,) if args.mode else MODES):run(args,profile,mode)
        stage_receipt(args.output/'result.json',dict(status='PASS',modes=[args.mode] if args.mode else MODES,completePlanAcceptance=False))


if __name__=='__main__':main()
