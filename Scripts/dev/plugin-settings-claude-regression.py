#!/usr/bin/env python3
"""Scoped Claude pages/native documents and inert ACP wire consumers."""
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
from guest_profile import activate_profile, profile_argument

spec = importlib.util.spec_from_file_location('claude_runner', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


def hashes(case):
    return {str(p.relative_to(case)): hashlib.sha256(p.read_bytes()).hexdigest() for p in (case/'config').rglob('*.json')}


@receipt_run
def run(args, profile, scope):
    case, out = args.work_root/scope, args.output/scope
    case.mkdir(); out.mkdir(); (out/'persisted').mkdir()
    install = case/'install'
    shutil.copytree(args.source, install, copy_function=os.link, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
    for part in ('config/settings/plugins', 'cache', 'state', 'bin', 'home', 'shared', 'selected', 'sibling', 'following'):
        (case/part).mkdir(parents=True)
    dest = case/'config/plugins/claude-code-panel'
    shutil.copytree(args.plugins/'claude-code-panel', dest)
    wanted = None
    if args.control:
        name, old, new, wanted = {
            'client': ('Panel.qml', 'settingsConsumerFor(pluginApi.settingsContext)', 'settingsConsumerFor(mainInstance.pluginApi.settingsContext)', 'selected Panel working directory'),
            'child': ('Panel.qml', 'var wd = settingsConsumer?.workingDir || ""', 'var wd = "wrong rendered cwd"', 'actual cwd child Text'),
        }[args.control]
        path = dest/name; text = path.read_text(); assert text.count(old) == 1
        path.write_text(text.replace(old, new))
    endpoint = case/'bin/claude-code-acp'
    endpoint.write_text('''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
log=Path(os.environ['PHA_CLAUDE_REQUESTS'])
def record(event):
 with log.open('a') as f:f.write(json.dumps(dict(pid=os.getpid(),cwd=os.getcwd(),event=event))+'\\n')
def send(value):print(json.dumps(dict(jsonrpc='2.0',**value)),flush=True)
record(dict(start=True))
for line in sys.stdin:
 m=json.loads(line);record(m)
 if m.get('method')=='initialize':send(dict(id=m['id'],result=dict(protocolVersion=1)))
 elif m.get('method')=='session/new':send(dict(id=m['id'],result=dict(sessionId='inert-'+str(os.getpid()))))
 elif m.get('method')=='session/prompt':
  send(dict(method='session/update',params=dict(sessionId=m['params']['sessionId'],update=dict(sessionUpdate='agent_message_chunk',content=dict(type='text',text='reply:'+os.getcwd())))))
  send(dict(id=m['id'],result=dict(stopReason='end_turn')))
''')
    endpoint.chmod(0o755)
    claude = dict(binary='claude', workingDir=str(case/'shared'), appendSystemPrompt='shared prefix', injectNoctaliaContext=False, permissionMode='default')
    shared = dict(claude=claude, maxHistoryLength=200, panelDetached=True, panelWidth=620, opaque=dict(keep='shared'))
    bar = dict(widgets=dict(left=[dict(id='plugin:claude-code-panel', tag='selected', instanceSettings=dict(opaque=dict(keep='selected'))),
        dict(id='plugin:claude-code-panel', tag='sibling', instanceSettings=dict(claude=dict(claude, workingDir=str(case/'sibling'), permissionMode='plan'), opaque=dict(keep='sibling'))),
        dict(id='plugin:claude-code-panel', tag='inherited', instanceSettings=dict(opaque=dict(keep='inherited')))]))
    initial = dict(shared=shared, bar=bar); edited = deepcopy(initial)
    target = edited['shared'] if scope == 'shared' else edited['bar']['widgets']['left'][0]['instanceSettings']
    target.update(claude=dict(claude, workingDir=str(case/'selected')), panelWidth=700)
    reset = deepcopy(edited)
    for key in ('claude', 'panelWidth'):
        (reset['shared'] if scope == 'shared' else reset['bar']['widgets']['left'][0]['instanceSettings']).pop(key)
    following = deepcopy(reset); following['shared'].update(claude=dict(claude, workingDir=str(case/'following')), panelWidth=720)
    expected = dict(initial=initial, discarded=initial, edited=edited, **{'reset-staged': edited}, reset=reset, following=following)
    for name, value in [('input.json', dict(plugin='claude-code-panel')), ('expectations.json', expected),
                        ('config/settings.json', dict(settingsVersion=62)), ('config/plugins.json', dict(version=6, states={}, sources=[])),
                        ('config/settings/plugins/claude-code-panel.json', shared), ('config/settings/bar.json', bar)]:
        runner.write_json(case/name, value)
    env = dict(PATH=str(case/'bin')+os.pathsep+os.environ['PATH'], HOME=str(case/'home'), PHA_CLAUDE_SCOPE=scope, PHA_CLAUDE_CASE=str(case), PHA_CLAUDE_OUTPUT=str(out),
               PHA_CLAUDE_REQUESTS=str(case/'requests.jsonl'), PHA_CLAUDE_DISK=str(args.source/'Scripts/dev/fixtures/plugin-settings-query-disk.py'),
               PHA_CLAUDE_RED='1' if args.old_red else '0')
    for mode, boundary in [('edit', ''), ('cold', 'edited'), ('reset', ''), ('cold', 'reset'), ('follow', ''), ('cold', 'following')]:
        output = out/(mode+('-'+boundary if boundary else '')); output.mkdir(); before = hashes(case)
        try:
            text = runner.run_fixture(profile, install, case, output, args.source/'Scripts/dev/fixtures/plugin-settings-claude-native.qml',
                extra_env=dict(env, PHA_CLAUDE_MODE=mode, PHA_CLAUDE_BOUNDARY=boundary), extra_lint=tuple(sorted(dest.rglob('*.qml'))), timeout=100)
        except RuntimeError:
            wanted = 'original Panel consumes saved selected working directory' if args.old_red else wanted
            if not wanted or not (output/'runtime.log').is_file() or wanted not in (output/'runtime.log').read_text() or (output/'runtime.exit').read_text().strip() != '2':
                raise
            if not (out/'persisted/edited.json').is_file():
                raise RuntimeError('Claude red preceded actual native publication')
            result = dict(status='PASS', originalRed=args.old_red, control=args.control, rejectedAt=wanted, completePlanAcceptance=False)
            stage_receipt(out/'result.json', result); runner.remove_completed_installs(case, out); return result
        if 'CLAUDE_NATIVE: PASS '+scope+' '+mode not in text or any(v in text for v in ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected', 'CLAUDE_ASSERT:')):
            raise RuntimeError('Claude consumer/diagnostic failure')
        if mode == 'cold' and hashes(case) != before:
            raise RuntimeError('Claude cold reader published')
        stage_receipt(output/'observed.json', dict(status='PASS', configurationBefore=before, configurationAfter=hashes(case)))
    if args.old_red or wanted:
        raise RuntimeError('Claude original red escaped')
    for boundary, value in expected.items():
        if json.loads((out/'persisted'/(boundary+'.json')).read_text()) != dict(status='PASS', values=value):
            raise RuntimeError('independent Claude documents: '+boundary)
    rows = [json.loads(line) for line in (case/'requests.jsonl').read_text().splitlines()]
    for boundary in ('edited', 'reset', 'following'):
        cfg = dict(args.defaults); cfg.update(expected[boundary]['shared'])
        if scope == 'instance': cfg.update(expected[boundary]['bar']['widgets']['left'][0]['instanceSettings'])
        cwd = cfg['claude'].get('workingDir') or str(case/'home')
        assert any(r['event'].get('method') == 'session/new' and r['event']['params']['cwd'] == cwd and r['cwd'] == cwd for r in rows), 'actual captured ACP cwd '+boundary
    result = dict(status='PASS', scope=scope, independentBoundaries=sorted(expected), coldReaders=['edited', 'reset', 'following'], physicalProof=False, completePlanAcceptance=False)
    stage_receipt(out/'result.json', result); runner.remove_completed_installs(case, out); return result


@receipt_run
def main():
    parser = argparse.ArgumentParser(description=__doc__); profile_argument(parser)
    for name in ('source', 'plugins', 'work-root', 'output'):
        parser.add_argument('--'+name, type=Path, required=True)
    parser.add_argument('--scope', choices=('instance', 'shared')); parser.add_argument('--old-red', action='store_true')
    parser.add_argument('--control', choices=('client', 'child'))
    args = parser.parse_args(); profile = activate_profile(args.guest_profile); profile.prepare_roots()
    args.defaults = json.loads((args.plugins/'claude-code-panel/manifest.json').read_text())['metadata']['defaultSettings']
    if Path(__file__).resolve() != args.source.resolve()/'Scripts/dev/plugin-settings-claude-regression.py': parser.error('execute supplied source')
    if (args.old_red or args.control) and args.scope != 'instance': parser.error('explicit instance red required')
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent): parser.error('fresh owned guest roots required')
    with (profile.work_base/'.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB); args.work_root.mkdir(); args.output.mkdir()
        inputs = [Path(__file__), args.source/'Scripts/dev/fixtures/plugin-settings-claude-native.qml', args.source/'Scripts/dev/fixtures/plugin-settings-query-disk.py']
        runner.write_json(args.output/'inputs.json', dict(source=str(args.source), plugins=str(args.plugins), files={str(p.relative_to(args.source)): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs},
            pluginFiles={str(p.relative_to(args.plugins)): hashlib.sha256(p.read_bytes()).hexdigest() for p in (args.plugins/'claude-code-panel').rglob('*') if p.is_file()}))
        rows = [run(args, profile, scope) for scope in ((args.scope,) if args.scope else ('instance', 'shared'))]
        stage_receipt(args.output/'result.json', dict(status='PASS', cases=rows, completePlanAcceptance=False))


if __name__ == '__main__':
    main()
