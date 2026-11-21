#!/usr/bin/env python3
"""Reject omitted-origin output consumers after independent native publication."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
from guest_profile import activate_profile,profile_argument


def main():
    parser=argparse.ArgumentParser(description=__doc__);profile_argument(parser)
    for name in ('source','plugins','work-root','output'):parser.add_argument('--'+name,type=Path,required=True)
    args=parser.parse_args();profile=activate_profile(args.guest_profile);profile.prepare_roots()
    if Path(__file__).resolve()!=args.source.resolve()/'Scripts/dev/plugin-settings-output-native-controls.py':parser.error('execute supplied source')
    for path,parent in ((args.work_root,profile.work_base),(args.output,profile.journal_base)):
        if path!=path.resolve() or path==parent or not path.is_relative_to(parent):parser.error('fresh owned guest roots required')
    args.work_root.mkdir();args.output.mkdir()
    controls=[('display-settings','mainInst?.settingsConsumerFor(pluginApi?.settingsContext)','mainInst?.settingsConsumerFor()','selected config path reaches actual parsed Panel card'),('monitor-layout','setOutputPosition(selectedOutput.outputId, nextX, nextY, true, root.pluginApi?.settingsContext)','setOutputPosition(selectedOutput.outputId, nextX, nextY, true)','selected grid reaches actual shared draft and Panel child Text')]
    inputs={str(p.relative_to(args.source)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (Path(__file__),args.source/'Scripts/dev/plugin-settings-output-native-regression.py',args.source/'Scripts/dev/fixtures/plugin-settings-output-native.qml')}
    (args.output/'inputs.json').write_text(json.dumps(inputs,indent=2)+'\n')
    for member,old,new,message in controls:
        product=args.work_root/(member+'-control');shutil.copytree(args.plugins/member,product/member)
        path=product/member/'Panel.qml';text=path.read_text()
        if text.count(old)!=1:raise RuntimeError('stale native output origin control '+member)
        path.write_text(text.replace(old,new,1))
        work,out=args.work_root/(member+'-native'),args.output/member
        command=['python3','-B',str(args.source/'Scripts/dev/plugin-settings-output-native-regression.py'),'--guest-profile',str(args.guest_profile),'--source',str(args.source),'--plugins',str(product),'--work-root',str(work),'--output',str(out),'--plugin',member,'--scope','instance']
        result=subprocess.run(command,capture_output=True,text=True,timeout=180)
        (args.output/(member+'.log')).write_text(result.stdout+result.stderr)
        (args.output/(member+'.exit')).write_text(str(result.returncode)+'\n')
        root=out/(member+'-instance');log=(root/'edit/runtime.log').read_text()
        wanted='OUTPUT_NATIVE_ASSERT: '+member+'/instance/edit/effect: '+message
        if result.returncode==0 or (root/'edit/runtime.exit').read_text().strip()!='2' or wanted not in log:raise RuntimeError('native origin control did not reject at consumer '+member)
        if any(word in log for word in ('TypeError:','ReferenceError:','SyntaxError:','Binding loop detected')):raise RuntimeError('native control unrelated diagnostic '+member)
        expected=json.loads((work/(member+'-instance')/'expectations.json').read_text())['edited']
        if json.loads((root/'persisted/edited.json').read_text())!=dict(status='PASS',values=expected):raise RuntimeError('native origin control lacks complete edited documents')
        shutil.copy2(work/(member+'-instance')/'requests.jsonl',out/'requests.jsonl')
        (out/'control.json').write_text(json.dumps(dict(status='PASS',plugin=member,kind='omitted-origin',nativeEditedBoundary=True,rejectedAt=wanted,mutation=dict(path='Panel.qml',old=old,new=new)),indent=2)+'\n')
        print('OUTPUT_NATIVE_CONTROL '+member+': PASS',flush=True)
    (args.output/'result.json').write_text(json.dumps(dict(status='PASS',controls=2,completeGroupAcceptance=False),indent=2)+'\n')


if __name__=='__main__':main()
