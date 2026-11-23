#!/usr/bin/env python3
"""Prayer week/fallback/retry/countdown and original native cache/effect owners."""
import argparse
from datetime import datetime, timezone
import fcntl
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import importlib.util
import json
import os
from pathlib import Path
import shutil
import socket
import threading
from fixture_resources import FixtureResources
import time
from urllib.parse import parse_qs, urlparse

from guest_profile import activate_profile, profile_argument

spec = importlib.util.spec_from_file_location('prayer_lifetime_runner', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(spec); spec.loader.exec_module(runner)


def main():
    parser = argparse.ArgumentParser(description=__doc__); profile_argument(parser)
    for key in ('source', 'plugins', 'work-root', 'output'): parser.add_argument('--' + key, type=Path, required=True)
    parser.add_argument('--negative-control', action='store_true')
    args = parser.parse_args(); profile = activate_profile(args.guest_profile); profile.prepare_roots()
    if Path(__file__).resolve() != args.source.resolve() / 'Scripts/dev/plugin-settings-prayer-lifecycle-regression.py': parser.error('execute supplied source')
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent): parser.error('fresh owned profile roots required')
    with (profile.work_base / '.plugin-settings-host-assets.lock').open('a+') as lock, FixtureResources() as resources:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB); case, out = args.work_root, args.output; case.mkdir(); out.mkdir(); (out / 'persisted').mkdir()
        for part in ('config/settings/plugins', 'cache', 'state', 'home', 'bin'): (case / part).mkdir(parents=True)
        install = case / 'install'; shutil.copytree(args.source, install, copy_function=os.link, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__', '.qmlls.ini'))
        dest = case / 'config/plugins/mawaqit'; shutil.copytree(args.plugins / 'mawaqit', dest)
        if args.negative_control:
            path = dest / 'Main.qml'; text = path.read_text(); old = 'client === settingsConsumer && pluginApi.settingsContext.current()'
            if text.count(old) != 1: raise RuntimeError('stale shared prayer cache-owner control')
            path.write_text(text.replace(old, 'pluginApi.settingsContext.current()'))
            runner.write_json(out / 'mutation.json', dict(path='mawaqit/Main.qml', before=hashlib.sha256(text.encode()).hexdigest(), after=hashlib.sha256(path.read_bytes()).hexdigest(), control='shared-prayer-cache-owner'))
        requests, effects = [], case / 'effects.jsonl'; effects.write_text(''); row_lock = threading.Lock()
        held, retry, shared_release = threading.Event(), threading.Event(), threading.Event()
        now = datetime.now(timezone.utc)
        def entry(city):
            return dict(date=now.strftime('%d-%m-%Y'), readable='controlled-' + city, timings=dict(Fajr=now.strftime('%H:%M'), Sunrise='06:00', Dhuhr='12:00', Asr='15:00', Maghrib='18:00', Isha='22:00'), hijri=dict(day='10', month=dict(number=8, en='Controlled', ar='Controlled', days=30), year='1448', date='10-08-1448'))

        class Endpoint(BaseHTTPRequestHandler):
            def log_message(self, *_): pass
            def do_GET(self):
                parsed = urlparse(self.path)
                if parsed.path == '/release-retry':
                    retry.set(); self.send_response(200); self.end_headers(); return
                if parsed.path == '/release-shared':
                    shared_release.set(); self.send_response(200); self.end_headers(); return
                query = parse_qs(parsed.query); city = query['city'][0]
                with row_lock: requests.append(dict(path=self.path, city=city, query=query, receivedAtMs=time.time() * 1000))
                if city == 'shared': shared_release.wait(25)
                if city == 'held': held.wait(25)
                if city == 'retry':
                    retry.wait(25)
                    self.connection.shutdown(socket.SHUT_RDWR); self.connection.close(); return
                week = '/timingsByCity/' in parsed.path
                status = 500 if city == 'fallback' and week else 200
                item = entry(city)
                data = [item] if week else dict(timings=item['timings'], date=dict(gregorian=dict(date=item['date']), hijri=item['hijri'], readable=item['readable']))
                self.send_response(status); self.send_header('Content-Type', 'application/json'); self.end_headers()
                try: self.wfile.write(json.dumps(dict(code=status, data=data)).encode())
                except (BrokenPipeError, ConnectionResetError): pass

        resources.defer(runner.write_json, out / 'requests.json', requests)
        server = resources.serve(ThreadingHTTPServer(('127.0.0.1', 0), Endpoint), daemon=True)
        for event in (held, retry, shared_release):
            resources.defer(event.set)
        base = 'http://127.0.0.1:' + str(server.server_address[1])
        path = dest / 'MawaqitSettingsClient.qml'; text = path.read_text(); assert text.count('https://api.aladhan.com') == 2; path.write_text(text.replace('https://api.aladhan.com', base))
        for name in ('paplay', 'pw-cat', 'notify-send', 'pkill'):
            path = case / ('bin/' + name); shutil.copy2(args.source / 'Scripts/dev/fixtures/plugin-settings-prayer-effect.py', path); path.chmod(0o755)
        shared = dict(city='shared', country='UK', method=3, school=0, showNotifications=True, playAzan=True, opaque=dict(keep='shared'), _cacheData=json.dumps([dict(legacy='unqualified')]), _cacheCity='shared', _cacheCountry='UK', _cacheMethod='3', _cacheSchool='0', _cacheSavedAt='old', _cacheFajrAngle='null', _cacheIshaAngle='null')
        bar = dict(widgets=dict(left=[dict(id='plugin:mawaqit', instanceSettings=dict(city='selected', hijriDayOffset=2, opaque=dict(keep='selected'))), dict(id='plugin:mawaqit', instanceSettings=dict(city='selected'))]))
        seed = dict(shared=shared, bar=bar, week=[entry('shared')], base=base)
        for name, data in [('input.json', seed), ('config/settings.json', dict(settingsVersion=62)), ('config/plugins.json', dict(version=6, states={}, sources=[])), ('config/settings/plugins/mawaqit.json', shared), ('config/settings/bar.json', bar)]: runner.write_json(case / name, data)
        paths = [Path(__file__), args.source / 'Scripts/dev/fixtures/plugin-settings-prayer-lifecycle.qml', args.source / 'Scripts/dev/fixtures/plugin-settings-prayer-disk.py', args.source / 'Scripts/dev/fixtures/plugin-settings-prayer-effect.py']
        runner.write_json(out / 'inputs.json', dict(files={str(p.relative_to(args.source)): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}, pluginFiles={str(p.relative_to(args.plugins)): hashlib.sha256(p.read_bytes()).hexdigest() for p in (args.plugins / 'mawaqit').rglob('*') if p.is_file()}))
        env = dict(PHA_PRAYER_CASE=str(case), PHA_PRAYER_OUTPUT=str(out), PHA_PRAYER_DISK=str(args.source / 'Scripts/dev/fixtures/plugin-settings-prayer-disk.py'), PHA_PRAYER_EFFECTS=str(effects), HOME=str(case / 'home'), PATH=str(case / 'bin') + ':' + os.environ['PATH'])
        try:
            text = runner.run_fixture(profile, install, case, out, args.source / 'Scripts/dev/fixtures/plugin-settings-prayer-lifecycle.qml', extra_env=env, extra_lint=tuple(sorted(dest.rglob('*.qml'))), timeout=90)
        except RuntimeError:
            text = (out / 'runtime.log').read_text() if (out / 'runtime.log').is_file() else ''
            if not args.negative_control or 'independent complete prayer native readback' not in text or (out / 'runtime.exit').read_text().strip() != '2': raise
            runner.write_json(out / 'result.json', dict(status='PASS', kind='rejecting-control', rejectedAt='independent complete prayer native readback', completePlanAcceptance=False)); runner.remove_completed_installs(case, out); return
        if args.negative_control: raise RuntimeError('shared prayer cache-owner control escaped')
        if 'PRAYER_LIFECYCLE: PASS' not in text or any(key in text for key in ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected', 'PRAYER_ASSERT:')): raise RuntimeError('prayer lifetime/diagnostic failure')
        rows = [json.loads(line) for line in effects.read_text().splitlines()]
        for row in rows:
            path = Path('/proc') / str(row['pid']) / 'stat'
            if path.exists() and path.read_text().split(') ', 1)[1].split()[19] == row['start']: raise RuntimeError('prayer effect collaborator survived engine')
        if not any(row['city'] == 'fallback' and '/timingsByCity?' in row['path'] for row in requests): raise RuntimeError('no actual fallback-day request')
        if not any(row['city'] == 'fallback' and row['query']['tune'][0].split(',')[1] == '9' for row in requests): raise RuntimeError('tune integer source change did not reach request')
        marker = next(line.split('PRAYER_RETIRE ', 1)[1] for line in text.splitlines() if 'PRAYER_RETIRE ' in line)
        retired_at = float(marker.strip())
        retry_rows = [row for row in requests if row['city'] == 'retry']
        if not retry_rows or any(row['receivedAtMs'] > retired_at for row in retry_rows): raise RuntimeError('retired retry timer admitted another request')
        for boundary in ('initial', 'shared', 'selected'):
            if json.loads((out / ('persisted/' + boundary + '.json')).read_text())['status'] != 'PASS': raise RuntimeError('missing full native documents')
        runner.write_json(out / 'effects.json', rows); runner.write_json(out / 'result.json', dict(status='PASS', independentNativeDocuments=['initial', 'shared', 'selected'], nativePlacementAcceptance=False, physicalProof=False, completePlanAcceptance=False))
        runner.remove_completed_installs(case, out); print('PRAYER_LIFECYCLE: PASS', flush=True)


if __name__ == '__main__': main()
