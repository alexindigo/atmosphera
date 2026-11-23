#!/usr/bin/env python3
"""Individual managed-service and inhibitor lifetimes against inert endpoints."""
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

spec = importlib.util.spec_from_file_location('resource', Path(__file__).with_name('plugin-settings-resource-native-regression.py'))
resource = importlib.util.module_from_spec(spec); spec.loader.exec_module(resource)
runner = resource.runner

INHIBITOR = '''#!/usr/bin/python3
import fcntl,json,os,signal,sys,time
from pathlib import Path
b=Path(os.environ['PHA_RESOURCE_CASE']);name=Path(sys.argv[0]).name;args=sys.argv[1:]
start=(Path('/proc')/str(os.getpid())/'stat').read_text().split(') ',1)[1].split()[19]
def record(kind):
 with (b/'requests.jsonl').open('a') as f:
  fcntl.flock(f,fcntl.LOCK_EX);f.write(json.dumps(dict(kind=kind,endpoint=name,argv=args,pid=os.getpid(),start=start))+'\\n');f.flush()
record('start')
if name=='which':raise SystemExit(0)
if name=='niri':
 if args==['msg','--json','outputs']:print(json.dumps({'eDP-1':{'modes':[{}],'current_mode':0},'HDMI-A-1':{'modes':[{}],'current_mode':0}}))
 elif args==['msg','--json','event-stream']:
  while True:time.sleep(.05)
 else:raise SystemExit('unreviewed niri '+repr(args))
elif name=='systemd-inhibit':
 def stop(*args):
  record('term')
  while (b/'hold-exit').exists() and not (b/'release-exit').exists():time.sleep(.02)
  raise SystemExit(0)
 signal.signal(signal.SIGTERM,stop)
 while True:time.sleep(.05)
else:raise SystemExit('unreviewed endpoint '+name)
'''


@receipt_run
def main():
    parser = argparse.ArgumentParser(description=__doc__); profile_argument(parser)
    for name in ('source', 'plugins', 'work-root', 'output'):
        parser.add_argument('--'+name, type=Path, required=True)
    parser.add_argument('--case', choices=('clamshell-original', 'clamshell-policy', 'clamshell-replacement', 'clamshell-retirement', 'agent-delay', 'agent-http', 'agent-failure', 'agent-retirement', 'agent-polling'), required=True)
    args = parser.parse_args(); profile = activate_profile(args.guest_profile); profile.prepare_roots()
    if Path(__file__).resolve() != args.source.resolve()/'Scripts/dev/plugin-settings-resource-lifetime-regression.py':
        parser.error('execute supplied source')
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent):
            parser.error('fresh owned guest roots required')
    with (profile.work_base/'.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB); args.work_root.mkdir(); args.output.mkdir()
        install = args.work_root/'install'
        shutil.copytree(args.source, install, copy_function=os.link, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
        resource.seed(args.work_root, args.plugins)
        shutil.copytree(args.plugins/'clamshell', args.work_root/'config/plugins/clamshell')
        for name in ('systemd-inhibit', 'niri', 'which'):
            path = args.work_root/'bin'/name; path.write_text(INHIBITOR); path.chmod(0o755)
        assigned = resource.ports()
        runner.write_json(args.work_root/'input.json', dict(ports=assigned))
        runner.write_json(args.output/'sources.json', {str(p.relative_to(args.plugins)): hashlib.sha256(p.read_bytes()).hexdigest() for name in ('agent-session-status', 'clamshell') for p in sorted((args.plugins/name).rglob('*')) if p.is_file()})
        runner.write_json(args.output/'inputs.json', {str(p.relative_to(args.source)): hashlib.sha256(p.read_bytes()).hexdigest() for p in (Path(__file__), Path(resource.__file__), args.source/'Scripts/dev/fixtures/plugin-settings-resource-lifetime.qml')})
        env = dict(PHA_RESOURCE_CASE=str(args.work_root), PHA_RESOURCE_TEST=args.case, HOME=str(args.work_root/'home'), PATH=str(args.work_root/'bin')+':'+os.environ['PATH'])
        text = runner.run_fixture(profile, install, args.work_root, args.output, args.source/'Scripts/dev/fixtures/plugin-settings-resource-lifetime.qml', extra_env=env, extra_lint=tuple(p for name in ('agent-session-status', 'clamshell') for p in sorted((args.work_root/'config/plugins'/name).glob('*.qml'))), timeout=100)
        if 'RESOURCE_LIFETIME: PASS '+args.case not in text:
            raise RuntimeError('incomplete resource lifetime')
        if any(word in text for word in ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected')):
            raise RuntimeError('resource lifetime diagnostic')
        shutil.copy2(args.work_root/'requests.jsonl', args.output/'requests.jsonl')
        rows = [json.loads(line) for line in (args.output/'requests.jsonl').read_text().splitlines()]
        if args.case == 'clamshell-original':
            assert not any(row.get('endpoint') == 'systemd-inhibit' and '--who=selected-who' in row['argv'] for row in rows), 'original selected inhibitor unexpectedly admitted'
        elif args.case.startswith('clamshell-'):
            assert any(row.get('endpoint') == 'systemd-inhibit' and '--who=selected-who' in row['argv'] for row in rows), 'selected policy reaches actual inhibitor argv'
        elif args.case != 'agent-retirement':
            assert any(row['kind'] == 'start' and row.get('port') == assigned[1] for row in rows), 'selected daemon argv'
        for _ in range(100):
            live = []
            for row in rows:
                try:
                    actual = (Path('/proc')/str(row['pid'])/'stat').read_text().split(') ', 1)[1].split()[19]
                except FileNotFoundError:
                    continue
                if actual == row['start']: live.append(row)
            if not live: break
            time.sleep(.02)
        if live: raise RuntimeError('live resource endpoints '+repr(live))
        stage_receipt(args.output/'result.json', dict(status='PASS', case=args.case, endpointRows=len(rows), allEndpointIdentitiesAbsent=True, physicalProof=False, nativeScopeProof=False))
        runner.remove_completed_installs(args.work_root, args.output)


if __name__ == '__main__':
    main()
