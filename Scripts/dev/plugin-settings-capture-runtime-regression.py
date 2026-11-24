#!/usr/bin/env python3
"""Controlled capture admission/lifetime characterization, not native acceptance."""
from fixture_receipts import receipt_run, stage_receipt
import argparse
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import struct
import time
import zlib

from guest_profile import activate_profile, profile_argument

spec = importlib.util.spec_from_file_location('capture_runner', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)

ENDPOINT = '''#!/usr/bin/python3
import fcntl,json,os,sys,time
from pathlib import Path
base=Path(os.environ['PHA_CAPTURE_CASE']);name=Path(sys.argv[0]).name;args=sys.argv[1:]
if name=='endpoint.py':name=args.pop(0)
if name=='pidof':
 deadline=time.monotonic()+20
 while args==['xdg-desktop-portal'] and (base/'hold-portal').exists() or args==['wf-recorder'] and (base/'hold-pidof').exists():
  if time.monotonic()>deadline:raise SystemExit('inert portal deadline')
  time.sleep(.02)
 raise SystemExit(1 if args==['wf-recorder'] else 0)
if name in ('tesseract','which'):raise SystemExit(1)
payload=sys.stdin.read() if name=='wl-copy' else ''
start=(Path('/proc')/str(os.getpid())/'stat').read_text().split(') ',1)[1].split()[19]
with (base/'requests.jsonl').open('a') as stream:
 fcntl.flock(stream,fcntl.LOCK_EX);stream.write(json.dumps(dict(endpoint=name,argv=args,pid=os.getpid(),start=start,stdin=payload))+'\\n');stream.flush()
if name=='gpu-screen-recorder':
 marker='release-replay' if '-r' in args else 'release-recorder'
 deadline=time.monotonic()+20
 emitted=0
 while not (base/marker).exists():
  if time.monotonic()>deadline:raise SystemExit('inert recorder deadline')
  if '-r' in args and os.environ.get('PHA_CAPTURE_COMPLETION')=='1' and emitted<2 and (base/('emit-replay-'+str(emitted+1))).exists():
   emitted+=1;print(str(base/('controlled-replay-'+str(emitted)+'.mp4')),flush=True)
  time.sleep(.02)
if name=='measure.sh':print(str(base/'selected/controlled.png'))
if name=='share-upload.sh':print('https://controlled.invalid/capture')
if name=='wl-screenrec':
 Path(args[args.index('-f')+1]).write_text('controlled recording')
 deadline=time.monotonic()+20
 while not (base/'release-recorder').exists():
  if time.monotonic()>deadline:raise SystemExit('inert toolkit recorder deadline')
  time.sleep(.02)
if name=='record.sh' and args[0].startswith('convert-'):Path(args[2]).write_text('controlled conversion')
if name=='annotate.sh':
 if args[0]=='save':Path(args[2]).parent.mkdir(parents=True,exist_ok=True);Path(args[2]).write_text('controlled annotation');print(args[2])
if name=='hyprctl':print('[]')
if name=='swaymsg':print('{"nodes":[]}')
'''


