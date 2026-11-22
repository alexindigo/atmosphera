#!/usr/bin/env python3
"""Actual Music page/native ownership and inert playback-follow-up outcomes."""
import argparse
from copy import deepcopy
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
from guest_profile import activate_profile, profile_argument

spec = importlib.util.spec_from_file_location('content_runner', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)

HELPER = '''#!/usr/bin/env bash
set -eu
python3 - "$@" <<'PY'
import fcntl,json,os,sys,time
from pathlib import Path
b=Path(os.environ['PHA_CONTENT_CASE']);args=sys.argv[1:]
start=(Path('/proc')/str(os.getpid())/'stat').read_text().split(') ',1)[1].split()[19]
with (b/'requests.jsonl').open('a') as f:
 fcntl.flock(f,fcntl.LOCK_EX);f.write(json.dumps(dict(argv=args,pid=os.getpid(),start=start))+'\\n');f.flush()
if args[0]=='play':
 while (b/'hold-play').exists():time.sleep(.02)
 print(json.dumps(dict(isPlaying=True,id=args[1],title=args[2],url=args[3],uploader=args[4],duration=int(args[5]),updatedAt='1')))
elif args[0]=='status':print('{}')
elif args[0]=='download-mp3':print('/inert/download.mp3')
PY
'''

CLIP_ENDPOINT = '''#!/usr/bin/python3
import fcntl,json,os,sys
from pathlib import Path
b=Path(os.environ['PHA_CONTENT_CASE']);name=Path(sys.argv[0]).name
start=(Path('/proc')/str(os.getpid())/'stat').read_text().split(') ',1)[1].split()[19]
with (b/'requests.jsonl').open('a') as f:
 fcntl.flock(f,fcntl.LOCK_EX);f.write(json.dumps(dict(endpoint=name,argv=sys.argv[1:],pid=os.getpid(),start=start))+'\\n');f.flush()
if name=='which':print(str(b/'bin/wtype'))
elif name=='wl-paste':print('Selected text')
elif name=='cliphist' and sys.argv[1:2]==['list']:print('1\\tClipboard text')
'''


