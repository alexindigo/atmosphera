#!/usr/bin/env python3
"""Controlled compositor grammars and all nine held parser-stage lifetimes."""
import argparse
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
from guest_profile import activate_profile, profile_argument
spec=importlib.util.spec_from_file_location('kbd_life_runner',Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner=importlib.util.module_from_spec(spec); spec.loader.exec_module(runner)
STAGES=['niri-read','niri-glob','hypr-read','hypr-glob','hypr-detect','hypr-lua','hyprctl','mango-read','mango-glob']

def files(case):
    for folder in ('initial','replacement'):
        root=case/folder
        for name in ('niri/extra','hypr/extra','mango/extra'): (root/name).mkdir(parents=True)
        (root/'niri/main.kdl').write_text('include "extra/*.kdl"\nbinds {\n    Mod+1 { focus-workspace 1; }\n    Mod+2 { focus-workspace 2; }\n    Mod+3 { focus-workspace 3; }\n    Mod+Return hotkey-overlay-title="'+folder+' niri bind" { spawn "fixture"; }\n}\n')
        (root/'niri/extra/child.kdl').write_text('binds {\n    Ctrl+E hotkey-overlay-title="included niri bind" { spawn "fixture"; }\n}\n')
        (root/'hypr/main.conf').write_text('# 1. Apps\nbind = $meta, RETURN, exec, fixture #"'+folder+' conf bind"\nsource = extra/*.conf\n')
        (root/'hypr/extra/child.conf').write_text('# 1. Extra\nbind = CTRL, E, exec, fixture #"included conf bind"\n')
        (root/'hypr/main.lua').write_text('-- 1. Lua\nrequire("extra.module")\n')
        (root/'hypr/extra/module.lua').write_text('-- 2. Child\ndescription = "lua bind"\n')
        (root/'mango/main.conf').write_text('# 1. Apps\nbind=SUPER,Return,spawn,'+folder+' mango bind\naxisbind=CTRL,UP,focusdir,left\nmousebind=ALT,BTN_LEFT,killclient\nsource=extra/*.conf\n')
        (root/'mango/extra/child.conf').write_text('# 2. Extra\nbinds=LOGO,E,spawn,included mango bind\n')
    (case/'empty.kdl').write_text('')
    (case/'empty.conf').write_text('')

def main():
    p=argparse.ArgumentParser(description=__doc__); profile_argument(p)
    for name in ('source','plugins','work-root','output'): p.add_argument('--'+name,type=Path,required=True)
    p.add_argument('--stage',choices=STAGES); p.add_argument('--mode',choices=('functional','replace','retire','destroy','cache','failure','startfail','edges'),default='functional')
    p.add_argument('--fail-stage',choices=STAGES)
    p.add_argument('--control',choices=('retirement',))
    args=p.parse_args(); profile=activate_profile(args.guest_profile); profile.prepare_roots()
    if Path(__file__).resolve()!=args.source/'Scripts/dev/plugin-settings-keybind-lifetime-regression.py': p.error('execute supplied source')
    if args.mode in ('replace','retire','destroy') and not args.stage: p.error('held stage required')
    if args.control and (args.mode!='retire' or args.stage!='niri-read'): p.error('explicit retirement control target required')
    for path,parent in ((args.work_root,profile.work_base),(args.output,profile.journal_base)):
        if path!=path.resolve() or path==parent or not path.is_relative_to(parent): p.error('fresh owned roots required')
    with (profile.work_base/'.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB); args.work_root.mkdir(); args.output.mkdir()
        case=args.work_root; out=args.output; install=case/'install'; shutil.copytree(args.source,install,ignore=shutil.ignore_patterns('.git','.envrc','__pycache__'))
        compositor=install/'Services/Compositor/CompositorService.qml'
        compositor.write_text('pragma Singleton\nimport QtQuick\nQtObject { property bool isNiri: false; property bool isHyprland: false; property bool isMango: false; property bool isSway: false; property bool isLabwc: false }\n')
        for part in ('config/settings','cache','state','bin'): (case/part).mkdir(parents=True)
        dest=case/'config/plugins/keybind-cheatsheet'; shutil.copytree(args.plugins/'keybind-cheatsheet',dest)
        if args.control:
            path=dest/'ParserClient.qml'; text=path.read_text(); assert text.count('if (!current && constructed) retireClient()')==1 and text.count('if (!root.settingsContext.current()) root.retireClient();')==1
            path.write_text(text.replace('if (!current && constructed) retireClient()','if (false) retireClient()').replace('if (!root.settingsContext.current()) root.retireClient();','if (false) root.retireClient();'))
        if args.mode=='startfail':
            path=dest/'ParserGeneration.qml'; text=path.read_text(); assert text.count('["cat", nextFile]')==4
            path.write_text(text.replace('["cat", nextFile]','["keybind-missing-cat", nextFile]'))
        files(case); (case/'endpoints.jsonl').touch()
        endpoint=args.source/'Scripts/dev/fixtures/plugin-settings-keybind-endpoint.py'
        for name in ('cat','sh','hyprctl'): shutil.copy2(endpoint,case/'bin'/name); (case/'bin'/name).chmod(0o755)
        runner.write_json(case/'config/settings.json',dict(settingsVersion=62)); runner.write_json(case/'config/plugins.json',dict(version=6,states={},sources=[]))
        fixture=args.source/'Scripts/dev/fixtures/plugin-settings-keybind-lifetime.qml'
        runner.write_json(out/'inputs.json',dict(source=str(args.source),plugins=str(args.plugins),mode=args.mode,stage=args.stage,files={str(path):hashlib.sha256(path.read_bytes()).hexdigest() for path in [Path(__file__),fixture,endpoint,*sorted(dest.glob('*.qml')),dest/'MangoParser.js']},compositorCollaborator=dict(path=str(compositor),sha256=hashlib.sha256(compositor.read_bytes()).hexdigest()),physicalProof=False))
        env=dict(PATH=str(case/'bin')+':'+os.environ['PATH'],KBD_ENDPOINT_CASE=str(case),KBD_HOLD_STAGE=args.stage or '',KBD_FAIL_STAGE=args.fail_stage or '',KBD_MODE=args.mode,KBD_PLUGIN=str(dest),KBD_ENDPOINT=str(endpoint))
        try:
            text=runner.run_fixture(profile,install,case,out,fixture,extra_env=env,extra_lint=tuple(sorted(dest.glob('*.qml'))),timeout=120)
        except RuntimeError:
            if not args.control or 'origin retirement destroys client and every stage' not in (out/'runtime.log').read_text() or (out/'runtime.exit').read_text().strip()!='2': raise
            text=(out/'runtime.log').read_text()
        else:
            if args.control: raise RuntimeError('retirement control escaped')
        checked='\n'.join(line for line in text.splitlines() if not (args.mode=='edges' and 'hyprctl JSON parse failed: SyntaxError:' in line))
        if not args.control and ('KEYBIND_LIFETIME: PASS' not in text or any(value in checked for value in ('TypeError:','ReferenceError:','SyntaxError:','Binding loop detected','KEYBIND_LIFE_ASSERT:'))): raise RuntimeError('parser lifetime failure')
        if args.mode=='startfail' and 'Process failed to start' not in text: raise RuntimeError('failed-start path not exercised')
        rows=[json.loads(line) for line in (case/'endpoints.jsonl').read_text().splitlines()]
        for row in rows:
            if runner_path:=Path('/proc/'+str(row['pid'])+'/stat'):
                try: current=runner_path.read_text().rsplit(')',1)[1].split()[19]
                except FileNotFoundError: continue
                if current==row['start']: raise RuntimeError('endpoint still present after engine')
        shutil.copy2(case/'endpoints.jsonl',out/'endpoints.jsonl')
        runner.write_json(out/'result.json',dict(status='PASS',mode=args.mode,stage=args.stage,control=args.control,rejected=bool(args.control),checks=text.count('KEYBIND_LIFE_CHECK:'),endpoints=len(rows),physicalProof=False,completePlanAcceptance=False))
        runner.remove_completed_installs(case,out)
if __name__=='__main__': main()
