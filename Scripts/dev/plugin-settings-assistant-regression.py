#!/usr/bin/env python3
"""Real scoped Assistant controls, native documents and common-content consumers."""
from fixture_receipts import receipt_run, stage_receipt
from fixture_evidence import require
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

spec = importlib.util.spec_from_file_location('assistant_runner', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
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
    for part in ('config/settings/plugins', 'cache', 'state', 'bin'):
        (case/part).mkdir(parents=True)
    dest = case/'config/plugins/assistant-panel'
    shutil.copytree(args.plugins/'assistant-panel', dest)
    wanted = None
    if args.control:
        name, old, new, wanted = {
            'client': ('AiChatView.qml', 'settingsConsumerFor(pluginApi.settingsContext)', 'settingsConsumerFor(mainInstance.pluginApi.settingsContext)', 'selected chat model'),
            'child': ('AiChatView.qml', 'text: model', 'text: "wrong rendered model"', 'actual model child Text'),
            'response': ('MessageBubble.qml', 'text: message.content', 'text: "wrong rendered response"', 'actual assistant response child Text'),
        }[args.control]
        path = dest/name; text = path.read_text()
        require(text.count(old) == 1, name+' Assistant mutation anchor')
        path.write_text(text.replace(old, new))
    endpoint = case/'bin/curl'
    endpoint.write_text('''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
a=sys.argv[1:];url=a[-1]
with Path(os.environ['PHA_ASSISTANT_REQUESTS']).open('a') as f:f.write(json.dumps(a)+'\\n')
payload=json.loads(a[a.index('-d')+1]) if '-d' in a and a[a.index('-d')+1].startswith('{') else None
if payload and 'messages' in payload:
 print('data: '+json.dumps(dict(choices=[dict(delta=dict(content='reply-'+payload['model']))])),flush=True)
 print('data: [DONE]',flush=True)
elif payload and 'contents' in payload:
 print('data: '+json.dumps(dict(candidates=[dict(content=dict(parts=[dict(text='gemini-reply')]))])),flush=True)
elif 'deepl.com' in ' '.join(a):print(json.dumps(dict(translations=[dict(text='deepl-reply')])))
else:print(json.dumps([[['google-reply']]]))
''')
    endpoint.chmod(0o755)
    ai = dict(provider='openai_compatible', models=dict(openai_compatible='shared-model'), apiKeys={}, openaiLocal=True,
              openaiBaseUrl='http://inert.invalid/shared', temperature=0.7, systemPrompt='shared prompt')
    shared = dict(ai=ai, translator=dict(backend='google', sourceLanguage='auto', targetLanguage='en', realTimeTranslation=False),
                  maxHistoryLength=100, panelDetached=True, panelWidth=520, opaque=dict(keep='shared'))
    bar = dict(widgets=dict(left=[dict(id='plugin:assistant-panel', tag='selected', instanceSettings=dict(opaque=dict(keep='selected'))),
        dict(id='plugin:assistant-panel', tag='sibling', instanceSettings=dict(ai=dict(ai, models=dict(openai_compatible='sibling-model')), opaque=dict(keep='sibling'))),
        dict(id='plugin:assistant-panel', tag='inherited', instanceSettings=dict(opaque=dict(keep='inherited')))]))
    initial = dict(shared=shared, bar=bar); edited = deepcopy(initial)
    target = edited['shared'] if scope == 'shared' else edited['bar']['widgets']['left'][0]['instanceSettings']
    target.update(ai=dict(ai, models=dict(openai_compatible='selected-model'), model='selected-model', temperature=0), maxHistoryLength=20)
    reset = deepcopy(edited)
    for key in ('ai', 'maxHistoryLength'):
        (reset['shared'] if scope == 'shared' else reset['bar']['widgets']['left'][0]['instanceSettings']).pop(key)
    following = deepcopy(reset); following['shared'].update(ai=dict(ai, models=dict(openai_compatible='following-model')), maxHistoryLength=30)
    expected = dict(initial=initial, discarded=initial, edited=edited, **{'reset-staged': edited}, reset=reset, following=following)
    for name, value in [('input.json', dict(plugin='assistant-panel')), ('expectations.json', expected),
                        ('config/settings.json', dict(settingsVersion=62)), ('config/plugins.json', dict(version=6, states={}, sources=[])),
                        ('config/settings/plugins/assistant-panel.json', shared), ('config/settings/bar.json', bar)]:
        runner.write_json(case/name, value)
    env = dict(PATH=str(case/'bin')+os.pathsep+os.environ['PATH'], PHA_ASSISTANT_SCOPE=scope, PHA_ASSISTANT_CASE=str(case), PHA_ASSISTANT_OUTPUT=str(out),
               PHA_ASSISTANT_REQUESTS=str(case/'requests.jsonl'),
               PHA_ASSISTANT_DISK=str(args.source/'Scripts/dev/fixtures/plugin-settings-query-disk.py'), PHA_ASSISTANT_RED='1' if args.old_red else '0',
               NOCTALIA_AP_GOOGLE_API_KEY='', NOCTALIA_AP_OPENAI_COMPATIBLE_API_KEY='', NOCTALIA_AP_DEEPL_API_KEY='')
    for mode, boundary in [('edit', ''), ('cold', 'edited'), ('reset', ''), ('cold', 'reset'), ('follow', ''), ('cold', 'following')]:
        output = out/(mode+('-'+boundary if boundary else '')); output.mkdir(); before = hashes(case)
        try:
            text = runner.run_fixture(profile, install, case, output, args.source/'Scripts/dev/fixtures/plugin-settings-assistant-native.qml',
                extra_env=dict(env, PHA_ASSISTANT_MODE=mode, PHA_ASSISTANT_BOUNDARY=boundary),
                extra_lint=tuple(sorted(dest.rglob('*.qml'))), timeout=100)
        except RuntimeError:
            wanted = 'original model consumes saved selected configuration' if args.old_red else wanted
            if not wanted or not (output/'runtime.log').is_file() or wanted not in (output/'runtime.log').read_text() or (output/'runtime.exit').read_text().strip() != '2':
                raise
            if not (out/'persisted/edited.json').is_file():
                raise RuntimeError('assistant red preceded actual native publication')
            result = dict(status='PASS', originalRed=args.old_red, control=args.control, rejectedAt=wanted, completePlanAcceptance=False)
            stage_receipt(out/'result.json', result); runner.remove_completed_installs(case, out); return result
        if 'ASSISTANT_NATIVE: PASS '+scope+' '+mode not in text or any(v in text for v in ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected', 'ASSISTANT_ASSERT:')):
            raise RuntimeError('assistant consumer/diagnostic failure')
        if mode == 'cold' and hashes(case) != before:
            raise RuntimeError('assistant cold reader published')
        stage_receipt(output/'observed.json', dict(status='PASS', configurationBefore=before, configurationAfter=hashes(case)))
    if args.old_red or wanted:
        raise RuntimeError('assistant original red escaped')
    for boundary, value in expected.items():
        if json.loads((out/'persisted'/(boundary+'.json')).read_text()) != dict(status='PASS', values=value):
            raise RuntimeError('independent assistant documents: '+boundary)
    if scope == 'instance':
        rows = [json.loads(line) for line in (case/'requests.jsonl').read_text().splitlines()]
        payloads = [json.loads(a[a.index('-d')+1]) for a in rows if '-d' in a and 'messages' in json.loads(a[a.index('-d')+1])]
        require(any(p['model'] == 'selected-model' and p['temperature'] == 0 for p in payloads), 'selected actual literal request')
    result = dict(status='PASS', scope=scope, independentBoundaries=sorted(expected), coldReaders=['edited', 'reset', 'following'], physicalProof=False, completePlanAcceptance=False)
    stage_receipt(out/'result.json', result); runner.remove_completed_installs(case, out); return result


@receipt_run
def main():
    parser = argparse.ArgumentParser(description=__doc__); profile_argument(parser)
    for name in ('source', 'plugins', 'work-root', 'output'):
        parser.add_argument('--'+name, type=Path, required=True)
    parser.add_argument('--scope', choices=('instance', 'shared'))
    oracle = parser.add_mutually_exclusive_group()
    oracle.add_argument('--old-red', action='store_true')
    oracle.add_argument('--control', choices=('client', 'child', 'response'))
    args = parser.parse_args(); profile = activate_profile(args.guest_profile); profile.prepare_roots()
    if Path(__file__).resolve() != args.source.resolve()/'Scripts/dev/plugin-settings-assistant-regression.py': parser.error('execute supplied source')
    if (args.old_red or args.control) and args.scope != 'instance': parser.error('explicit instance red required')
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent): parser.error('fresh owned guest roots required')
    with (profile.work_base/'.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB); args.work_root.mkdir(); args.output.mkdir()
        inputs = [Path(__file__), args.source/'Scripts/dev/fixtures/plugin-settings-assistant-native.qml', args.source/'Scripts/dev/fixtures/plugin-settings-query-disk.py']
        runner.write_json(args.output/'inputs.json', dict(source=str(args.source), plugins=str(args.plugins), files={str(p.relative_to(args.source)): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs},
            pluginFiles={str(p.relative_to(args.plugins)): hashlib.sha256(p.read_bytes()).hexdigest() for p in (args.plugins/'assistant-panel').rglob('*') if p.is_file()}))
        rows = [run(args, profile, scope) for scope in ((args.scope,) if args.scope else ('instance', 'shared'))]
        stage_receipt(args.output/'result.json', dict(status='PASS', cases=rows, completePlanAcceptance=False))


if __name__ == '__main__':
    main()