def hashes(case):
    return {str(p.relative_to(case)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((case/'config').rglob('*.json'))}


def run(args, profile, member, scope):
    case, out = args.work_root/(member+'-'+scope), args.output/(member+'-'+scope)
    case.mkdir(); out.mkdir(); (out/'persisted').mkdir()
    install = case/'install'
    shutil.copytree(args.source, install, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
    product = args.plugins/member
    dest = case/('config/plugins/'+member)
    shutil.copytree(product, dest)
    if args.original_plugins:
        shutil.copy2(args.original_plugins/member/'Main.qml', dest/'Main.qml')
    music = member == 'music-search'
    if music:
        (dest/'musicctl.sh').write_text(HELPER)
    for name in ('config/settings/plugins', 'home', 'cache', 'state'):
        (case/name).mkdir(parents=True)
    field = 'autoSaveMp3AfterPlayback' if music else 'autoPasteDelay'
    shared = {field: False if music else 800, 'opaque': 'shared'}
    if not music:
        shared['autoPaste'] = True  # Keep the actual delay control visible.
    bar = dict(widgets=dict(left=[dict(id='plugin:'+member, instanceSettings=row) for row in (dict(opaque='selected'), {field: False if music else 950, 'opaque':'sibling'}, dict(opaque='inherited'))]))
    initial = dict(shared=shared, bar=bar); edited = deepcopy(initial)
    (edited['shared'] if scope == 'shared' else edited['bar']['widgets']['left'][0]['instanceSettings'])[field] = True if music else 250
    reset = deepcopy(edited)
    (reset['shared'] if scope == 'shared' else reset['bar']['widgets']['left'][0]['instanceSettings']).pop(field)
    following = deepcopy(reset); following['shared'][field] = True if music else 500
    expected = dict(initial=initial, discarded=initial, edited=edited, **{'reset-staged': edited}, reset=reset, following=following)
    for name, value in [('input.json', dict(plugin=member)), ('expectations.json', expected), ('config/settings.json', dict(settingsVersion=62)), ('config/plugins.json', dict(version=6, states={}, sources=[])), ('config/settings/plugins/'+member+'.json', shared), ('config/settings/bar.json', bar)]:
        runner.write_json(case/name, value)
    (case/'requests.jsonl').write_text('')
    (case/'bin').mkdir()
    for name in ('cliphist','which','wtype','wl-copy','wl-paste'):
        path = case/'bin'/name; path.write_text(CLIP_ENDPOINT); path.chmod(0o755)
    content = case/'home/.config/noctalia/plugins/clipper'
    (content/'notecards').mkdir(parents=True)
    runner.write_json(content/'pinned.json',dict(items=[dict(id='pinned-1',content='Protected pin')]))
    runner.write_json(content/'notecards/retained.json',dict(id='retained',content='Protected note'))
    content_before = {str(p.relative_to(content)):hashlib.sha256(p.read_bytes()).hexdigest() for p in content.rglob('*.json')}
    runner.write_json(out/'sources.json', {str(p.relative_to(product)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(product.rglob('*')) if p.is_file()})
    env = dict(PHA_CONTENT_OMIT_ORIGIN='1' if args.omit_origin else '', PHA_CONTENT_PLUGIN=member, PHA_CONTENT_SCOPE=scope, PHA_CONTENT_CASE=str(case), PHA_CONTENT_OUTPUT=str(out), PHA_CONTENT_DISK=str(args.source/'Scripts/dev/fixtures/plugin-settings-query-disk.py'), HOME=str(case/'home'), MUSIC_CACHE_DIR=str(case/'cache'), PATH=str(case/'bin')+':'+os.environ['PATH'])
    controlled = args.original_plugins or args.omit_origin
    modes = [('edit', '')] if controlled else [('edit', ''), ('cold', 'edited'), ('reset', ''), ('cold', 'reset'), ('follow', ''), ('cold', 'following')]
    rejected = False
    for mode, boundary in modes:
        output = out/(mode+('-'+boundary if boundary else '')); output.mkdir(); before = hashes(case)
        try:
            text = runner.run_fixture(profile, install, case, output, args.source/'Scripts/dev/fixtures/plugin-settings-content-native.qml', extra_env=dict(env, PHA_CONTENT_MODE=mode, PHA_CONTENT_BOUNDARY=boundary), extra_lint=tuple(sorted(dest.rglob('*.qml'))), timeout=120)
        except RuntimeError:
            text = (output/'runtime.log').read_text()
            wanted = 'selected playback policy reaches download follow-up' if music else 'selected paste delay reaches actual Timer'
            if not controlled or wanted not in text or (output/'runtime.exit').read_text().strip() != '2':
                raise
            rejected = True
        if not rejected and 'CONTENT_NATIVE: PASS '+scope+' '+mode+' '+boundary not in text:
            raise RuntimeError('incomplete content native case')
        if any(word in text for word in ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected')):
            raise RuntimeError('content runtime diagnostics')
        after = hashes(case)
        runner.write_json(output/'configuration-hashes.json', dict(before=before, after=after, nonpublishing=before == after))
        if mode == 'cold' and after != before:
            raise RuntimeError('cold reader published')
    if controlled and not rejected:
        raise RuntimeError('original Main escaped')
    wanted_boundaries = ['initial', 'discarded', 'edited'] if rejected else list(expected)
    for name in wanted_boundaries:
        if json.loads((out/'persisted'/(name+'.json')).read_text()) != dict(status='PASS', values=expected[name]):
            raise RuntimeError('native complete documents differ: '+name)
    shutil.copy2(case/'requests.jsonl', out/'requests.jsonl')
    if {str(p.relative_to(content)):hashlib.sha256(p.read_bytes()).hexdigest() for p in content.rglob('*.json')} != content_before:
        raise RuntimeError('protected Clipper content changed')
    runner.write_json(out/'result.json', dict(status='PASS', plugin=member, scope=scope, protectedContent=content_before, kind=('omitted-origin-native' if args.omit_origin else 'original-native-red') if rejected else 'native', completeNativeBoundaries=wanted_boundaries, nonpublishingColdReaders=[] if rejected else ['edited', 'reset', 'following'], physicalProof=False, completeGroupAcceptance=False))
    runner.remove_completed_installs(case, out)


def main():
    parser = argparse.ArgumentParser(description=__doc__); profile_argument(parser)
    for name in ('source', 'plugins', 'work-root', 'output'):
        parser.add_argument('--'+name, type=Path, required=True)
    parser.add_argument('--scope', choices=('shared', 'instance'))
    parser.add_argument('--plugin', choices=('music-search','clipper'))
    parser.add_argument('--original-plugins', type=Path)
    parser.add_argument('--omit-origin', action='store_true')
    args = parser.parse_args(); profile = activate_profile(args.guest_profile); profile.prepare_roots()
    if Path(__file__).resolve() != args.source.resolve()/'Scripts/dev/plugin-settings-content-native-regression.py':
        parser.error('execute supplied source')
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent):
            parser.error('fresh owned guest roots required')
    with (profile.work_base/'.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB); args.work_root.mkdir(); args.output.mkdir()
        runner.write_json(args.output/'inputs.json', {str(p.relative_to(args.source)): hashlib.sha256(p.read_bytes()).hexdigest() for p in (Path(__file__), args.source/'Scripts/dev/fixtures/plugin-settings-content-native.qml', args.source/'Scripts/dev/fixtures/plugin-settings-query-disk.py')})
        for member in ((args.plugin,) if args.plugin else ('music-search','clipper')):
            for scope in ((args.scope,) if args.scope else ('instance', 'shared')):
                run(args, profile, member, scope)
        runner.write_json(args.output/'result.json', dict(status='PASS', completeGroupAcceptance=False))


if __name__ == '__main__':
    main()
