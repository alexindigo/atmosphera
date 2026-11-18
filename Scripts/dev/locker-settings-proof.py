#!/usr/bin/env python3
"""Guest proof of installed locker read-only routes and nonmaterialization."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
from decimal import Decimal

from locker_test_support import require_guest, run, wait_for


def tree(path):
    return {str(p.relative_to(path)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in path.rglob('*') if p.is_file()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--stage', type=Path)
    args = parser.parse_args()
    source, work = require_guest(args.work, Path(__file__).resolve().parents[2])
    stage = args.stage
    if stage is None:
        stage = work / 'stage'
        run(['bash', '-eu', '-c', 'source "$1/packaging/aur/package.sh"; package', 'stage', str(source)],
            env=dict(os.environ, srcdir=str(source.parent), _gitname=source.name, pkgdir=str(stage), pkgver='0.9.3'), timeout=60)
    config_root = stage / 'etc/xdg/quickshell/atmosphera-lockscreen'
    if args.stage is not None:
        shutil.copyfile(source / 'Helpers/LockerSettingsInput.js', config_root / 'Helpers/LockerSettingsInput.js')
    entry = config_root / 'readonly-settings-proof.qml'
    fixture = (source / 'Scripts/dev/fixtures/locker-settings.qml').read_text()
    entry.write_text(fixture.replace('../../../Helpers/LockerSettingsInput.js', 'Helpers/LockerSettingsInput.js'))
    encoded = None
    for mode in ('existing', 'missing', 'legacy', 'invalid', 'codec', 'managed', 'managed-stale', 'managed-live'):
        case = work / mode
        case.mkdir()
        config = case / 'config'
        config.mkdir()
        if mode == 'existing':
            (config / 'settings').mkdir()
            (config / 'settings.json').write_text(json.dumps({'settingsVersion': 62, 'general': {'compactLockScreen': False},
                'bar': {'position': 'bottom', 'density': 'compact', 'screenOverrides': [
                    {'name': 'disabled', 'enabled': False, 'position': 'left', 'density': 'spacious'},
                    {'name': 'enabled', 'enabled': True, 'position': 'right', 'density': 'mini'},
                    {'name': 'implicit', 'position': 'left', 'density': 'spacious'}]}}))
            (config / 'settings/general.json').write_text(json.dumps({'compactLockScreen': True}))
        if mode == 'legacy':
            (config / 'settings.json').write_text('{"settingsVersion":26,"general":{"compactLockScreen":false}}')
        if mode == 'invalid':
            (config / 'settings.json').write_text('{invalid JSON retained verbatim')
        if mode == 'codec':
            (config / 'settings.json').write_text('{"settingsVersion":62,"general":{"compactLockScreen":true},"bar":{"widgets":{"left":[{"id":"Spacer","opaque":{"decimal":"authored"},"wide":18446744073709551615,"fraction":1.0000000000000001}]}}}')
        before = tree(config)
        env = dict(os.environ, ATMOSPHERA_CONFIG_DIR=str(config), ATMOSPHERA_CACHE_DIR=str(case / 'cache'),
                   ATMOSPHERA_STATE_DIR=str(case / 'state'), XDG_CONFIG_DIRS=str(stage / 'etc/xdg') + ':/etc/xdg')
        if mode.startswith('managed'):
            values = json.loads((source / 'Configs/defaults.json').read_text())
            values['general']['compactLockScreen'] = True
            view = case / 'view.json'
            view.touch(mode=0o600)
            generation = 'stale-generation' if mode == 'managed-stale' else 'proof-generation'
            body = json.dumps({'schema': 1, 'session': 'proof', 'generation': generation})[:-1] + ',"values":' + encoded + '}'
            view.write_text(body)
            env.update(ATMOSPHERA_LOCK_GENERATION='proof-generation', ATMOSPHERA_LOCK_SESSION='proof',
                       ATMOSPHERA_LOCK_ADAPTER='read-only-settings-proof', ATMOSPHERA_LOCK_SETTINGS_FILE=str(view))
        if mode in ('codec', 'managed'):
            env['LOCKER_SETTINGS_CODEC'] = '1'
        if mode == 'managed-stale':
            env['LOCKER_SETTINGS_EXPECT_ERROR'] = '1'
        if mode == 'managed-live':
            env['LOCKER_SETTINGS_LIVE'] = '1'
            process = subprocess.Popen(['qs', '-p', str(entry), '--no-color'], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
            try:
                def waiting():
                    reply = subprocess.run(['qs', 'ipc', '-p', str(entry), 'call', 'settingsProof', 'waiting'], capture_output=True, text=True, env=env, timeout=3)
                    return reply.returncode == 0 and reply.stdout.strip() == 'true'
                wait_for(waiting, 15)
                values['general']['compactLockScreen'] = False
                replacement = view.with_suffix('.new')
                replacement.write_text(json.dumps({'schema': 1, 'session': 'proof', 'generation': generation, 'values': values}))
                replacement.replace(view)
                stdout, stderr = process.communicate(timeout=20)
                result = subprocess.CompletedProcess(process.args, process.returncode, stdout, stderr)
            finally:
                if process.poll() is None:
                    process.terminate()
                    process.communicate(timeout=10)
        else:
            result = subprocess.run(['qs', '-p', str(entry), '--no-color'], capture_output=True, text=True, env=env, timeout=25)
        (case / 'journal.txt').write_text(result.stdout + result.stderr)
        if mode == 'managed-stale':
            assert result.returncode == 0 and 'PASS rejected-settings-generation' in result.stdout + result.stderr, result.stdout + result.stderr
            continue
        assert result.returncode == 0 and 'PASS native-readonly-settings' in result.stdout + result.stderr, result.stdout + result.stderr
        assert tree(config) == before, 'settings changed or defaults materialized'
        assert not list(config.rglob('*.lock')) and not list(config.rglob('*.bak')), 'locker created publication artifacts'
        marker = next(line.split('READONLY_VALUES ', 1)[1] for line in (result.stdout + result.stderr).splitlines() if 'READONLY_VALUES ' in line)
        values = json.loads(marker)
        if mode == 'existing':
            assert values['bars'] == [['bottom', 'compact'], ['right', 'mini'], ['left', 'spacious'], ['bottom', 'compact']], values
        assert values['compact'] == (mode in ('existing', 'codec') or mode.startswith('managed')), values
        if mode.startswith('managed'):
            assert not (case / 'cache/settings-conflicts').exists(), 'managed consumer initialized retention writer'
        if mode == 'managed-live':
            assert 'PASS live-settings-consumer' in result.stdout + result.stderr
        if mode in ('codec', 'managed'):
            output = next(line.split('INPUT_CODEC ', 1)[1] for line in (result.stdout + result.stderr).splitlines() if 'INPUT_CODEC ' in line)
            payload = json.loads(output, parse_float=Decimal)
            record = payload['bar']['widgets']['left'][0]
            assert record['wide'] == 18446744073709551615 and record['fraction'] == Decimal('1.0000000000000001'), record
            assert record['opaque'] == {'decimal': 'authored'}, record
            if mode == 'codec':
                encoded = output
        (case / 'observed.json').write_text(json.dumps(values, indent=2))
    print('PASS settings-readonly', work)


if __name__ == '__main__':
    main()
