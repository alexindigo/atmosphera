#!/usr/bin/env python3
"""Controlled actual wallpaper Main/action consumers; not native acceptance."""
from fixture_receipts import receipt_run, stage_receipt
import argparse
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import time
from guest_profile import activate_profile, profile_argument

spec = importlib.util.spec_from_file_location('wallpaper_runner', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(spec); spec.loader.exec_module(runner)
ENDPOINT = '''#!/usr/bin/python3
import fcntl,json,os,sys,time
from pathlib import Path
base=Path(os.environ['PHA_WALLPAPER_CASE']);name=Path(sys.argv[0]).name;args=sys.argv[1:]
if name=='endpoint.py':name=args.pop(0)
start=(Path('/proc')/str(os.getpid())/'stat').read_text().split(') ',1)[1].split()[19]
def record(path):
 with (base/path).open('a') as stream:
  fcntl.flock(stream,fcntl.LOCK_EX);stream.write(json.dumps(dict(endpoint=name,argv=args,pid=os.getpid(),start=start))+'\\n');stream.flush()
record('requests.jsonl')
if name=='scan-wallpapers.sh':print(args[0]+'/controlled\\tControlled')
if name in ('linux-wallpaperengine','mpvpaper') and '--help' not in args and '--list-properties' not in args:
 deadline=time.monotonic()+25
 while not (base/'release-engine').exists():
  if time.monotonic()>deadline:
   record('expired-engines.jsonl')
   raise SystemExit('inert engine deadline')
  time.sleep(.02)
'''


def observe_browse(dest, plugin):
    # Trace admission at the request owner and settlement at the exact model's
    # destruction. Instrument only the fixture copy, not either plugin API.
    path = dest / ('Main.qml' if plugin == 'mpvpaper' else 'main/Functions.qml')
    source = path.read_text()
    model = 'required property string sourceFolder'
    admission = 'browseChoices = browseChoicesComponent.createObject(root, {sourceFolder: Settings.preprocessPath(pendingBrowse.folder)});'
    if source.count(model) != 1 or source.count(admission) != 1:
        raise RuntimeError('wallpaper browse observation points changed')
    result = source.replace(model, model + '\n            Component.onDestruction: root.pluginApi.recordBrowse("settled", sourceFolder)')
    result = result.replace(admission, admission + '\n        if (browseChoices) root.pluginApi.recordBrowse("admitted", {request: pendingBrowse, source: browseChoices.sourceFolder});')
    path.write_text(result)
    return dict(path=str(path.relative_to(dest)), sha256=hashlib.sha256(source.encode()).hexdigest(),
                reason='observe exact model admission and settlement; do not change browse behavior')


@receipt_run
def main():
    parser = argparse.ArgumentParser(description=__doc__); profile_argument(parser)
    for name in ('source', 'plugins', 'work-root', 'output'): parser.add_argument('--'+name, type=Path, required=True)
    parser.add_argument('--plugin', choices=('linux-wallpaperengine-controller', 'mpvpaper', 'video-wallpaper'), required=True)
    parser.add_argument('--original-plugins', type=Path)
    parser.add_argument('--browse',action='store_true',help='source-qualified runtime browse and retired pending request')
    args = parser.parse_args(); profile = activate_profile(args.guest_profile); profile.prepare_roots()
    if Path(__file__).resolve() != args.source.resolve()/'Scripts/dev/plugin-settings-wallpaper-runtime-regression.py': parser.error('execute supplied source')
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent): parser.error('fresh owned guest roots required')
    with (profile.work_base/'.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        case, out = args.work_root, args.output; case.mkdir(); out.mkdir()
        install = case/'install'; shutil.copytree(args.source, install, ignore=shutil.ignore_patterns('.git','.envrc','__pycache__'))
        product = (args.original_plugins or args.plugins)/args.plugin; dest = case/'plugin'; shutil.copytree(product, dest)
        for part in ('bin','home','config','cache','state','selected','shared'): (case/part).mkdir()
        if args.browse:
            if args.plugin=='linux-wallpaperengine-controller': parser.error('browse lifecycle belongs to MPV/Video')
            (case/'replacement').mkdir()
            (case/'selected/controlled.mp4').write_text('controlled inventory')
            (case/'shared/foreign.mp4').write_text('controlled foreign inventory')
            (case/'replacement/retired.mp4').write_text('controlled retired inventory')
        runner.write_json(case/'config/settings.json', dict(settingsVersion=62))
        runner.write_json(case/'config/plugins.json', dict(version=6, states={}, sources=[]))
        (case/'requests.jsonl').write_text(''); (case/'bin/endpoint.py').write_text(ENDPOINT)
        runner.write_json(out/'sources.json', {str(p.relative_to(product)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(product.rglob('*')) if p.is_file()})
        runner.write_json(out/'inputs.json', {str(p.relative_to(args.source)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (Path(__file__), args.source/'Scripts/dev/fixtures/plugin-settings-wallpaper-runtime.qml')})
        adapters = []
        if args.browse and not args.original_plugins:
            adapters.append(observe_browse(dest, args.plugin))
        for name in ('linux-wallpaperengine','mpvpaper','ffmpeg'):
            path=case/'bin'/name; path.write_text(ENDPOINT); path.chmod(0o755)
        if args.plugin == 'linux-wallpaperengine-controller':
            for name in ('force-stop-engine.sh','scan-wallpapers.sh','capture-wallpaper-colors.sh','check-file-exists.sh','update-noctalia-wallpapers-cache.sh'):
                path=dest/'scripts'/name
                adapters.append(dict(path=str(path.relative_to(dest)),sha256=hashlib.sha256(path.read_bytes()).hexdigest(),reason='inert literal argv endpoint; no physical wallpaper/kill/capture action'))
                path.write_text('#!/bin/sh\nexec python3 "$PHA_WALLPAPER_CASE/bin/endpoint.py" '+name+' "$@"\n'); path.chmod(0o755)
        runner.write_json(out/'adapters.json', adapters)
        expected = 'selected browse source and runtime writer' if args.browse else 'selected engine fps reaches inert endpoint' if args.plugin == 'linux-wallpaperengine-controller' else 'wallpaper action writes only its originating configuration'
        try:
            text=runner.run_fixture(profile,install,case,out,args.source/'Scripts/dev/fixtures/plugin-settings-wallpaper-runtime.qml',extra_env=dict(PHA_WALLPAPER_PLUGIN=args.plugin,PHA_WALLPAPER_CASE=str(case),PHA_WALLPAPER_BROWSE='1' if args.browse else '0',PHA_WALLPAPER_ORIGINAL='1' if args.original_plugins else '0',HOME=str(case/'home'),PATH=str(case/'bin')+':'+os.environ['PATH']),extra_lint=tuple(sorted(dest.rglob('*.qml'))),timeout=90)
        except RuntimeError:
            (case/'release-engine').touch()
            if not args.original_plugins or expected not in (out/'runtime.log').read_text() or (out/'runtime.exit').read_text().strip()!='2': raise
        else:
            if args.original_plugins: raise RuntimeError('original wallpaper control escaped')
            if 'WALLPAPER_RUNTIME: PASS '+args.plugin not in text: raise RuntimeError('wallpaper runtime incomplete')
            if any(word in text for word in ('TypeError:','ReferenceError:','SyntaxError:','Binding loop detected')): raise RuntimeError('wallpaper runtime diagnostics')
        (case/'release-engine').touch()
        rows=[json.loads(line) for line in (case/'requests.jsonl').read_text().splitlines()]
        for row in rows:
            path=Path('/proc')/str(row['pid'])/'stat'; deadline=time.monotonic()+5
            while path.exists() and path.read_text().split(') ',1)[1].split()[19]==row['start']:
                if time.monotonic()>deadline: raise RuntimeError('wallpaper endpoint survived')
                time.sleep(.02)
        shutil.copy2(case/'requests.jsonl',out/'requests.jsonl')
        stage_receipt(out/'result.json',dict(status='PASS',plugin=args.plugin,kind='original-red' if args.original_plugins else 'focused-runtime',rejectedAt=expected if args.original_plugins else None,nativeAcceptance=False,physicalProof=False,completeGroupAcceptance=False))
        runner.remove_completed_installs(case,out)


if __name__=='__main__': main()
