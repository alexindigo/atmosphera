#!/usr/bin/env python3
"""Guest-only actual read-only wallpaper consumer and cache-watch proof."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

from locker_test_support import require_guest, run, wait_for


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    source, work = require_guest(args.work, args.source)
    entry = source / '.locker-wallpaper-proof.qml'
    cache = work / 'wallpapers.json'
    cache.write_text(json.dumps({'wallpapers': {}, 'defaultWallpaper': '/first.png'}))
    environment = dict(os.environ, LOCKER_WALLPAPER_CACHE=str(cache))
    created = False
    process = None
    journal = (work / 'journal.txt').open('w')
    try:
        with entry.open('x') as output:
            created = True
            output.write((source / 'Scripts/dev/fixtures/locker-wallpaper.qml').read_text().replace('../../../Helpers/', 'Helpers/'))
        process = subprocess.Popen(['qs', '-p', str(entry), '--no-color'], env=environment, stdout=journal, stderr=journal)

        def ipc(*command):
            return run(['qs', 'ipc', '-p', str(entry), 'call', 'wallpaperProof', *command], env=environment).stdout.strip()

        def status():
            result = subprocess.run(['qs', 'ipc', '-p', str(entry), 'call', 'wallpaperProof', 'status'],
                                    env=environment, capture_output=True, text=True, timeout=5)
            return json.loads(result.stdout) if result.returncode == 0 else None

        def ready():
            view = status()
            return view if view and view['ready'] and view['checks'] == 12 else None

        initial = wait_for(ready, 15)
        assert initial['path'] == '/first.png' and initial['changes'] > 0
        name = initial['name']
        replacement = cache.with_suffix('.new')
        replacement.write_text(json.dumps({'wallpapers': {name: {'light': '/light.png', 'dark': '/dark.png'}},
                                           'defaultWallpaper': '/fallback.png'}))
        replacement.replace(cache)
        wait_for(lambda: status()['path'] == '/light.png' and status()['changes'] > initial['changes'])
        original = hashlib.sha256(cache.read_bytes()).hexdigest()
        ipc('appearance', 'true', 'false')
        wait_for(lambda: status()['path'] == '/dark.png')
        ipc('appearance', 'true', 'true')
        wait_for(lambda: status()['path'] == 'solid://#123456' and status()['solidPath'])
        ipc('appearance', 'false', 'false')
        wait_for(lambda: status()['path'] == '/light.png' and not status()['solidPath'])
        assert hashlib.sha256(cache.read_bytes()).hexdigest() == original, 'read consumer wrote its cache'
        (work / 'observations.json').write_text(json.dumps({'initial': initial, 'final': status()}, indent=2))
        ipc('exit')
        assert process.wait(timeout=10) == 0
    finally:
        if process is not None and process.poll() is None:
            process.terminate()
            process.wait(timeout=10)
        journal.close()
        if created:
            entry.unlink()
    text = (work / 'journal.txt').read_text()
    assert not any(error in text for error in ('TypeError:', 'ReferenceError:', 'wallpaper-selection:', 'PluginRegistry', 'PluginService'))
    (work / 'result.txt').write_text('PASS wallpaper-read-consumer 12\n')
    print('PASS wallpaper-read-consumer 12', work)


if __name__ == '__main__':
    main()
