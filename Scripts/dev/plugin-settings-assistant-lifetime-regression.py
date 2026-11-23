#!/usr/bin/env python3
"""Finite real Assistant lifetimes with synthetic responses (no external calls)."""
import argparse
from contextlib import contextmanager
from copy import deepcopy
import fcntl
import hashlib
from http.server import BaseHTTPRequestHandler, HTTPServer
import importlib.util
import json
import os
from pathlib import Path
import shutil
from fixture_resources import FixtureResources
from guest_profile import activate_profile, profile_argument

spec = importlib.util.spec_from_file_location('assistant_runner', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(spec); spec.loader.exec_module(runner)
HTTP_BODIES = {
    'chat-http': b'data: {"choices":[{"delta":{"content":"reply-selected-model"}}]}\n\n',
    'http-empty': b'',
    'http-provider-error': b'{"error":{"message":"synthetic rejection"}}',
    'http-stream': b'data: {"choices":[{"delta":{"content":"not a reply"}}]}\n\n',
    'translation-http': b'{"translations":[{"text":"not a translation"}]}',
}
MODES = ('chat', 'gemini', 'environment', 'edit', 'translation-google', 'translation-deepl', 'translation-environment', 'translation-replace', 'cache', 'replace', 'retired', 'native-retired', 'stop', 'clear', 'destroyed', 'start-failure', *HTTP_BODIES)


@contextmanager
def local_response(mode, out):
    if mode not in HTTP_BODIES:
        yield {}
        return

    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            self.rfile.read(int(self.headers.get('Content-Length', '0')))
            body = HTTP_BODIES[mode]
            status = 200 if mode == 'chat-http' else 401
            self.send_response(status)
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            runner.write_json(out/'http.json', dict(status=status, body=body.decode()))

        def log_message(self, *args):
            pass

    with FixtureResources() as resources:
        server = resources.serve(HTTPServer(('127.0.0.1', 0), Handler))
        yield dict(PHA_ASSISTANT_HTTP=f'http://127.0.0.1:{server.server_port}/fixture', PHA_REAL_CURL=shutil.which('curl'))


def run(args, profile, mode):
    case, out = args.work_root/mode, args.output/mode
    case.mkdir(); out.mkdir()
    install = case/'install'
    shutil.copytree(args.source, install, copy_function=os.link, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
    for part in ('config/settings/plugins', 'cache/plugins/assistant-panel', 'state', 'bin'):
        (case/part).mkdir(parents=True)
    dest = case/'config/plugins/assistant-panel'; shutil.copytree(args.plugins/'assistant-panel', dest)
    wanted = None
    if args.control:
        name,old,new,wanted = {
            'origin': ('Main.qml','_consumer(context)?.captureChat()','_consumer(undefined)?.captureChat()','captured provider stream reaches common conversation'),
            'retirement': ('Main.qml','if ((kind === "all" || kind === "chat") && _chatRequest?.policy.context === client.settingsContext) _cancelChat(false);','/* deliberately omit common request retirement */','request generation settled after source/owner/action change'),
            'cache': ('Main.qml','_conversation = {messages: next, historyLimit: limit}', '_conversation = {messages: next, historyLimit: settingsConsumer.maxHistoryLength}', 'debounced cache retains captured limit, common content not truncated'),
            'parser': ('Main.qml','ProviderLogic.parseTranslateResponse(worker.policy.backend, output)','ProviderLogic.parseTranslateResponse(root.translatorBackend, output)','captured selected translation backend/parser'),
        }[args.control]
        path=dest/name;text=path.read_text();assert old in text;path.write_text(text.replace(old,new))
    # Fixture is copied into the install root; keep its original relative JS import valid.
    fixture = install/'plugin-settings-assistant-lifetime.qml'
    fixture.write_text((args.source/'Scripts/dev/fixtures/plugin-settings-assistant-lifetime.qml').read_text().replace('../../../Services/Plugins/PluginSettingsRead.js','Services/Plugins/PluginSettingsRead.js'))
    endpoint = case/'bin/curl'
    endpoint.write_text('''#!/usr/bin/env python3
import json,os,sys,time
from pathlib import Path
a=sys.argv[1:];m=os.environ['PHA_ASSISTANT_LIFE_MODE'];c=Path(os.environ['PHA_ASSISTANT_CASE'])
with (c/'requests.jsonl').open('a') as f:f.write(json.dumps(dict(pid=os.getpid(),start=Path('/proc/self/stat').read_text().split(') ',1)[1].split()[19],argv=a))+'\\n')
if os.environ.get('PHA_ASSISTANT_HTTP'):
 urls=[i for i,arg in enumerate(a) if arg.startswith(('http://','https://'))]
 if len(urls)!=1:sys.exit(2)
 a[urls[0]]=os.environ['PHA_ASSISTANT_HTTP'];curl=os.environ['PHA_REAL_CURL']
 os.execv(curl,[curl,'-q','--noproxy','*',*a])
held=m in ('replace','retired','native-retired','stop','clear','destroyed','translation-replace')
payload=json.loads(a[a.index('-d')+1]) if '-d' in a and a[a.index('-d')+1].startswith('{') else None
if payload and 'messages' in payload:
 print('data: '+json.dumps(dict(choices=[dict(delta=dict(content='partial' if held else 'reply-'+payload['model']))])),flush=True)
elif payload and 'contents' in payload:print('data: '+json.dumps(dict(candidates=[dict(content=dict(parts=[dict(text='gemini-reply')]))])),flush=True)
elif not held:print(json.dumps(dict(translations=[dict(text='deepl-reply')])) if 'deepl.com' in ' '.join(a) else json.dumps([[['google-reply']]]),flush=True)
if held:
 while True:time.sleep(.05)
''')
    endpoint.chmod(0o644 if mode == 'start-failure' else 0o755)
    # No system curl fallback can make a network request during failed-start proof.
    for name in ('python3', 'mkdir', 'qs', 'bash', 'dirname', 'mktemp', 'rm', 'find', 'sort', 'grep', 'sed', 'head', 'tail', 'awk'):
        (case/'bin'/name).symlink_to(shutil.which(name))
    ai = dict(provider='openai_compatible', models=dict(openai_compatible='selected-model', google='selected-gemini'), apiKeys=dict(google='synthetic-key'), openaiLocal=True,
              openaiBaseUrl='http://inert.invalid/selected', temperature=0, systemPrompt='selected prompt')
    if mode in ('gemini', 'environment'): ai['provider'] = 'google'
    cfg = dict(ai=ai, translator=dict(backend='google' if mode == 'translation-google' else 'deepl', sourceLanguage='fr', targetLanguage='de', deeplApiKey='synthetic:fx'), maxHistoryLength=1)
    shared = dict(ai=dict(ai, models=dict(openai_compatible='shared-model')), maxHistoryLength=100, opaque=dict(keep='shared'))
    bar = dict(widgets=dict(left=[dict(id='plugin:assistant-panel', tag='selected', instanceSettings=cfg), dict(id='plugin:assistant-panel', tag='sibling', instanceSettings=dict(opaque='sibling'))]))
    docs = {'settings.json':dict(settingsVersion=62), 'plugins.json':dict(version=6,states={},sources=[]), 'settings/plugins/assistant-panel.json':shared, 'settings/bar.json':bar}
    for name, value in docs.items(): runner.write_json(case/'config'/name, value)
    shutil.copy2(args.source/'Assets/ColorScheme/MacOS/MacOS.json', case/'config/colors.json')
    before = {str(p.relative_to(case/'config')):hashlib.sha256(p.read_bytes()).hexdigest() for p in (case/'config').rglob('*.json')}
    env = dict(PATH=str(case/'bin') if mode == 'start-failure' else str(case/'bin')+os.pathsep+os.environ['PATH'],
               PHA_ASSISTANT_CASE=str(case), PHA_ASSISTANT_LIFE_MODE=mode, NOCTALIA_AP_GOOGLE_API_KEY='synthetic-environment' if mode=='environment' else '', NOCTALIA_AP_OPENAI_COMPATIBLE_API_KEY='', NOCTALIA_AP_DEEPL_API_KEY='synthetic-environment:fx' if mode=='translation-environment' else '')
    try:
        with local_response(mode, out) as http_env:
            text = runner.run_fixture(profile,install,case,out,fixture,installed=True,extra_env=env | http_env,extra_lint=tuple(sorted(dest.glob('*.qml'))),timeout=100)
    except RuntimeError:
        if not wanted or not (out/'runtime.log').is_file() or wanted not in (out/'runtime.log').read_text() or (out/'runtime.exit').read_text().strip()!='2':raise
        rows=[json.loads(line) for line in (case/'requests.jsonl').read_text().splitlines()] if (case/'requests.jsonl').exists() else []
        for row in rows:
            stat=Path('/proc')/str(row['pid'])/'stat'
            assert not stat.exists() or stat.read_text().split(') ',1)[1].split()[19]!=row['start'],'control endpoint survived engine'
        assert {name:json.loads((case/'config'/name).read_text()) for name in docs}==docs,'control native documents'
        runner.write_json(out/'result.json',dict(status='PASS',control=args.control,rejectedAt=wanted,requests=rows,completePlanAcceptance=False))
        runner.remove_completed_installs(case,out);return
    if wanted:raise RuntimeError('Assistant runtime control escaped: '+args.control)
    assert 'ASSISTANT_LIFETIME: PASS '+mode in text and not any(s in text for s in ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected')), text[-3000:]
    expected=deepcopy(docs)
    if mode == 'native-retired':expected['settings/bar.json']['widgets']['left']=expected['settings/bar.json']['widgets']['left'][1:]
    assert {name:json.loads((case/'config'/name).read_text()) for name in docs}==expected, 'complete independent native documents'
    rows=[json.loads(line) for line in (case/'requests.jsonl').read_text().splitlines()] if (case/'requests.jsonl').exists() else []
    for row in rows:
        p=Path('/proc')/str(row['pid'])/'stat'
        assert not p.exists() or p.read_text().split(') ',1)[1].split()[19]!=row['start'], 'endpoint survived engine'
    if mode in ('chat','edit'):
        assert len(rows)==(3 if mode=='edit' else 1)
        for row in rows:
            a=row['argv'];payload=json.loads(a[a.index('-d')+1]);assert payload['model']=='selected-model' and payload['temperature']==0 and a[-1]=='http://inert.invalid/selected'
    if mode=='gemini':assert 'selected-gemini' in rows[0]['argv'][-1] and 'synthetic-key' in rows[0]['argv'][-1]
    if mode=='environment':assert 'selected-gemini' in rows[0]['argv'][-1] and 'synthetic-environment' in rows[0]['argv'][-1] and 'synthetic-key' not in rows[0]['argv'][-1]
    if mode=='translation-environment':assert 'Authorization: DeepL-Auth-Key synthetic-environment:fx' in rows[0]['argv']
    if mode == 'cache':
        saved = json.loads((case/'cache/plugins/assistant-panel/state.json').read_text())
        if ([(m['role'], m['content']) for m in saved['messages']] != [('user', 'last')]
                or (saved['activeTab'], saved['chatInputText'], saved['chatInputCursorPosition']) != ('translate', 'new draft', 3)):
            raise RuntimeError('independent cache readback did not preserve history and UI fields')
        runner.write_json(out/'cache.json', saved)
    if mode in HTTP_BODIES and (len(rows) != 1 or not (out/'http.json').is_file()):
        raise RuntimeError('expected one real loopback response')
    runner.write_json(out/'result.json',dict(status='PASS',mode=mode,requests=rows,configurationBefore=before,documents=expected,beforeEngineExitJoin=True,completePlanAcceptance=False))
    runner.remove_completed_installs(case,out)


def main():
    parser=argparse.ArgumentParser(description=__doc__);profile_argument(parser)
    for name in ('source','plugins','work-root','output'):parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--mode',choices=MODES)
    parser.add_argument('--control',choices=('origin','retirement','cache','parser'))
    args=parser.parse_args();profile=activate_profile(args.guest_profile);profile.prepare_roots()
    if Path(__file__).resolve()!=args.source.resolve()/'Scripts/dev/plugin-settings-assistant-lifetime-regression.py':parser.error('execute supplied source')
    if args.control and args.mode!={'origin':'chat','retirement':'retired','cache':'cache','parser':'translation-deepl'}[args.control]:parser.error('explicit matching mode required for control')
    for p,parent in ((args.work_root,profile.work_base),(args.output,profile.journal_base)):
        if p!=p.resolve() or p==parent or not p.is_relative_to(parent):parser.error('fresh owned guest roots')
    with (profile.work_base/'.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB);args.work_root.mkdir();args.output.mkdir()
        files=[Path(__file__),args.source/'Scripts/dev/fixtures/plugin-settings-assistant-lifetime.qml']
        runner.write_json(args.output/'inputs.json',dict(source=str(args.source),plugins=str(args.plugins),files={str(p.relative_to(args.source)):hashlib.sha256(p.read_bytes()).hexdigest() for p in files},pluginFiles={str(p.relative_to(args.plugins)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (args.plugins/'assistant-panel').rglob('*') if p.is_file()}))
        modes=(args.mode,) if args.mode else MODES
        for mode in modes:run(args,profile,mode)
        runner.write_json(args.output/'result.json',dict(status='PASS',modes=modes,completePlanAcceptance=False))


if __name__=='__main__':main()
