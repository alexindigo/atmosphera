#!/usr/bin/env python3
"""Actual Steam overlay processes against inert compositor/launch endpoints."""
from fixture_receipts import receipt_run, stage_receipt
import argparse
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil

from guest_profile import activate_profile, profile_argument

spec = importlib.util.spec_from_file_location('steam_runner', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)

ENDPOINT = '''#!/usr/bin/python3
import fcntl,json,os,sys,time
from pathlib import Path
b=Path(os.environ['PHA_STEAM_CASE']); name=Path(sys.argv[0]).name; args=sys.argv[1:]
stage=''
if name=='bash' and len(args)==2 and args[0]=='-c':
 code=args[1]
 if 'clients -j' in code:
  stage='detect' if '.at[0]' in code else 'new' if 'workspace: .workspace.name' in code else 'focus' if 'jq -r' in code else 'detect-all'
 elif code.startswith('hyprctl dispatch '):stage='move' if 'resize' in code else 'show' if ('togglespecialworkspace' in code or 'workspace.toggle_special' in code) else 'new-move' if '0x104' in code and ('movetoworkspacesilent' in code or 'workspace = ' in code) else 'move-all' if ('movetoworkspacesilent' in code or 'workspace = ' in code) else 'focus-exec'
start=(Path('/proc')/str(os.getpid())/'stat').read_text().split(') ',1)[1].split()[19]
with (b/'requests.jsonl').open('a') as f:
 fcntl.flock(f,fcntl.LOCK_EX);f.write(json.dumps(dict(endpoint=name,argv=args,stage=stage,pid=os.getpid(),start=start))+'\\n');f.flush()
if name=='bash':
 if args and args[0]==str(b/'install/Scripts/dev/qmllint.sh'):os.execv('/usr/bin/bash',['bash',*args])
 while stage and (b/('hold-'+stage)).exists() and not (b/('release-'+stage)).exists():time.sleep(.02)
 if len(args)==2 and args[0]=='-c' and args[1].startswith('hyprctl '):os.execv('/usr/bin/bash',['bash',*args])
 raise SystemExit('Unreviewed Steam shell '+repr(args))
if name=='pidof':raise SystemExit(0)
if name=='hyprctl':
 if args==['monitors','-j']:print('[{"width":2000,"height":1000}]')
 elif args==['clients','-j']:
  time.sleep(.25)
  while (b/'hold-clients').exists():time.sleep(.02)
  windows=json.loads((b/'windows.json').read_text())
  if (b/'add-window').exists():windows.append(dict(address='0x104',title='Extra',**{'class':'steam'},fullscreen=0,at=[0,0],size=[900,900],workspace=dict(name='2')))
  for window in windows:
   if (b/('moved-'+window['address'])).exists():window['workspace']['name']='special:steam'
  print(json.dumps(windows))
 elif args==['dispatch','hl.dsp.no_op()']:
  if os.environ.get('PHA_STEAM_LUA')=='1':print('ok')
  else:raise SystemExit(1)
 elif args and args[0]=='dispatch':
  while (b/'hold-dispatch').exists():time.sleep(.02)
  import re
  if 'movetoworkspacesilent' in args or 'workspace = "special:steam"' in str(args):
   match=re.search(r'address:(0x[0-9a-f]+)',str(args))
   if match:(b/('moved-'+match[1])).touch()
 else:raise SystemExit('Unreviewed hyprctl '+repr(args))
elif name!='steam':raise SystemExit('Unreviewed endpoint '+name)
'''


def seed(case, plugins):
    for name in ('config/settings/plugins', 'cache', 'state', 'home', 'bin'):
        (case/name).mkdir(parents=True)
    shutil.copytree(plugins/'hyprland-steam-overlay', case/'config/plugins/hyprland-steam-overlay')
    runner.write_json(case/'config/settings.json', dict(settingsVersion=62))
    runner.write_json(case/'config/plugins.json', dict(version=6, states={}, sources=[]))
    runner.write_json(case/'windows.json', [dict(address='0x101', title='Steam', **{'class':'steam'}, fullscreen=0, at=[0,0], size=[1000,900], workspace=dict(name='1')),
                                           dict(address='0x102', title='Friends List', **{'class':'steam'}, fullscreen=0, at=[0,0], size=[200,900], workspace=dict(name='1')),
                                           dict(address='0x103', title='Chat', **{'class':'steam'}, fullscreen=0, at=[0,0], size=[300,800], workspace=dict(name='1'))])
    (case/'requests.jsonl').write_text('')
    for name in ('bash', 'hyprctl', 'steam', 'pidof'):
        path=case/'bin'/name;path.write_text(ENDPOINT);path.chmod(0o755)


