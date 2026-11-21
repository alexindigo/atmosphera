#!/usr/bin/env python3
"""Six provider IO/lease lifetimes in synthetic HOME with inert HTTP origins."""
import argparse
from datetime import datetime
import fcntl
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import importlib.util
import json
import os
from pathlib import Path
import shutil
import threading
import time
from urllib.parse import urlparse

from guest_profile import activate_profile, profile_argument

spec = importlib.util.spec_from_file_location('model_lifetime_runner', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(spec); spec.loader.exec_module(runner)


def main():
    parser = argparse.ArgumentParser(description=__doc__); profile_argument(parser)
    for key in ('source', 'plugins', 'work-root', 'output'): parser.add_argument('--' + key, type=Path, required=True)
    parser.add_argument('--negative-control', action='store_true')
    parser.add_argument('--lease-key-control', action='store_true')
    parser.add_argument('--environment-precedence', action='store_true')
    args = parser.parse_args(); profile = activate_profile(args.guest_profile); profile.prepare_roots()
    if sum([args.negative_control, args.lease_key_control, args.environment_precedence]) > 1: parser.error('one provider variant per run')
    if Path(__file__).resolve() != args.source.resolve() / 'Scripts/dev/plugin-settings-model-lifecycle-regression.py': parser.error('execute supplied source')
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent): parser.error('fresh owned profile roots required')
    with (profile.work_base / '.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB); case, out = args.work_root, args.output; case.mkdir(); out.mkdir()
        for part in ('config', 'cache', 'state', 'home', 'bin'): (case / part).mkdir()
        install = case / 'install'; shutil.copytree(args.source, install, copy_function=os.link, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__', '.qmlls.ini'))
        dest = case / 'plugin'; shutil.copytree(args.plugins / 'model-usage', dest)
        if args.negative_control:
            path = dest / 'providers/Codex.qml'; text = path.read_text()
            old = 'Qt.callLater(function() {\n            if (root.enabled && generation === root._searchGeneration)\n                root.advanceSessionFile();\n        });'
            if text.count(old) != 1: raise RuntimeError('stale Codex fallback control')
            path.write_text(text.replace(old, 'if (root.enabled && generation === root._searchGeneration) root.advanceSessionFile();'))
            runner.write_json(out / 'mutation.json', dict(path='model-usage/providers/Codex.qml', before=hashlib.sha256(text.encode()).hexdigest(), after=hashlib.sha256(path.read_bytes()).hexdigest(), control='synchronous-file-continuation'))
        if args.lease_key_control:
            path = dest / 'Main.qml'; text = path.read_text(); old = 'var key = sourceKeyFor(id, options);'
            if text.count(old) != 1: raise RuntimeError('stale effective provider source-key control')
            path.write_text(text.replace(old, 'var key = JSON.stringify([id, options]);'))
            runner.write_json(out / 'mutation.json', dict(path='model-usage/Main.qml', before=hashlib.sha256(text.encode()).hexdigest(), after=hashlib.sha256(path.read_bytes()).hexdigest(), control='raw-options-lease-key'))
        requests = case / 'requests.jsonl'; requests.write_text(''); rows = []; row_lock = threading.Lock()

        class Endpoint(BaseHTTPRequestHandler):
            def log_message(self, *_): pass
            def do_POST(self):
                data = self.rfile.read(int(self.headers.get('Content-Length', '0')))
                assert json.loads(data) == dict(model='glm-5-free', input='hi', max_output_tokens=1)
                self.reply(data.decode())
            def do_GET(self): self.reply('')
            def reply(self, body):
                token = self.headers.get('Authorization', '')
                with row_lock: rows.append(dict(path=self.path, authorization=token, body=body))
                if 'held' in token: time.sleep(1.5)
                path = urlparse(self.path).path
                if path == '/api/oauth/usage': data = dict(seven_day=dict(utilization=25 if 'fresh' not in token else 65), five_hour=dict(utilization=12))
                elif path == '/copilot_internal/user': data = dict(copilot_plan='pro', quota_snapshots=dict(premium_interactions=dict(percent_remaining=60)))
                elif path == '/api/v1/key': data = dict(data=dict(usage_weekly=4 if 'fresh' not in token else 7, limit=10))
                elif path == '/api/v1/activity': data = dict(data=[dict(requests=3 if 'fresh' not in token else 7, prompt_tokens=9, completion_tokens=1, model='controlled')])
                elif path == '/models': data = dict(data=[dict(id='controlled-model')])
                elif path == '/responses': data = dict(id='controlled-response')
                else: raise AssertionError('unreviewed loopback endpoint ' + path)
                self.send_response(200); self.send_header('Content-Type', 'application/json'); self.end_headers()
                try: self.wfile.write(json.dumps(data).encode())
                except (BrokenPipeError, ConnectionResetError): pass

        server = ThreadingHTTPServer(('127.0.0.1', 0), Endpoint); thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
        base = 'http://127.0.0.1:' + str(server.server_address[1])
        for name, origin in [('Claude', 'https://api.anthropic.com'), ('Copilot', 'https://api.github.com'), ('OpenRouter', 'https://openrouter.ai')]:
            path = dest / ('providers/' + name + '.qml'); text = path.read_text(); assert origin in text
            path.write_text(text.replace(origin, base))
        for name in ('find', 'gh'):
            path = case / ('bin/' + name); shutil.copy2(args.source / 'Scripts/dev/fixtures/plugin-settings-provider-local.py', path); path.chmod(0o755)
        home = case / 'home'; today = datetime.now().strftime('%Y-%m-%d'); now = int(time.time())
        fixtures = {
            '.claude/stats-a.json': dict(totalMessages=11, totalSessions=1), '.claude/stats-b.json': dict(totalMessages=22, totalSessions=2),
            '.claude/credentials-a.json': dict(claudeAiOauth=dict(accessToken='controlled-a', expiresAt=(now + 3600) * 1000)),
            '.claude/credentials-held.json': dict(claudeAiOauth=dict(accessToken='controlled-held', expiresAt=(now + 3600) * 1000)),
            '.codex/auth.json': dict(auth_mode='controlled'),
        }
        for path, data in fixtures.items():
            target = home / path; target.parent.mkdir(parents=True, exist_ok=True); runner.write_json(target, data)
        for path, text in {
            '.claude/history.jsonl': '\n'.join(json.dumps(dict(timestamp=now * 1000, sessionId='session')) for _ in range(3)) + '\n',
            '.codex/history.jsonl': '\n'.join(json.dumps(dict(ts=now, session_id='codex-session')) for _ in range(2)) + '\n',
            '.codex/config.toml': 'model = "controlled-codex"\n',
            '.codex/sessions/a.jsonl': json.dumps(dict(type='token_count', rate_limits=dict(primary=dict(used_percent=37, window_minutes=10080)), info=dict(total_token_usage=dict(input_tokens=9, output_tokens=1)))) + '\n',
            '.codex/sessions/z.jsonl': '{}\n',
            '.gemini/tmp/session-' + today + '.jsonl': json.dumps(dict(type='user')) + '\n' + json.dumps(dict(type='gemini', tokens=dict(total=19), model='controlled-gemini')) + '\n',
        }.items():
            p = home / path; p.parent.mkdir(parents=True, exist_ok=True); p.write_text(text)
        options = dict(claude=dict(enabled=True, statsPath=str(home / '.claude/stats-a.json'), credentialsPath=str(home / '.claude/credentials-a.json')), codex=dict(enabled=True), copilot=dict(enabled=True), gemini=dict(enabled=True), openrouter=dict(enabled=True, apiKey='controlled-a'), zen=dict(enabled=True, apiKey='controlled-a', apiBaseUrl=base))
        runner.write_json(case / 'input.json', dict(directory=str(dest), options=options, home=str(home)))
        files = [Path(__file__), args.source / 'Scripts/dev/fixtures/plugin-settings-model-lifecycle.qml', args.source / 'Scripts/dev/fixtures/plugin-settings-provider-local.py']
        runner.write_json(out / 'inputs.json', dict(files={str(p.relative_to(args.source)): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}, pluginFiles={str(p.relative_to(args.plugins)): hashlib.sha256(p.read_bytes()).hexdigest() for p in (args.plugins / 'model-usage').rglob('*') if p.is_file()}))
        env = dict(PHA_PROVIDER_CASE=str(case), PHA_PROVIDER_REQUESTS=str(requests), HOME=str(home), PATH=str(case / 'bin') + ':' + os.environ['PATH'], OPENROUTER_API_KEY='', OPENCODE_ZEN_API_KEY='', OPENCODE_API_KEY='', ZEN_API_KEY='')
        if args.environment_precedence: env.update(PHA_PROVIDER_ENV_PRECEDENCE='1', OPENROUTER_API_KEY='controlled-env-router', OPENCODE_ZEN_API_KEY='controlled-env-zen', OPENCODE_API_KEY='controlled-lower-opencode', ZEN_API_KEY='controlled-lower-legacy')
        wanted = 'equal sources share all six child observations' if args.lease_key_control else 'Codex FileView fallback continuation did not deliver'
        try:
            try:
                text = runner.run_fixture(profile, install, case, out, args.source / 'Scripts/dev/fixtures/plugin-settings-model-lifecycle.qml', extra_env=env, extra_lint=tuple(sorted(dest.rglob('*.qml'))), timeout=90)
            except RuntimeError:
                text = (out / 'runtime.log').read_text() if (out / 'runtime.log').is_file() else ''
                if not (args.negative_control or args.lease_key_control) or wanted not in text or (out / 'runtime.exit').read_text().strip() != '2': raise
                runner.write_json(out / 'result.json', dict(status='PASS', kind='rejecting-control', rejectedAt=wanted, completePlanAcceptance=False)); runner.remove_completed_installs(case, out); return
            if args.negative_control or args.lease_key_control: raise RuntimeError('Model provider control escaped')
            if 'MODEL_LIFECYCLE: PASS' not in text or any(key in text for key in ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected', 'MODEL_ASSERT:')): raise RuntimeError('model provider lifetime/diagnostic failure')
            processes = [json.loads(line) for line in requests.read_text().splitlines()]
            for row in processes:
                path = Path('/proc') / str(row['pid']) / 'stat'
                if path.exists() and path.read_text().split(') ', 1)[1].split()[19] == row['start']: raise RuntimeError('local provider endpoint survived engine')
            runner.write_json(out / 'processes.json', processes)
            runner.write_json(out / 'result.json', dict(status='PASS', providers=['claude', 'codex', 'copilot', 'gemini', 'openrouter', 'zen'], environmentPrecedence=args.environment_precedence, nativePlacementAcceptance=False, physicalProof=False, completePlanAcceptance=False))
            runner.remove_completed_installs(case, out); print('MODEL_LIFECYCLE: PASS', flush=True)
        finally:
            server.shutdown(); server.server_close(); thread.join(); runner.write_json(out / 'requests.json', rows)


if __name__ == '__main__': main()
