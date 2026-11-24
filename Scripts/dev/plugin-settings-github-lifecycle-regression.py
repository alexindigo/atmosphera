#!/usr/bin/env python3
"""All GitHub request stages and original shared cache owner, inert curl only."""
from fixture_receipts import receipt_run, stage_receipt
from fixtures.source_delivery import link_or_copy
import argparse
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import struct
import zlib

from guest_profile import activate_profile, profile_argument

spec = importlib.util.spec_from_file_location('github_lifetime_runner', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(spec); spec.loader.exec_module(runner)


@receipt_run
def main():
    parser = argparse.ArgumentParser(description=__doc__); profile_argument(parser)
    for key in ('source', 'plugins', 'work-root', 'output'): parser.add_argument('--' + key, type=Path, required=True)
    parser.add_argument('--notification-control', action='store_true')
    args = parser.parse_args(); profile = activate_profile(args.guest_profile); profile.prepare_roots()
    if Path(__file__).resolve() != args.source.resolve() / 'Scripts/dev/plugin-settings-github-lifecycle-regression.py': parser.error('execute supplied source')
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent): parser.error('fresh owned profile roots required')
    with (profile.work_base / '.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB); case, out = args.work_root, args.output; case.mkdir(); out.mkdir()
        for part in ('config', 'cache', 'state', 'home', 'bin'): (case / part).mkdir()
        install = case / 'install'; shutil.copytree(args.source, install, copy_function=link_or_copy, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__', '.qmlls.ini'))
        dest = case / 'plugin'; shutil.copytree(args.plugins / 'github-feed', dest)
        if args.notification_control:
            path = dest / 'Main.qml'; text = path.read_text(); old = 'if (_notified.has(key)) return;'
            if text.count(old) != 1: raise RuntimeError('stale common GitHub notification control')
            path.write_text(text.replace(old, 'if (false) return;'))
            runner.write_json(out / 'mutation.json', dict(path='github-feed/Main.qml', before=hashlib.sha256(text.encode()).hexdigest(), after=hashlib.sha256(path.read_bytes()).hexdigest(), control='common-notification'))
        endpoint = case / 'bin/curl'; shutil.copy2(args.source / 'Scripts/dev/fixtures/plugin-settings-provider-endpoint.py', endpoint); endpoint.chmod(0o755)
        notification = case / 'bin/notify-send'; shutil.copy2(args.source / 'Scripts/dev/fixtures/plugin-settings-prayer-effect.py', notification); notification.chmod(0o755)
        effects = case / 'effects.jsonl'; effects.write_text('')
        requests = case / 'requests.jsonl'; requests.write_text('')
        (case / 'avatar-held').write_text('')
        (dest / 'cache').mkdir(exist_ok=True)
        avatars = dest / 'cache/avatars'; avatars.mkdir()
        (avatars / 'download.png').write_bytes(b'legacy-unqualified')
        def chunk(kind, data): return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
        png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 1, 1, 8, 6, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(b'\x00\x20\x80\xff\xff')) + chunk(b'IEND', b'')
        (avatars / 'https%3A%2F%2Fgithub.com__cached.png').write_bytes(png)
        runner.write_json(dest / 'cache/events.json', dict(events=[dict(id='legacy-foreign')], following=[], timestamp=2140000000))
        runner.write_json(case / 'input.json', dict(directory=str(dest)))
        files = [Path(__file__), args.source / 'Scripts/dev/fixtures/plugin-settings-github-lifecycle.qml', args.source / 'Scripts/dev/fixtures/plugin-settings-provider-endpoint.py', args.source / 'Scripts/dev/fixtures/plugin-settings-prayer-effect.py']
        runner.write_json(out / 'inputs.json', dict(files={str(p.relative_to(args.source)): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}, pluginFiles={str(p.relative_to(args.plugins)): hashlib.sha256(p.read_bytes()).hexdigest() for p in (args.plugins / 'github-feed').rglob('*') if p.is_file()}))
        env = dict(PHA_PROVIDER_CASE=str(case), PHA_PROVIDER_REQUESTS=str(requests), PHA_PROVIDER_LIFECYCLE='1', PHA_PRAYER_EFFECTS=str(effects), HOME=str(case / 'home'), PATH=str(case / 'bin') + ':' + os.environ['PATH'])
        try:
            text = runner.run_fixture(profile, install, case, out, args.source / 'Scripts/dev/fixtures/plugin-settings-github-lifecycle.qml', extra_env=env, extra_lint=tuple(sorted(dest.rglob('*.qml'))), timeout=90)
        except RuntimeError:
            text = (out / 'runtime.log').read_text() if (out / 'runtime.log').is_file() else ''
            wanted = 'one common notification across equal-source contexts'
            if not args.notification_control or wanted not in text or (out / 'runtime.exit').read_text().strip() != '2': raise
            runner.write_json(out / 'requests.json', [json.loads(line) for line in requests.read_text().splitlines()])
            runner.write_json(out / 'effects.json', [json.loads(line) for line in effects.read_text().splitlines()])
            stage_receipt(out / 'result.json', dict(status='PASS', kind='rejecting-control', rejectedAt=wanted, completePlanAcceptance=False))
            runner.remove_completed_installs(case, out); return
        if args.notification_control: raise RuntimeError('common GitHub notification control escaped')
        if 'GITHUB_LIFECYCLE: PASS' not in text or any(key in text for key in ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected', 'GITHUB_LIFECYCLE_ASSERT:')): raise RuntimeError('GitHub chain lifetime/diagnostic failure')
        cache = json.loads((dest / 'cache/events.json').read_text())
        if cache['schema'] != 1 or cache['sourceUsername'] != 'same' or cache['sourceOrigin'] != 'https://github.com' or len(cache['events']) != 1: raise RuntimeError('instance worker overwrote original shared cache owner')
        rows = [json.loads(line) for line in requests.read_text().splitlines()]
        notification_rows = [json.loads(line) for line in effects.read_text().splitlines()]
        if len(notification_rows) != 1 or notification_rows[0]['command'] != 'notify-send': raise RuntimeError('common notification admission did not reach singular inert effect')
        patches = [row for row in rows if 'PATCH' in row['argv']]
        if len(patches) != 1 or 'Authorization: Bearer controlled-token-only' not in patches[0]['argv'] or not patches[0]['argv'][-1].endswith('/threads/0'): raise RuntimeError('retired PATCH queue borrowed replacement credentials or continued')
        avatar_rows = [row for row in rows if '-o' in row['argv']]
        if len(avatar_rows) != 3 or any('/never?' in row['argv'][-1] or '/cached?' in row['argv'][-1] for row in avatar_rows): raise RuntimeError('avatar cache check or retired queued admission failed')
        expected = {'download.png': b'legacy-unqualified', 'https%3A%2F%2Fgithub.com__cached.png': png, 'https%3A%2F%2Fgithub.com__download.png': png, 'https%3A%2F%2Fenterprise.controlled__download.png': png, 'https%3A%2F%2Fenterprise.controlled__held.png': png}
        if {path.name: path.read_bytes() for path in avatars.iterdir()} != expected: raise RuntimeError('independent complete qualified avatar bytes mismatch')
        if any('controlled-empty-user' in arg for row in rows for arg in row['argv']): raise RuntimeError('unconfigured source admitted network IO')
        for row in rows + notification_rows:
            path = Path('/proc') / str(row['pid']) / 'stat'
            if path.exists() and path.read_text().split(') ', 1)[1].split()[19] == row['start']: raise RuntimeError('GitHub inert endpoint survived engine')
        runner.write_json(out / 'cache.json', cache); runner.write_json(out / 'requests.json', rows); runner.write_json(out / 'effects.json', notification_rows)
        stage_receipt(out / 'result.json', dict(status='PASS', avatarDownloads=len(avatar_rows), decodedAvatarImages=3, avatarFiles=sorted(expected), commonNotifications=len(notification_rows), unconfiguredProjection=True, nativePlacementAcceptance=False, physicalProof=False, completePlanAcceptance=False))
        runner.remove_completed_installs(case, out); print('GITHUB_LIFECYCLE: PASS', flush=True)


if __name__ == '__main__': main()