def check_geometry(rows, values, lua=False):
    """Independent oracle over final compositor argv, not Main's calculations."""
    gap=int(values.get('gapSize',10));height=round(1000*values.get('windowHeightPercent',95)/100)
    widths=[round(2000*values.get('friendsWidthPercent',10)/100-gap),round(2000*values.get('mainWidthPercent',60)/100-gap*2),round(2000*values.get('chatWidthPercent',25)/100-gap)]
    offset=round((2000-sum(widths)-gap*2)/2);top=round(1000*values.get('topMarginPercent',2.5)/100)
    coordinates=[offset,offset+widths[0]+gap,offset+widths[0]+gap+widths[1]+gap]
    commands=[row['argv'][1:] for row in rows if row['endpoint']=='hyprctl' and row['argv'][0]=='dispatch' and row['argv'][1]!='hl.dsp.no_op()']
    if values.get('useCustomLayout',False):
        assert commands and not any(any(word in str(command) for word in ('setfloating','window.float','resizewindowpixel','window.resize')) for command in commands),commands
    else:
        for address,width,x in zip(('0x102','0x101','0x103'),widths,coordinates):
            resize=[f'hl.dsp.window.resize({{ x = {width}, y = {height}, exact = true, window = "address:{address}" }})'] if lua else ['resizewindowpixel','exact',str(width),str(height)+',address:'+address]
            move=[f'hl.dsp.window.move({{ x = {x}, y = {top}, window = "address:{address}" }})'] if lua else ['movewindowpixel','exact',str(x),str(top)+',address:'+address]
            assert resize in commands,('selected geometry reaches actual compositor argv',resize,commands)
            assert move in commands,('selected position reaches actual compositor argv',move,commands)
    return dict(status='PASS',widths=widths,coordinates=coordinates,height=height,top=top,lua=lua,custom=values.get('useCustomLayout',False))


@receipt_run
def main():
    parser=argparse.ArgumentParser(description=__doc__);profile_argument(parser)
    for name in ('source','plugins','work-root','output'):parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--case',choices=('ordering-red','classic','lua','custom','retire-query','retire-all-query','retire-move-all','retire-move','retire-show','retire-focus','retire-focus-exec','retire-active','retire-new','retire-new-move','continuing','launch'),required=True)
    args=parser.parse_args();profile=activate_profile(args.guest_profile);profile.prepare_roots()
    if Path(__file__).resolve()!=args.source.resolve()/'Scripts/dev/plugin-settings-steam-regression.py':parser.error('execute supplied source')
    for path,parent in ((args.work_root,profile.work_base),(args.output,profile.journal_base)):
        if path!=path.resolve() or path==parent or not path.is_relative_to(parent):parser.error('fresh owned guest roots required')
    with (profile.work_base/'.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB);args.work_root.mkdir();args.output.mkdir()
        # These fixture installs read shell inputs only; generated entry/tooling
        # files are new paths. Keep immutable source files linked under inode pressure.
        install=args.work_root/'install';shutil.copytree(args.source,install,copy_function=os.link,ignore=shutil.ignore_patterns('.git','.envrc','__pycache__'))
        seed(args.work_root,args.plugins)
        stage={'retire-query':'detect','retire-all-query':'detect-all','retire-move-all':'move-all','retire-move':'move','retire-show':'show','retire-focus':'focus','retire-focus-exec':'focus-exec','retire-new':'new','retire-new-move':'new-move'}.get(args.case)
        if stage:(args.work_root/('hold-'+stage)).touch()
        if args.case in ('classic','lua','custom'):(args.work_root/'hold-detect').touch()
        if args.case=='retire-focus-exec':(args.work_root/'add-window').touch()
        runner.write_json(args.output/'sources.json',{str(p.relative_to(args.plugins)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((args.plugins/'hyprland-steam-overlay').rglob('*')) if p.is_file()})
        env=dict(PHA_STEAM_CASE=str(args.work_root),PHA_STEAM_TEST=args.case,PHA_STEAM_LUA='1' if args.case=='lua' else '0',HOME=str(args.work_root/'home'),PATH=str(args.work_root/'bin')+':'+os.environ['PATH'])
        text=runner.run_fixture(profile,install,args.work_root,args.output,args.source/'Scripts/dev/fixtures/plugin-settings-steam-lifetime.qml',extra_env=env,extra_lint=tuple(sorted((args.work_root/'config/plugins/hyprland-steam-overlay').glob('*.qml'))),timeout=90)
        if 'STEAM_LIFETIME: PASS '+args.case not in text:raise RuntimeError('incomplete Steam lifetime case')
        if any(word in text for word in ('TypeError:','ReferenceError:','SyntaxError:','Binding loop detected')):raise RuntimeError('Steam lifetime diagnostic')
        shutil.copy2(args.work_root/'requests.jsonl',args.output/'requests.jsonl')
        rows=[json.loads(line) for line in (args.output/'requests.jsonl').read_text().splitlines()]
        if args.case in ('classic','lua','custom','continuing'):
            runner.write_json(args.output/'geometry.json',check_geometry(rows,dict(gapSize=30,friendsWidthPercent=15,mainWidthPercent=50,chatWidthPercent=20,topMarginPercent=4,windowHeightPercent=80,useCustomLayout=args.case=='custom'),args.case=='lua'))
        if args.case=='continuing':
            assert any(row['endpoint']=='hyprctl' and row['argv']==['dispatch','setfloating','address:0x104'] for row in rows),'admitted continuing-window policy reaches actual float endpoint'
            assert any(row['endpoint']=='hyprctl' and row['argv']==['dispatch','alterzorder','top,address:0x104'] for row in rows),'admitted continuing-window policy reaches actual focus endpoint'
        # Every endpoint PID/start identity must really disappear after Main teardown.
        import time
        for _ in range(100):
            live=[]
            for row in rows:
                try:actual=(Path('/proc')/str(row['pid'])/'stat').read_text().split(') ',1)[1].split()[19]
                except FileNotFoundError:continue
                if actual==row['start']:live.append(row)
            if not live:break
            time.sleep(.02)
        if live:raise RuntimeError('live Steam endpoints '+repr(live))
        runner.write_json(args.output/'quiescence.json',dict(status='PASS',identities=len(rows),allAbsent=True))
        stage_receipt(args.output/'result.json',dict(status='PASS',case=args.case,physicalProof=False,nativeScopeProof=False))
        runner.remove_completed_installs(args.work_root,args.output)


if __name__=='__main__':main()
