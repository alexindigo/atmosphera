#!/usr/bin/env python3
"""G1a Real-domain/QML int conversion and original Timer running policies."""
import argparse
import fcntl
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shutil
import os

from guest_profile import activate_profile, profile_argument

SPEC=importlib.util.spec_from_file_location('host_runner',Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
r=importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(r)
CASES=[('battery-wireless-devices',1.5,1,1000,True),('battery-wireless-devices',0.5,0,0,True),('battery-wireless-devices',0,60,60000,True),
       ('cloudflare-warp',1.5,1,1,True),('cloudflare-warp',0,0,0,True),('monique',1.5,1,1,True),('monique',0,0,0,True),
       ('ip-monitor',1.5,1,1000,True),('ip-monitor',0.5,0,0,False),('ip-monitor',0,0,0,False)]


def run(a,profile,index,case_input):
    plugin,value,projection,interval,running=case_input
    name=str(index)+'-'+plugin
    case,out=a.work_root/name,a.output/name
    case.mkdir(); out.mkdir()
    install=case/'install'
    shutil.copytree(a.source,install,ignore=shutil.ignore_patterns('.git','.envrc','__pycache__'))
    shutil.copytree(a.plugins/plugin,case/'plugin')
    for name in ('config/settings','cache','state','inert/scripts','bin'): (case/name).mkdir(parents=True)
    r.write_json(case/'config/settings.json',dict(settingsVersion=62))
    r.write_json(case/'config/plugins.json',dict(version=6,states={},sources=[]))
    shutil.copy2(a.plugins/plugin/'manifest.json',case/'manifest.json')
    (case/'inert/scripts/scan.py').write_text('print("[]")\n')
    stubs={'warp-cli':'printf "Status update: Disconnected\\n"',
           'monique':'case "$1" in --list-profiles) printf "[]\\n";; *) printf "inert\\n";; esac',
           'curl':'''printf '%s\\n' '{"status":"success","query":"controlled"}' '''}
    for command,body in stubs.items():
        path=case/'bin'/command; path.write_text('#!/bin/sh\n'+body+'\n'); path.chmod(0o755)
    if a.negative_control:
        path=install/'Services/Plugins/PluginSettingsPoller.qml'; text=path.read_text()
        old,new=('required property int sourceInterval','required property real sourceInterval') if a.negative_control=='early-scale' else ('property bool requirePositiveInterval: false','property bool requirePositiveInterval: true')
        if text.count(old)!=1: raise RuntimeError('review polling domain control anchor')
        path.write_text(text.replace(old,new,1))
    env=dict(POLL_EDGE_CASE=str(case),POLL_EDGE_PLUGIN=str(case/'plugin'),POLL_EDGE_VALUE=str(value),PATH=str(case/'bin')+':'+os.environ['PATH'])
    text=r.run_fixture(profile,install,case,out,a.source/'Scripts/dev/fixtures/plugin-settings-polling-domain.qml',extra_env=env,timeout=15)
    match=re.search(r'POLL_EDGE (\{[^\n]+\})',text)
    if not match: raise RuntimeError('actual Main/Timer observation missing')
    actual=json.loads(match[1]); expected=dict(input=value,mainProjection=projection,interval=interval,running=running)
    result=dict(status='PASS' if actual==expected else 'FAIL',plugin=plugin,expected=expected,actual=actual,nativeInstanceAcceptance=False)
    r.write_json(out/'result.json',result); r.remove_completed_installs(case,out)
    return result


def main():
    p=argparse.ArgumentParser(description=__doc__); profile_argument(p)
    for name in ('source','plugins','work-root','output'): p.add_argument('--'+name,type=Path,required=True)
    p.add_argument('--negative-control',choices=('early-scale','positive-only'))
    a=p.parse_args(); profile=activate_profile(a.guest_profile); profile.prepare_roots()
    if Path(__file__).resolve()!=a.source.resolve()/'Scripts/dev/plugin-settings-polling-domain-regression.py': p.error('execute from supplied source tree')
    for path,parent in ((a.work_root,profile.work_base),(a.output,profile.journal_base)):
        if path!=path.resolve() or path==parent or not path.is_relative_to(parent): p.error('fresh owned profile roots required')
    with (profile.work_base/'.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB); a.work_root.mkdir(); a.output.mkdir()
        a.baseline_source=a.baseline_plugins=None
        r.write_json(a.output/'inputs.json',dict(native=r.input_fingerprints(a),files={str(path.relative_to(root)):hashlib.sha256(path.read_bytes()).hexdigest()
            for root,paths in ((a.source,[Path(__file__),a.source/'Scripts/dev/fixtures/plugin-settings-polling-domain.qml',a.source/'Services/Plugins/PluginSettingsPoller.qml']),
                              (a.plugins,[path for plugin in {row[0] for row in CASES} for path in sorted((a.plugins/plugin).rglob('*'))])) for path in paths if path.is_file()}))
        cases=CASES[:1] if a.negative_control=='early-scale' else [CASES[4]] if a.negative_control else CASES
        results=[run(a,profile,index,row) for index,row in enumerate(cases)]
        if a.negative_control:
            if not any(row['status']=='FAIL' for row in results): raise RuntimeError('polling domain control escaped')
        elif any(row['status']!='PASS' for row in results): raise RuntimeError('polling domain behavior changed: '+json.dumps(results))
        r.write_json(a.output/'result.json',dict(status='PASS',kind='rejecting-control' if a.negative_control else 'actual-main-typed-domain',cases=results,nativeInstanceAcceptance=False))
        print('PLUGIN_SETTINGS_POLLING_DOMAIN: PASS ('+str(len(results))+' cases)',flush=True)


if __name__=='__main__': main()
