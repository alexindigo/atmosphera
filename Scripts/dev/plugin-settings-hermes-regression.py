#!/usr/bin/env python3
"""Actual Hermes scoped page/native owner and terminal consumers, inert SSH only."""
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

spec = importlib.util.spec_from_file_location('hermes_runner', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(spec); spec.loader.exec_module(runner)

STUB = '''#!/usr/bin/env python3
import fcntl, json, os, signal, struct, sys, termios, tty
from pathlib import Path
case = Path(os.environ['PHA_HERMES_CASE'])
target = sys.argv[-2]
def record(event, **values):
 row = dict(event=event, pid=os.getpid(), start=Path('/proc/self/stat').read_text().split(') ', 1)[1].split()[19], target=target, **values)
 fd = os.open(case / 'requests.jsonl', os.O_WRONLY | os.O_APPEND)
 os.write(fd, (json.dumps(row) + '\\n').encode()); os.close(fd)
def terminate(signum, frame):
 record('term'); sys.exit(0)
signal.signal(signal.SIGTERM, terminate)
rows, cols, _, _ = struct.unpack('HHHH', fcntl.ioctl(0, termios.TIOCGWINSZ, b'\\0' * 8))
tty.setraw(0)
record('start', argv=sys.argv[1:], rows=rows, cols=cols)
os.write(1, ('REMOTE_' + target + '\\r\\n').encode())
while True:
 data = os.read(0, 4096)
 if not data: break
 record('input', text=data.decode())
 os.write(1, ('INPUT_' + target + ':' + data.decode() + '\\r\\n').encode())
'''


def hashes(case):
    return {str(p.relative_to(case)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((case / 'config').rglob('*.json'))}


@receipt_run
def run(args, profile, scope):
    case, out = args.work_root / scope, args.output / scope
    case.mkdir(); out.mkdir(); (out / 'persisted').mkdir()
    install = case / 'install'
    shutil.copytree(args.source, install, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
    for part in ('config/settings/plugins', 'cache', 'state', 'bin', 'home'):
        (case / part).mkdir(parents=True)
    dest = case / 'config/plugins/hermes-ssh-chat'; shutil.copytree(args.plugins / 'hermes-ssh-chat', dest)
    (case / 'requests.jsonl').write_text('')
    executable = case / 'bin/ssh'; executable.write_text(STUB); executable.chmod(0o755)
    shared = dict(host='shared.invalid', user='shared-user', port=2222, autoConnectOnStartup=False, rememberLastTarget=True, showBarText=True, opaque=dict(keep='shared'))
    bar = dict(widgets=dict(left=[dict(id='plugin:hermes-ssh-chat', tag='selected', instanceSettings=dict(opaque=dict(keep='selected'))), dict(id='plugin:hermes-ssh-chat', tag='sibling', instanceSettings=dict(showBarText=True, host='sibling.invalid', opaque=dict(keep='sibling'))), dict(id='plugin:hermes-ssh-chat', tag='inherited', instanceSettings=dict(opaque=dict(keep='inherited')))]))
    initial = dict(shared=shared, bar=bar)
    edited = deepcopy(initial)
    (edited['shared'] if scope == 'shared' else edited['bar']['widgets']['left'][0]['instanceSettings'])['showBarText'] = False
    reset = deepcopy(edited)
    (reset['shared'] if scope == 'shared' else reset['bar']['widgets']['left'][0]['instanceSettings']).pop('showBarText')
    following = deepcopy(reset); following['shared']['showBarText'] = False
    expected = dict(initial=initial, discarded=initial, edited=edited, **{'reset-staged': edited}, reset=reset, following=following)
    remembered = deepcopy(initial)
    remembered['bar']['widgets']['left'][0]['instanceSettings'].update(host='first.invalid', port=2201, user='first-user')
    remembered['bar']['widgets']['left'][1]['instanceSettings'].update(host='second.invalid', port=2202, user='second-user')
    expected['remembered'] = remembered
    replaced = deepcopy(remembered)
    replaced['bar']['widgets']['left'][0]['instanceSettings'].update(host='replacement.invalid', port=2203, user='replacement-user')
    expected.update(replaced=replaced, retired=replaced)
    for path, value in [('input.json', dict(plugin='hermes-ssh-chat')), ('expectations.json', expected), ('config/settings.json', dict(settingsVersion=62)), ('config/plugins.json', dict(version=6, states={}, sources=[])), ('config/settings/plugins/hermes-ssh-chat.json', shared), ('config/settings/bar.json', bar)]: runner.write_json(case / path, value)
    wanted = 'original Bar child uses saved selected text policy' if args.old_red else None
    if args.control:
        name, old, new, wanted = {
            'shared-bar': ('BarWidget.qml', 'settingsConsumerFor(pluginApi.settingsContext)', 'settingsConsumerFor(mainInstance.pluginApi.settingsContext)', 'actual views share exact captured session'),
            'child': ('BarWidget.qml', 'visible: root.showBarText && !root.isVertical', 'visible: !root.isVertical', 'actual Bar text visibility uses selected policy'),
            'writer': ('HermesSession.qml', 'api.pluginSettings.host = host;', 'api.base.pluginSettings.host = host;', 'independent complete Hermes documents: remembered'),
            'terminal': ('TerminalView.qml', 'target: root.session', 'target: null', 'actual terminal child renders selected remote output'),
            'generation': ('HermesSession.qml', 'function handleMessage(connection, line) {\n    if (!acceptsConnection(connection)) return;', 'function handleMessage(connection, line) {\n    if (!current) return;', 'retired connection callback is fenced'),
            'auto-source': ('HermesSession.qml', 'generation === root._sourceGeneration', 'true', 'queued auto source replacement is fenced'),
            'source-replay': ('TerminalView.qml', 'onSessionChanged: Qt.callLater(replayBuffer)', 'onSessionChanged: {}', 'restored terminal replays only originating session buffer'),
            'retirement': ('HermesSession.qml', 'disconnect(); retire(root);', 'retire(root);', 'retirement'),
        }[args.control]
        path = dest / name; text = path.read_text()
        if text.count(old) != 1: raise RuntimeError('stale Hermes control')
        path.write_text(text.replace(old, new))
    env = dict(PHA_HERMES_SCOPE=scope, PHA_HERMES_CASE=str(case), PHA_HERMES_OUTPUT=str(out), PHA_HERMES_DISK=str(args.source / 'Scripts/dev/fixtures/plugin-settings-query-disk.py'), PHA_HERMES_CHILDREN=str(args.source / 'Scripts/dev/fixtures/plugin-settings-hermes-children.py'), PHA_HERMES_OLD_RED='1' if args.old_red else '0', HOME=str(case / 'home'), PATH=str(case / 'bin') + ':' + os.environ['PATH'])
    modes = [('life', '')] if args.lifetime else [('edit', ''), ('cold', 'edited'), ('reset', ''), ('cold', 'reset'), ('follow', ''), ('cold', 'following')]
    for mode, boundary in modes:
        output = out / (mode + ('-' + boundary if boundary else '')); output.mkdir(); before = hashes(case)
        try:
            text = runner.run_fixture(profile, install, case, output, args.source / 'Scripts/dev/fixtures/plugin-settings-hermes-native.qml', extra_env=dict(env, PHA_HERMES_MODE=mode, PHA_HERMES_BOUNDARY=boundary), extra_lint=tuple(sorted(dest.glob('*.qml'))), timeout=100)
        except RuntimeError:
            if not wanted or not (output / 'runtime.log').is_file() or wanted not in (output / 'runtime.log').read_text() or (output / 'runtime.exit').read_text().strip() != '2': raise
            if args.old_red and not (out / 'persisted/edited.json').is_file(): raise RuntimeError('Hermes red precedes native publication')
            result = dict(status='PASS', rejectedAt=wanted, originalRed=args.old_red, completePlanAcceptance=False)
            stage_receipt(out / 'result.json', result); runner.remove_completed_installs(case, out); return result
        if 'HERMES_NATIVE: PASS ' + scope + ' ' + mode not in text or any(x in text for x in ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected', 'HERMES_ASSERT:')): raise RuntimeError('Hermes consumer/diagnostic failure')
        if mode == 'cold' and hashes(case) != before: raise RuntimeError('Hermes cold reader published configuration')
        stage_receipt(output / 'observed.json', dict(status='PASS', configurationBefore=before, configurationAfter=hashes(case)))
    if wanted: raise RuntimeError('Hermes control escaped')
    life_boundaries = {'remembered', 'replaced', 'retired'}
    for boundary, value in [(key, value) for key, value in expected.items() if (key in life_boundaries) == args.lifetime]:
        if json.loads((out / ('persisted/' + boundary + '.json')).read_text()) != dict(status='PASS', values=value): raise RuntimeError('Hermes independent documents differ')
    shutil.copy2(case / 'requests.jsonl', out / 'requests.jsonl')
    rows = [json.loads(line) for line in (case / 'requests.jsonl').read_text().splitlines()]
    for row in rows:
        deadline = time.monotonic() + 4
        proc = Path('/proc') / str(row['pid']) / 'stat'
        while proc.exists() and proc.read_text().split(') ', 1)[1].split()[19] == row['start'] and time.monotonic() < deadline: time.sleep(0.02)
        if proc.exists() and proc.read_text().split(') ', 1)[1].split()[19] == row['start']: raise RuntimeError('actual SSH endpoint survived engine')
    result = dict(status='PASS', scope=scope, independentBoundaries=sorted(life_boundaries) if args.lifetime else sorted(set(expected) - life_boundaries), coldReaders=[] if args.lifetime else ['edited', 'reset', 'following'], lifetime=args.lifetime, endpointRows=len(rows), physicalProof=False, completePlanAcceptance=False)
    stage_receipt(out / 'result.json', result); runner.remove_completed_installs(case, out)
    print('HERMES_NATIVE ' + scope + ': PASS', flush=True); return result


@receipt_run
def main():
    parser = argparse.ArgumentParser(description=__doc__); profile_argument(parser)
    for key in ('source', 'plugins', 'work-root', 'output'): parser.add_argument('--' + key, type=Path, required=True)
    parser.add_argument('--scope', choices=('shared', 'instance'))
    oracle = parser.add_mutually_exclusive_group()
    oracle.add_argument('--old-red', action='store_true')
    oracle.add_argument('--control', choices=('shared-bar', 'child', 'writer', 'terminal', 'generation', 'auto-source', 'source-replay'))
    parser.add_argument('--lifetime', action='store_true')
    args = parser.parse_args()
    if args.old_red and args.lifetime: parser.error('original red requires the policy witness, not --lifetime')
    profile = activate_profile(args.guest_profile); profile.prepare_roots()
    if Path(__file__).resolve() != args.source.resolve() / 'Scripts/dev/plugin-settings-hermes-regression.py': parser.error('execute supplied source')
    if (args.old_red or args.control) and args.scope != 'instance': parser.error('explicit instance scope required')
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent): parser.error('fresh owned profile roots required')
    with (profile.work_base / '.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB); args.work_root.mkdir(); args.output.mkdir()
        paths = [Path(__file__), args.source / 'Scripts/dev/fixtures/plugin-settings-hermes-native.qml', args.source / 'Scripts/dev/fixtures/plugin-settings-hermes-children.py', args.source / 'Scripts/dev/fixtures/plugin-settings-query-disk.py']
        runner.write_json(args.output / 'inputs.json', dict(source=str(args.source), plugins=str(args.plugins), files={str(p.relative_to(args.source)): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}, pluginFiles={str(p.relative_to(args.plugins)): hashlib.sha256(p.read_bytes()).hexdigest() for p in (args.plugins / 'hermes-ssh-chat').rglob('*') if p.is_file()}))
        results = [run(args, profile, scope) for scope in ((args.scope,) if args.scope else ('instance', 'shared'))]
        stage_receipt(args.output / 'result.json', dict(status='PASS', cases=results, completePlanAcceptance=False))


if __name__ == '__main__': main()
