#!/usr/bin/env python3
"""Hold actual startup observations while an originating Steam request is admitted."""
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

spec=importlib.util.spec_from_file_location('steam',Path(__file__).with_name('plugin-settings-steam-regression.py'))
steam=importlib.util.module_from_spec(spec);spec.loader.exec_module(steam)


@receipt_run
def main():
    parser=argparse.ArgumentParser(description=__doc__);profile_argument(parser)
    for name in ('source','plugins','work-root','output'):parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--retire',action='store_true')
    args=parser.parse_args();profile=activate_profile(args.guest_profile);profile.prepare_roots()
    if Path(__file__).resolve()!=args.source.resolve()/'Scripts/dev/plugin-settings-steam-startup-regression.py':parser.error('execute supplied source')
    for path,parent in ((args.work_root,profile.work_base),(args.output,profile.journal_base)):
        if path!=path.resolve() or path==parent or not path.is_relative_to(parent):parser.error('fresh owned guest roots required')
    with (profile.work_base/'.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB);args.work_root.mkdir();args.output.mkdir()
        install=args.work_root/'install';shutil.copytree(args.source,install,copy_function=os.link,ignore=shutil.ignore_patterns('.git','.envrc','__pycache__'))
        steam.seed(args.work_root,args.plugins)
        endpoint=steam.ENDPOINT.replace("if name=='hyprctl':", "if name=='hyprctl':\n if args in (['monitors','-j'],['dispatch','hl.dsp.no_op()']):\n  while not (b/'release-probes').exists():time.sleep(.02)")
        for path in (args.work_root/'bin').iterdir():path.write_text(endpoint)
        env=dict(PHA_STEAM_CASE=str(args.work_root),PHA_STEAM_LUA='1',PHA_STEAM_RETIRE='1' if args.retire else '0',HOME=str(args.work_root/'home'),PATH=str(args.work_root/'bin')+':'+os.environ['PATH'])
        text=steam.runner.run_fixture(profile,install,args.work_root,args.output,args.source/'Scripts/dev/fixtures/plugin-settings-steam-startup.qml',extra_env=env,extra_lint=tuple(sorted((args.work_root/'config/plugins/hyprland-steam-overlay').glob('*.qml'))),timeout=60)
        if 'STEAM_STARTUP: PASS' not in text:raise RuntimeError('incomplete Steam startup admission')
        if any(word in text for word in ('TypeError:','ReferenceError:','SyntaxError:','Binding loop detected')):raise RuntimeError('Steam startup diagnostic')
        rows=[json.loads(line) for line in (args.work_root/'requests.jsonl').read_text().splitlines()]
        if args.retire:
            assert not any(row['endpoint']=='bash' and row['stage'] in ('detect','detect-all','move','show') for row in rows),'retired startup dispatched a continuation'
            geometry=dict(status='PASS',retiredBeforeObservation=True,noQueryOrEffect=True)
        else:
            geometry=steam.check_geometry(rows,dict(gapSize=30,friendsWidthPercent=15,mainWidthPercent=50,chatWidthPercent=20,topMarginPercent=4,windowHeightPercent=80),True)
            assert sum(row['endpoint']=='hyprctl' and row['argv']==['dispatch','hl.dsp.workspace.toggle_special("steam")'] for row in rows)==2,'actual opening and closing dispatch'
            geometry['actualClose']=True
        (args.output/'geometry.json').write_text(json.dumps(geometry,indent=2)+'\n')
        shutil.copy2(args.work_root/'requests.jsonl',args.output/'requests.jsonl')
        inputs={str(p.relative_to(args.source)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (Path(__file__),Path(steam.__file__),args.source/'Scripts/dev/fixtures/plugin-settings-steam-startup.qml')}
        stage_receipt(args.output/'result.json', dict(status='PASS',inputs=inputs,physicalProof=False))
        steam.runner.remove_completed_installs(args.work_root,args.output)


if __name__=='__main__':main()
