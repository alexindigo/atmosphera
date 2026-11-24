#!/usr/bin/env python3
"""OBS action admission, protocol stages, retained Toast and origin lifetimes."""
from fixture_receipts import receipt_run, stage_receipt
from fixtures.source_delivery import link_or_copy
import argparse
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import time

from fixture_resources import FixtureResources
from guest_profile import activate_profile, profile_argument

spec=importlib.util.spec_from_file_location('obs',Path(__file__).with_name('plugin-settings-obs-regression.py'))
obs=importlib.util.module_from_spec(spec);spec.loader.exec_module(obs);runner=obs.runner
SCENARIOS=('typed','panel-origin','launch-normal','launch-retire','start-Record','start-Replay','start-Stream','online-actions','failure','record-toast','toast-retire','request-retire','output-retire','auto-retire','terminate-retire','confirm-retire','auto-close','auto-active','auto-failure')

@receipt_run
def run(args,profile,scenario):
    with FixtureResources() as resources:
        return run_with_endpoint(args,profile,scenario,resources)


def run_with_endpoint(args,profile,scenario,resources):
    case,out=args.work_root/scenario,args.output/scenario;case.mkdir();out.mkdir()
    install=case/'install';shutil.copytree(args.source,install,copy_function=link_or_copy,ignore=shutil.ignore_patterns('.git','.envrc','__pycache__'))
    product=obs.seed(case,args.plugins);shutil.copy2(args.source/'Assets/ColorScheme/MacOS/MacOS.json',case/'config/colors.json')
    if scenario=='auto-active':runner.write_json(case/'obs-state.json',dict(recording=True,replay=False,streaming=False,camera=True))
    if args.control:
        if args.control=='launch-policy':
            path=product/'Main.qml';text=path.read_text();old='policy.launchBehavior === "minimized-to-tray"';assert text.count(old)==1;path.write_text(text.replace(old,'launchBehavior === "minimized-to-tray"'))
        elif args.control=='retirement':
            path=product/'Main.qml';text=path.read_text();old='root.activeAction !== policy';assert text.count(old)==1
            text=text.replace(old,'false').replace('if (policy && !actionCurrent)','if (false)').replace('if (!policy.context.current())','if (false)');path.write_text(text)
        elif args.control=='toast-policy':
            path=product/'Main.qml';text=path.read_text();old='root.openVideosForPolicy(policy)';assert text.count(old)==1;path.write_text(text.replace(old,'root.openVideos()'))
    resources.defer(shutil.copy2,case/'socket.jsonl',out/'socket.jsonl')
    resources.defer(shutil.copy2,case/'requests.jsonl',out/'requests.jsonl')
    endpoint=obs.ObsEndpoint(case)
    resources.serve(endpoint,interrupt=endpoint.finish)
    runner.write_json(case/'config/obs-studio/plugin_config/obs-websocket/config.json',dict(server_enabled=True,server_port=endpoint.server_address[1],server_password=''))
    before=obs.hashes(case);fixture=args.source/'Scripts/dev/fixtures/plugin-settings-obs-lifetime.qml'
    env=dict(PHA_OBS_CASE=str(case),PHA_OBS_SCENARIO=scenario,HOME=str(case/'home'),XDG_CONFIG_HOME=str(case/'config'),PATH=str(case/'bin')+':'+os.environ['PATH'])
    rejected=False
    try:text=runner.run_fixture(profile,install,case,out,fixture,extra_env=env,extra_lint=tuple(sorted(product.rglob('*.qml'))),timeout=100)
    except RuntimeError:
        text=(out/'runtime.log').read_text();wanted={'launch-policy':'launch keeps admitted normal policy','retirement':'retired request cannot stop output','toast-policy':'Toast retains admitted path/opener and retirement'}.get(args.control)
        assert wanted and wanted in text and (out/'runtime.exit').read_text().strip()=='2',text;rejected=True
    assert rejected==bool(args.control)
    if not rejected:assert 'OBS_LIFETIME: PASS '+scenario in text
    assert not any(word in text for word in ('TypeError:','ReferenceError:','SyntaxError:','Binding loop detected'))
    resources.close()
    after=obs.hashes(case);assert before==after;runner.write_json(out/'configuration-hashes.json',dict(before=before,after=after))
    rows=[json.loads(line) for line in (out/'requests.jsonl').read_text().splitlines()]
    for _ in range(100):
        live=[]
        for row in rows:
            stat=Path('/proc')/str(row['pid'])/'stat'
            if stat.exists() and stat.read_text().split(') ',1)[1].split()[19]==row['start']:live.append(row)
        if not live:break
        time.sleep(.02)
    assert not live,live
    assert not any(json.loads(line)['event']=='error' for line in (out/'socket.jsonl').read_text().splitlines())
    runner.write_json(out/'sources.json',{str(p.relative_to(product)):hashlib.sha256(p.read_bytes()).hexdigest() for p in product.rglob('*') if p.is_file()})
    stage_receipt(out/'result.json',dict(status='PASS',scenario=scenario,control=args.control,allEndpointIdentitiesAbsent=True,endpointRows=len(rows),physicalProof=False))
    runner.remove_completed_installs(case,out)

@receipt_run
def main():
    parser=argparse.ArgumentParser(description=__doc__);profile_argument(parser)
    for name in ('source','plugins','work-root','output'):parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--scenario',choices=SCENARIOS);parser.add_argument('--control',choices=('launch-policy','retirement','toast-policy'))
    args=parser.parse_args();profile=activate_profile(args.guest_profile);profile.prepare_roots()
    assert Path(__file__).resolve()==args.source.resolve()/'Scripts/dev/plugin-settings-obs-lifetime-regression.py'
    for path,parent in ((args.work_root,profile.work_base),(args.output,profile.journal_base)):assert path==path.resolve() and path!=parent and path.is_relative_to(parent)
    if args.control:assert args.scenario=={'launch-policy':'launch-normal','retirement':'request-retire','toast-policy':'record-toast'}[args.control]
    with (profile.work_base/'.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB);args.work_root.mkdir();args.output.mkdir()
        inputs=(Path(__file__),args.source/'Scripts/dev/fixtures/plugin-settings-obs-lifetime.qml',args.source/'Scripts/dev/plugin-settings-obs-regression.py',args.source/'Scripts/dev/plugin-settings-query-lifecycle-regression.py')
        runner.write_json(args.output/'inputs.json',{str(p.relative_to(args.source)):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs})
        for scenario in ((args.scenario,) if args.scenario else SCENARIOS):run(args,profile,scenario)
        stage_receipt(args.output/'result.json',dict(status='PASS',scenarios=[args.scenario] if args.scenario else SCENARIOS,completeGroupAcceptance=False))

if __name__=='__main__':main()