@receipt_run
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    profile_argument(parser)
    for key in ('source', 'plugins', 'work-root', 'output'):
        parser.add_argument('--' + key, type=Path, required=True)
    parser.add_argument('--plugin', choices=('screen-recorder', 'screen-shot-and-record', 'screen-toolkit'), required=True)
    parser.add_argument('--original-plugins', type=Path)
    parser.add_argument('--shared-control', action='store_true')
    parser.add_argument('--lifetime', choices=('measure-replacement', 'annotate-zoom', 'annotate-share', 'annotate-save', 'mirror', 'record', 'record-retirement'))
    parser.add_argument('--expect-rejection', action='store_true')
    parser.add_argument('--recorder-completion', action='store_true')
    parser.add_argument('--selector-variant', choices=('default', 'hypr', 'sway'), default='default')
    parser.add_argument('--retired-selector', action='store_true')
    parser.add_argument('--retired-preflight', action='store_true')
    args = parser.parse_args()
    if args.lifetime and args.plugin != 'screen-toolkit': parser.error('overlay lifetime requires Toolkit')
    if args.recorder_completion and args.plugin != 'screen-recorder': parser.error('recorder completion requires Recorder')
    if args.expect_rejection and args.lifetime not in ('measure-replacement', 'annotate-zoom', 'record', 'mirror'): parser.error('only characterized candidate defects may be red')
    profile = activate_profile(args.guest_profile)
    profile.prepare_roots()
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent):
            parser.error('fresh owned guest roots required')
    with (profile.work_base/'.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        case, out = args.work_root, args.output
        case.mkdir(); out.mkdir()
        install = case/'install'
        shutil.copytree(args.source, install, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
        dest = case/'plugin'
        product = (args.original_plugins or args.plugins)/args.plugin
        shutil.copytree(product, dest, ignore=shutil.ignore_patterns('*.bak'))
        for part in ('bin', 'home', 'config', 'cache', 'state'):
            (case/part).mkdir()
        (case/'bin/endpoint.py').write_text(ENDPOINT)
        runner.write_json(case/'config/settings.json', dict(settingsVersion=62))
        runner.write_json(case/'config/plugins.json', dict(version=6, states={}, sources=[]))
        (case/'requests.jsonl').write_text('')
        (case/'hold-portal').touch()
        if args.retired_preflight: (case/'hold-pidof').touch()
        def chunk(tag, data):
            return struct.pack('!I', len(data))+tag+data+struct.pack('!I', zlib.crc32(tag+data))
        (case/'synthetic.png').write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR', struct.pack('!IIBBBBB', 1, 1, 8, 6, 0, 0, 0))+chunk(b'IDAT', zlib.compress(b'\0\xff\0\0\xff'))+chunk(b'IEND', b''))
        inputs = {str(p.relative_to(product)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(product.rglob('*')) if p.is_file() and p.suffix != '.bak'}
        runner.write_json(out/'sources.json', inputs)
        runner.write_json(out/'inputs.json', {str(path.relative_to(args.source)):hashlib.sha256(path.read_bytes()).hexdigest() for path in (Path(__file__), args.source/'Scripts/dev/fixtures/plugin-settings-capture-runtime.qml', args.source/'Scripts/dev/fixtures/plugin-settings-capture-overlays.qml')})
        adapters = []
        if args.shared_control:
            path = dest/'Main.qml'; text = path.read_text()
            old, new = 'const settings = context.settingsView', 'const settings = pluginApi.pluginSettings'
            if text.count(old) != 1: raise RuntimeError('review shared policy control')
            path.write_text(text.replace(old, new))
        if args.plugin == 'screen-shot-and-record':
            path = dest/'Main.qml'; text = path.read_text()
            old = 'if (CompositorService.isNiri)'
            if text.count(old) != 1: raise RuntimeError('review compositor adapter')
            path.write_text(text.replace(old, 'if (false)'))
            adapters.append(dict(path='Main.qml', old=old, new='if (false)', reason='inert supported-selector branch on the niri test compositor'))
            if args.selector_variant != 'default':
                old = 'CompositorService.isSway ? "ScreenShotSway.qml"\n                                           : CompositorService.isHyprland ? "ScreenShotHypr.qml"\n                                           : "ScreenShot.qml"'
                new = '"ScreenShot'+('Hypr' if args.selector_variant == 'hypr' else 'Sway')+'.qml"'
                text = path.read_text()
                if text.count(old) != 1: raise RuntimeError('review selector variant adapter')
                path.write_text(text.replace(old,new)); adapters.append(dict(path='Main.qml',old=old,new=new,reason='actual supported selector with inert compositor command collaborator'))
            endpoint = dest/'record.sh'; endpoint.write_text('#!/bin/sh\nexec python3 "$PHA_CAPTURE_CASE/bin/endpoint.py" record.sh "$@"\n'); endpoint.chmod(0o755)
        elif args.plugin == 'screen-toolkit':
            endpoint = dest/'scripts/measure.sh'; endpoint.write_text('#!/bin/sh\nexec python3 "$PHA_CAPTURE_CASE/bin/endpoint.py" measure.sh "$@"\n'); endpoint.chmod(0o755)
            if args.lifetime:
                for name in ('record.sh', 'annotate.sh', 'share-upload.sh', 'mirror-screenshot.sh', 'mirror-record.sh'):
                    endpoint = dest/'scripts'/name
                    endpoint.write_text('#!/bin/sh\nexec python3 "$PHA_CAPTURE_CASE/bin/endpoint.py" '+name+' "$@"\n'); endpoint.chmod(0o755)
                path = dest/'overlays/Mirror.qml'; text = path.read_text()
                old = 'active: root._cameraActive && win.isPrimary'
                if text.count(old) != 1: raise RuntimeError('review inert camera loader adapter')
                path.write_text(text.replace(old, 'active: false'))
                adapters.append(dict(path='overlays/Mirror.qml', old=old, new='active: false', reason='no real camera activation; fixture injects inert capture/recorder collaborators'))
        for name in ('gpu-screen-recorder', 'pidof', 'tesseract', 'which', 'wl-copy', 'xdg-open', 'wl-screenrec', 'magick', 'hyprctl', 'swaymsg'):
            endpoint = case/'bin'/name; endpoint.write_text(ENDPOINT); endpoint.chmod(0o755)
        runner.write_json(out/'adapters.json', adapters)
        control = bool(args.original_plugins) or args.shared_control or args.expect_rejection
        expected = {'screen-recorder': 'selected frame rate reaches inert recorder', 'screen-shot-and-record': 'selected recording folder reaches actual inert helper', 'screen-toolkit': 'retained selected path reaches actual inert measure helper'}[args.plugin]
        if args.expect_rejection:
            expected = {'measure-replacement': 'held measure cannot borrow replacement policy', 'annotate-zoom': 'annotation zoom restore retains its admitted policy', 'record': 'screen admission cannot be overwritten before its callback', 'mirror': 'retired mirror completions do not announce selected results'}[args.lifetime]
        # Original and shared-input controls must reach the actual effect
        # endpoint, not reject only because the old code lacks a new property.
        try:
            fixture = 'plugin-settings-capture-overlays.qml' if args.lifetime else 'plugin-settings-capture-runtime.qml'
            text = runner.run_fixture(profile, install, case, out, args.source/'Scripts/dev/fixtures'/fixture, extra_env=dict(PHA_CAPTURE_PLUGIN=args.plugin, PHA_CAPTURE_CASE=str(case), PHA_CAPTURE_ORIGINAL='1' if control else '0', PHA_CAPTURE_LIFETIME=args.lifetime or '', PHA_CAPTURE_COMPLETION='1' if args.recorder_completion else '0', PHA_CAPTURE_RETIRED_SELECTOR='1' if args.retired_selector else '0', PHA_CAPTURE_RETIRED_PREFLIGHT='1' if args.retired_preflight else '0', HOME=str(case/'home'), PATH=str(case/'bin')+':'+os.environ['PATH']), extra_lint=tuple(sorted(dest.rglob('*.qml'))), timeout=90)
        except RuntimeError:
            for marker in ('release-recorder', 'release-replay'):
                (case/marker).touch()
            text = (out/'runtime.log').read_text()
            if not control or expected not in text or (out/'runtime.exit').read_text().strip() != '2': raise
        else:
            if control: raise RuntimeError('capture control escaped')
            marker = 'CAPTURE_OVERLAY: PASS '+args.lifetime if args.lifetime else 'CAPTURE_RUNTIME: PASS '+args.plugin
            if marker not in text: raise RuntimeError('capture runtime did not finish')
            if any(word in text for word in ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected')): raise RuntimeError('capture runtime diagnostic failure')
        rows = [json.loads(line) for line in (case/'requests.jsonl').read_text().splitlines()]
        for row in rows:
            path = Path('/proc')/str(row['pid'])/'stat'
            deadline = time.monotonic() + 5
            while path.exists() and path.read_text().split(') ', 1)[1].split()[19] == row['start']:
                if time.monotonic() > deadline: raise RuntimeError('capture endpoint survived')
                time.sleep(.02)
        shutil.copy2(case/'requests.jsonl', out/'requests.jsonl')
        if not control and args.lifetime in ('record', 'annotate-save'):
            files = sorted((case/'selected').glob('*'))
            wanted = 'controlled conversion' if args.lifetime == 'record' else 'controlled annotation'
            if not files or any(path.read_text() != wanted for path in files): raise RuntimeError('independent captured output byte check failed')
            runner.write_json(out/'saved-output.json', {str(path.relative_to(case)):hashlib.sha256(path.read_bytes()).hexdigest() for path in files})
        stage_receipt(out/'result.json', dict(status='PASS', plugin=args.plugin, lifetime=args.lifetime, kind='candidate-red' if args.expect_rejection else 'original-red' if args.original_plugins else 'shared-input-control' if args.shared_control else 'focused-runtime', rejectedAt=expected if control else None, nativeAcceptance=False, physicalProof=False, completeGroupAcceptance=False))
        runner.remove_completed_installs(case, out)


if __name__ == '__main__':
    main()
