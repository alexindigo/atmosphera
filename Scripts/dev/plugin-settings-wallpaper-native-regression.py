#!/usr/bin/env python3
"""Actual wallpaper pages/native owners and selected inert engine consumers."""
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

spec = importlib.util.spec_from_file_location('wallpaper_runtime', Path(__file__).with_name('plugin-settings-wallpaper-runtime-regression.py'))
runtime = importlib.util.module_from_spec(spec); spec.loader.exec_module(runtime)
runner = runtime.runner


def hashes(case):
    return {str(p.relative_to(case)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((case/'config').rglob('*.json'))}


@receipt_run
def run(args, profile, plugin, scope):
    case, out = args.work_root/(plugin+'-'+scope), args.output/(plugin+'-'+scope)
    case.mkdir(); out.mkdir(); (out/'persisted').mkdir(); install=case/'install'
    shutil.copytree(args.source,install,ignore=shutil.ignore_patterns('.git','.envrc','__pycache__'))
    product=args.plugins/plugin; dest=case/('config/plugins/'+plugin); shutil.copytree(product,dest)
    for part in ('config/settings/plugins','home','bin','cache','state','shared-folder'): (case/part).mkdir(parents=True)
    lwe=plugin=='linux-wallpaperengine-controller'; field='defaultFps' if lwe else 'profile'
    # Seed every operational field touched by construction. Physical baseline and
    # LWE stability/recovery have separate individual tests, not this page matrix.
    shared=dict(opaque='shared')
    if lwe: shared.update(defaultFps=13,autoApplyOnStartup=False,screens={'Virtual-1':dict(path=str(case/'wallpaper'))},lastKnownGoodScreens={},runtimeRecoveryPending=False,wallpaperProperties={},wallpaperColorScreenshots={},wallpapersFolder=str(case/'shared-folder'))
    else: shared.update(profile='default',active=True,isPlaying=True,isMuted=False,currentWallpaper=str(case/'wallpaper.mp4'),mpvSocket=str(profile.runtime_base/'wallpaper-native-socket'),oldWallpapers={},thumbCacheReady=True,wallpapersFolder=str(case/'shared-folder'))
    bar=dict(widgets=dict(left=[dict(id='plugin:'+plugin,instanceSettings=row) for row in (dict(opaque='selected'),{field:41 if lwe else 'low-latency', 'opaque':'sibling'},dict(opaque='inherited'))]))
    initial=dict(shared=shared,bar=bar); edited=deepcopy(initial)
    (edited['shared'] if scope=='shared' else edited['bar']['widgets']['left'][0]['instanceSettings'])[field]=29 if lwe else 'fast'
    reset=deepcopy(edited); (reset['shared'] if scope=='shared' else reset['bar']['widgets']['left'][0]['instanceSettings']).pop(field)
    following=deepcopy(reset); following['shared'][field]=37 if lwe else 'high-quality'
    expected=dict(initial=initial,discarded=initial,edited=edited,**{'reset-staged':edited},reset=reset,following=following)
    if args.tool_origin:
        tool_clear=deepcopy(edited)
        (tool_clear['shared'] if scope=='shared' else tool_clear['bar']['widgets']['left'][0]['instanceSettings'])['currentWallpaper']=''
        expected=dict(initial=initial,discarded=initial,edited=edited,**{'tool-clear':tool_clear})
    for path,value in [('input.json',dict(plugin=plugin)),('expectations.json',expected),('config/settings.json',dict(settingsVersion=62)),('config/settings/colorSchemes.json',dict(useWallpaperColors=False)),('config/plugins.json',dict(version=6,states={},sources=[])),('config/settings/plugins/'+plugin+'.json',shared),('config/settings/bar.json',bar)]: runner.write_json(case/path,value)
    (case/'requests.jsonl').write_text(''); (case/'bin/endpoint.py').write_text(runtime.ENDPOINT)
    for name in ('linux-wallpaperengine','mpvpaper','ffmpeg'):
        endpoint=case/'bin'/name; endpoint.write_text(runtime.ENDPOINT); endpoint.chmod(0o755)
    adapters=[]
    if lwe:
        path=dest/'Main.qml'; text=path.read_text(); old='readonly property int stableRunDelay: 2500'
        if text.count(old)!=1: raise RuntimeError('review isolated stability timer adapter')
        path.write_text(text.replace(old,'readonly property int stableRunDelay: 60000'))
        adapters.append(dict(path='Main.qml',old=old,new='readonly property int stableRunDelay: 60000',reason='hold operational stability publication outside preference-only page matrix; real stability/recovery is an individual gate'))
        for name in ('force-stop-engine.sh','scan-wallpapers.sh','capture-wallpaper-colors.sh','check-file-exists.sh','update-noctalia-wallpapers-cache.sh'):
            path=dest/'scripts'/name; adapters.append(dict(path=str(path.relative_to(dest)),sha256=hashlib.sha256(path.read_bytes()).hexdigest(),reason='inert physical endpoint'))
            path.write_text('#!/bin/sh\nexec python3 "$PHA_WALLPAPER_CASE/bin/endpoint.py" '+name+' "$@"\n'); path.chmod(0o755)
    runner.write_json(out/'sources.json',{str(p.relative_to(product)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(product.rglob('*')) if p.is_file()})
    if args.negative_control:
        if args.negative_control == 'shared-policy':
            path=dest/'Main.qml'
            old,new=('readonly property var cfg: policyContext?.settingsView || ({})','readonly property var cfg: pluginApi?.pluginSettings || ({})') if lwe else ('readonly property var cfg: policyContext?.settingsView ?? ({})','readonly property var cfg: pluginApi?.pluginSettings ?? ({})')
        else:
            path=dest/'BarWidget.qml'
            old,new=('reload(true, pluginApi?.settingsContext)','reload(true)') if lwe else ('setPreference("isPlaying", true, root.pluginApi)','setPreference("isPlaying", true)')
        text=path.read_text()
        if text.count(old)!=1: raise RuntimeError('stale wallpaper native control '+args.negative_control)
        path.write_text(text.replace(old,new))
        adapters.append(dict(path=str(path.relative_to(dest)),old=old,new=new,reason='rejecting '+args.negative_control+' control in disposable product copy'))
    runner.write_json(out/'adapters.json',adapters)
    env=dict(PHA_WALLPAPER_PLUGIN=plugin,PHA_WALLPAPER_SCOPE=scope,PHA_WALLPAPER_CASE=str(case),PHA_WALLPAPER_OUTPUT=str(out),PHA_WALLPAPER_DISK=str(args.source/'Scripts/dev/fixtures/plugin-settings-query-disk.py'),PHA_WALLPAPER_TOOL_ORIGIN='1' if args.tool_origin else '0',HOME=str(case/'home'),PATH=str(case/'bin')+':'+os.environ['PATH'])
    env['PHA_WALLPAPER_CALLER_PROOF']='1' if args.caller_proof or args.negative_control=='omitted-caller' else '0'
    modes=[('edit','')] if args.tool_origin or args.negative_control or args.caller_proof else [('edit',''),('cold','edited'),('reset',''),('cold','reset'),('follow',''),('cold','following')]
    rejected=False
    wanted='WALLPAPER_NATIVE_ASSERT: '+plugin+'/instance/edit/effect: actual selected wallpaper policy reaches inert engine'
    for mode,boundary in modes:
        output=out/(mode+('-'+boundary if boundary else '')); output.mkdir(); before=hashes(case)
        # Every engine owns a distinct finite endpoint lifetime.
        (case/'release-engine').unlink(missing_ok=True)
        try:
            text=runner.run_fixture(profile,install,case,output,args.source/'Scripts/dev/fixtures/plugin-settings-wallpaper-native.qml',extra_env=dict(env,PHA_WALLPAPER_MODE=mode,PHA_WALLPAPER_BOUNDARY=boundary),extra_lint=tuple(sorted(dest.rglob('*.qml'))),timeout=120)
        except RuntimeError:
            log=(output/'runtime.log').read_text() if (output/'runtime.log').exists() else ''
            if not args.negative_control or wanted not in log or (output/'runtime.exit').read_text().strip()!='2': raise
            if any(word in log for word in ('TypeError:','ReferenceError:','SyntaxError:','Binding loop detected')): raise RuntimeError('control rejected for unrelated diagnostic')
            if json.loads((out/'persisted/edited.json').read_text())!=dict(status='PASS',values=edited): raise RuntimeError('wallpaper control lacks independent edited publication')
            rejected=True
        finally: (case/'release-engine').touch()
        if args.negative_control:
            if not rejected: raise RuntimeError('wallpaper native control escaped')
            break
        if 'WALLPAPER_NATIVE: PASS '+plugin+' '+scope+' '+mode+' '+boundary not in text: raise RuntimeError('wallpaper native incomplete')
        if any(word in text for word in ('TypeError:','ReferenceError:','SyntaxError:','Binding loop detected')): raise RuntimeError('wallpaper native diagnostic failure')
        if mode=='cold' and hashes(case)!=before: raise RuntimeError('cold wallpaper reader published')
    for boundary,value in ({} if rejected else {key:value for key,value in expected.items() if not args.caller_proof or key in ('initial','discarded','edited')}).items():
        if json.loads((out/('persisted/'+boundary+'.json')).read_text())!=dict(status='PASS',values=value): raise RuntimeError('complete native documents differ')
    rows=[json.loads(line) for line in (case/'requests.jsonl').read_text().splitlines()]
    for row in rows:
        stat=Path('/proc')/str(row['pid'])/'stat'; deadline=time.monotonic()+5
        while stat.exists() and stat.read_text().split(') ',1)[1].split()[19]==row['start']:
            if time.monotonic()>deadline: raise RuntimeError('native wallpaper endpoint survived')
            time.sleep(.02)
    shutil.copy2(case/'requests.jsonl',out/'requests.jsonl')
    if rejected:
        stage_receipt(out/'result.json',dict(status='PASS',plugin=plugin,scope=scope,kind=args.negative_control,rejectedAt=wanted,nativeEditedBoundary=True,inertActions=len(rows),physicalProof=False,completeGroupAcceptance=False))
    else:
        stage_receipt(out/'result.json',dict(status='PASS',plugin=plugin,scope=scope,actualPageAndEngine=True,completeNativeBoundaries=sorted(key for key in expected if not args.caller_proof or key in ('initial','discarded','edited')),nonpublishingColdReaders=[] if args.tool_origin or args.caller_proof else ['edited','reset','following'],inertActions=len(rows),physicalProof=False,completeGroupAcceptance=False))
    runner.remove_completed_installs(case,out); print('WALLPAPER_NATIVE '+plugin+' '+scope+': PASS',flush=True)


@receipt_run
def main():
    parser=argparse.ArgumentParser(description=__doc__); profile_argument(parser)
    for key in ('source','plugins','work-root','output'): parser.add_argument('--'+key,type=Path,required=True)
    parser.add_argument('--plugin',choices=('linux-wallpaperengine-controller','mpvpaper')); parser.add_argument('--scope',choices=('shared','instance'))
    parser.add_argument('--tool-origin',action='store_true',help='actual Settings Clear action without a registered runtime view')
    parser.add_argument('--negative-control',choices=('omitted-caller','shared-policy'))
    parser.add_argument('--caller-proof',action='store_true',help='positive instance play/reload admission witness paired to omitted-caller control')
    args=parser.parse_args(); profile=activate_profile(args.guest_profile); profile.prepare_roots()
    if args.tool_origin and args.plugin!='mpvpaper': parser.error('tool origin characterization requires mpvpaper')
    if (args.negative_control or args.caller_proof) and (not args.plugin or args.scope!='instance' or args.tool_origin): parser.error('caller controls require one instance-scope plugin and no tool-origin')
    if Path(__file__).resolve()!=args.source.resolve()/'Scripts/dev/plugin-settings-wallpaper-native-regression.py': parser.error('execute supplied source')
    for path,parent in ((args.work_root,profile.work_base),(args.output,profile.journal_base)):
        if path!=path.resolve() or path==parent or not path.is_relative_to(parent): parser.error('fresh owned guest roots required')
    with (profile.work_base/'.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB); args.work_root.mkdir(); args.output.mkdir()
        runner.write_json(args.output/'inputs.json',{str(p.relative_to(args.source)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (Path(__file__),args.source/'Scripts/dev/fixtures/plugin-settings-wallpaper-native.qml',args.source/'Scripts/dev/plugin-settings-wallpaper-runtime-regression.py',args.source/'Scripts/dev/fixtures/plugin-settings-query-disk.py')})
        for plugin in ((args.plugin,) if args.plugin else ('linux-wallpaperengine-controller','mpvpaper')):
            for scope in ((args.scope,) if args.scope else ('instance','shared')): run(args,profile,plugin,scope)
        stage_receipt(args.output/'result.json',dict(status='PASS',completeGroupAcceptance=False))


if __name__=='__main__': main()
