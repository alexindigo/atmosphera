#!/usr/bin/env python3
"""Actual Steam page/native files and originating Bar geometry, both scopes."""
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

spec=importlib.util.spec_from_file_location('steam',Path(__file__).with_name('plugin-settings-steam-regression.py'))
steam=importlib.util.module_from_spec(spec);spec.loader.exec_module(steam)
runner=steam.runner


def hashes(case):
    return {str(p.relative_to(case)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((case/'config').rglob('*.json'))}


@receipt_run
def run(args,profile,scope):
    case,out=args.work_root/scope,args.output/scope;case.mkdir();out.mkdir();(out/'persisted').mkdir()
    install=case/'install';shutil.copytree(args.source,install,copy_function=os.link,ignore=shutil.ignore_patterns('.git','.envrc','__pycache__'))
    steam.seed(case,args.original_plugins or args.plugins)
    if args.omit_origin:
        bar=case/'config/plugins/hyprland-steam-overlay/BarWidget.qml'
        original=bar.read_text();assert original.count('toggleOverlay(pluginApi.settingsContext)')==2
        bar.write_text(original.replace('toggleOverlay(pluginApi.settingsContext)','toggleOverlay()'))
    shared=dict(gapSize=15,opaque='shared',friendsWidth=220,mainWidth=1200,chatWidth=400)
    bar=dict(widgets=dict(left=[dict(id='plugin:hyprland-steam-overlay',instanceSettings=row) for row in ({'opaque':'selected'},{'gapSize':45,'opaque':'sibling'},{'opaque':'inherited'})]))
    initial=dict(shared=shared,bar=bar);edited=deepcopy(initial)
    (edited['shared'] if scope=='shared' else edited['bar']['widgets']['left'][0]['instanceSettings'])['gapSize']=30
    reset=deepcopy(edited);(reset['shared'] if scope=='shared' else reset['bar']['widgets']['left'][0]['instanceSettings']).pop('gapSize')
    following=deepcopy(reset);following['shared']['gapSize']=25
    expected=dict(initial=initial,discarded=initial,edited=edited,**{'reset-staged':edited},reset=reset,following=following)
    runner.write_json(case/'input.json',dict(plugin='hyprland-steam-overlay'))
    runner.write_json(case/'expectations.json',expected)
    runner.write_json(case/'config/settings/plugins/hyprland-steam-overlay.json',shared)
    runner.write_json(case/'config/settings/bar.json',bar)
    product=(args.original_plugins or args.plugins)/'hyprland-steam-overlay'
    runner.write_json(out/'sources.json',{str(p.relative_to(product)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(product.rglob('*')) if p.is_file()})
    env=dict(PHA_STEAM_CASE=str(case),PHA_STEAM_SCOPE=scope,PHA_STEAM_OUTPUT=str(out),PHA_STEAM_DISK=str(args.source/'Scripts/dev/fixtures/plugin-settings-query-disk.py'),PHA_STEAM_ORIGINAL='1' if args.original_plugins else '0',PHA_STEAM_LUA='0',HOME=str(case/'home'),PATH=str(case/'bin')+':'+os.environ['PATH'])
    rejected=False
    modes=[('edit','')] if args.original_plugins or args.omit_origin else [('edit',''),('cold','edited'),('reset',''),('cold','reset'),('follow',''),('cold','following')]
    for mode,boundary in modes:
        part=out/(mode+('-'+boundary if boundary else ''));part.mkdir();before=hashes(case)
        text=runner.run_fixture(profile,install,case,part,args.source/'Scripts/dev/fixtures/plugin-settings-steam-native.qml',extra_env=dict(env,PHA_STEAM_MODE=mode,PHA_STEAM_BOUNDARY=boundary),extra_lint=tuple(sorted((case/'config/plugins/hyprland-steam-overlay').glob('*.qml'))),timeout=120)
        if 'STEAM_NATIVE: PASS '+scope+' '+mode+' '+boundary not in text:raise RuntimeError('incomplete Steam native case')
        if any(word in text for word in ('TypeError:','ReferenceError:','SyntaxError:','Binding loop detected')):raise RuntimeError('Steam native diagnostic')
        after=hashes(case);runner.write_json(part/'configuration-hashes.json',dict(before=before,after=after,nonpublishing=before==after))
        if mode=='cold' and before!=after:raise RuntimeError('Steam cold reader published')
        effect=boundary or {'edit':'edited','reset':'reset','follow':'following'}[mode]
        values=dict(expected[effect]['shared'])
        if scope=='instance':values.update(expected[effect]['bar']['widgets']['left'][0]['instanceSettings'])
        rows=[json.loads(line) for line in (case/'requests.jsonl').read_text().splitlines()]
        # The previous engine's commands are excluded by a monotone endpoint offset.
        last=int(text.split('STEAM_NATIVE_ENDPOINT_OFFSET ')[1].splitlines()[0])
        try:geometry=steam.check_geometry(rows[last:],values)
        except AssertionError as error:
            if not (args.original_plugins or args.omit_origin) or 'selected geometry reaches actual compositor argv' not in str(error):raise
            rejected=True;geometry=dict(status='REJECTED',assertion=str(error))
        runner.write_json(part/'geometry.json',geometry)
        if args.original_plugins or args.omit_origin:
            if not rejected:raise RuntimeError('wrong Steam origin escaped actual argv')
    wanted=['initial','discarded','edited'] if rejected else list(expected)
    for boundary in wanted:
        if json.loads((out/'persisted'/(boundary+'.json')).read_text())!=dict(status='PASS',values=expected[boundary]):raise RuntimeError('complete Steam native documents differ')
    shutil.copy2(case/'requests.jsonl',out/'requests.jsonl')
    rows=[json.loads(line) for line in (out/'requests.jsonl').read_text().splitlines()]
    for _ in range(100):
        live=[]
        for row in rows:
            try:actual=(Path('/proc')/str(row['pid'])/'stat').read_text().split(') ',1)[1].split()[19]
            except FileNotFoundError:continue
            if actual==row['start']:live.append(row)
        if not live:break
        time.sleep(.02)
    if live:raise RuntimeError('live native Steam endpoints '+repr(live))
    stage_receipt(out/'result.json',dict(status='PASS',scope=scope,kind='original-native-red' if args.original_plugins else 'omitted-origin-control' if args.omit_origin else 'native',completeNativeBoundaries=wanted,nonpublishingColdReaders=[] if rejected else ['edited','reset','following'],endpointRows=len(rows),allEndpointIdentitiesAbsent=True,physicalProof=False))
    runner.remove_completed_installs(case,out)


@receipt_run
def main():
    parser=argparse.ArgumentParser(description=__doc__);profile_argument(parser)
    for name in ('source','plugins','work-root','output'):parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--scope',choices=('instance','shared'));parser.add_argument('--original-plugins',type=Path);parser.add_argument('--omit-origin',action='store_true')
    args=parser.parse_args();profile=activate_profile(args.guest_profile);profile.prepare_roots()
    if Path(__file__).resolve()!=args.source.resolve()/'Scripts/dev/plugin-settings-steam-native-regression.py':parser.error('execute supplied source')
    for path,parent in ((args.work_root,profile.work_base),(args.output,profile.journal_base)):
        if path!=path.resolve() or path==parent or not path.is_relative_to(parent):parser.error('fresh owned guest roots required')
    with (profile.work_base/'.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB);args.work_root.mkdir();args.output.mkdir()
        runner.write_json(args.output/'inputs.json',{str(p.relative_to(args.source)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (Path(__file__),Path(steam.__file__),args.source/'Scripts/dev/fixtures/plugin-settings-steam-native.qml',args.source/'Scripts/dev/fixtures/plugin-settings-query-disk.py')})
        for scope in ((args.scope,) if args.scope else ('instance','shared')):run(args,profile,scope)
        stage_receipt(args.output/'result.json',dict(status='PASS',completeGroupAcceptance=False))


if __name__=='__main__':main()
