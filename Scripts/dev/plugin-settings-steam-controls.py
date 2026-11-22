#!/usr/bin/env python3
"""Reject disposable shared-admission and retirement Steam consumer controls."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

from guest_profile import activate_profile, profile_argument


def main():
    parser=argparse.ArgumentParser(description=__doc__);profile_argument(parser)
    for name in ('source','plugins','work-root','output'):parser.add_argument('--'+name,type=Path,required=True)
    args=parser.parse_args();profile=activate_profile(args.guest_profile);profile.prepare_roots()
    if Path(__file__).resolve()!=args.source.resolve()/'Scripts/dev/plugin-settings-steam-controls.py':parser.error('execute supplied source')
    for path,parent in ((args.work_root,profile.work_base),(args.output,profile.journal_base)):
        if path!=path.resolve() or path==parent or not path.is_relative_to(parent):parser.error('fresh owned guest roots required')
    args.work_root.mkdir();args.output.mkdir()
    controls=[('policy','classic','values: context.settingsView','values: pluginApi.pluginSettings','selected geometry reaches actual compositor argv'),
              ('retirement','retire-query','if (!_policyCurrent) stopPolicy();','if (false) stopPolicy();','retired held stage has no later endpoint')]
    results=[]
    for label,scenario,old,new,wanted in controls:
        root=args.work_root/('input-'+label);root.mkdir()
        shutil.copytree(args.plugins/'hyprland-steam-overlay',root/'hyprland-steam-overlay')
        main=root/'hyprland-steam-overlay/Main.qml';text=main.read_text();assert text.count(old)==1;main.write_text(text.replace(old,new))
        out=args.output/label;case=args.work_root/label
        command=['python3','-B',str(args.source/'Scripts/dev/plugin-settings-steam-regression.py'),'--guest-profile',str(args.guest_profile),'--source',str(args.source),'--plugins',str(root),'--work-root',str(case),'--output',str(out),'--case',scenario]
        result=subprocess.run(command,capture_output=True,text=True)
        (args.output/(label+'.log')).write_text(result.stdout+result.stderr)
        if result.returncode==0:raise RuntimeError(label+': control escaped')
        text=result.stdout+result.stderr+(out/'runtime.log').read_text()
        if wanted not in text:raise RuntimeError(label+': unrelated failure '+text)
        identities=[]
        for line in (case/'requests.jsonl').read_text().splitlines():
            row=json.loads(line);path=Path('/proc')/str(row['pid'])/'stat'
            if path.exists() and path.read_text().split(') ',1)[1].split()[19]==row['start']:raise RuntimeError('live control endpoint '+repr(row))
            identities.append((row['pid'],row['start']))
        receipt=dict(status='PASS',kind='rejecting-runtime-control',control=label,rejectedAt=wanted,driverExit=result.returncode,allEndpointIdentitiesAbsent=True,identities=len(identities))
        (args.output/(label+'.json')).write_text(json.dumps(receipt,indent=2)+'\n');results.append(receipt)
        print(label+' control rejected',flush=True)
    names=['plugin-settings-steam-controls.py','plugin-settings-steam-regression.py','fixtures/plugin-settings-steam-lifetime.qml']
    inputs={name:hashlib.sha256((args.source/'Scripts/dev'/name).read_bytes()).hexdigest() for name in names}
    (args.output/'result.json').write_text(json.dumps(dict(status='PASS',controls=results,inputs=inputs,physicalProof=False),indent=2)+'\n')
    profile.verify()


if __name__=='__main__':main()
