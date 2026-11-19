#!/usr/bin/env python3
"""Supplemental owner-cutover outcomes. Execute only in the assigned test VM.

The real-schema prerequisite is intentionally distinct from the retained
Settings/deployment IDs, which must also pass on the production owner.
"""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--installed', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--work-root', type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    args.work_root.mkdir(parents=True, exist_ok=False)
    subprocess.run(['timeout', '180', 'python3', '-B',
                    str(args.source/'Scripts/dev/settings-migrations-regression.py'),
                    '--source', str(args.source), '--installed', str(args.installed),
                    '--output', str(args.output/'migrations'),
                    '--work-root', str(args.work_root/'migrations')], check=True, timeout=185)
    subprocess.run(['timeout', '160', 'python3', '-B',
                    str(args.source/'Scripts/dev/settings-native-lists-regression.py'),
                    '--source', str(args.source), '--installed', str(args.installed),
                    '--output', str(args.output/'native-lists'),
                    '--work-root', str(args.work_root/'native-lists')], check=True, timeout=165)
    sources = args.installed/'Commons/SettingsSources.qml'
    original_sources = sources.read_bytes()
    assert original_sources == (args.source/'Commons/SettingsSources.qml').read_bytes()
    assert original_sources.count(b'JsonFileSource.StrictPendingRebase') == 29
    probe = args.installed/'i5-pending-rebase.qml'
    with probe.open('xb') as stream:
        stream.write((args.source/'Scripts/dev/fixtures/settings-pending-rebase.qml').read_bytes())
    rows = []
    def put(path, value):
        path.write_text(json.dumps(value)+'\n')
    def identity(path):
        stat = path.stat()
        return (hashlib.sha256(path.read_bytes()).hexdigest(), stat.st_ino, stat.st_mtime_ns, stat.st_mode)
    try:
        for case in ['negative-unknown-only', 'negative-parent-add', 'negative-parent-remove',
                     'unknown-only', 'parent-add', 'parent-remove']:
            negative = case.startswith('negative-')
            name = case.removeprefix('negative-')
            sources.write_bytes(original_sources.replace(b'StrictPendingRebase', b'StrictSourcePreimage')
                                if negative else original_sources)
            directory = args.work_root/case
            (directory/'settings').mkdir(parents=True)
            legacy = directory/'settings.json'
            put(legacy, {'settingsVersion':62, 'general':{'keybinds':{'keyUp':['F3'], 'keyDown':['F4']}}})
            before = identity(legacy)
            put(directory/'settings/bar.json', {'widgets':{'left':[{'id':'Clock','opaque':{'keep':True}}]}})
            parent = dict(keyUp=['F1'], keyDown=['F2'], futureSibling=[False, 0, None, ''])
            if name == 'unknown-only':
                put(directory/'settings/ui.json', {'fontDefaultScale':1.1})
                foreign = dict(fontDefaultScale=1.1, totallyUnknown=True)
            else:
                initial = dict(animationDisabled=True, futureRoot=[False, 0, None, ''])
                if name == 'parent-remove':
                    initial['keybinds'] = parent
                put(directory/'settings/general.json', initial)
                foreign = dict(initial)
                if name == 'parent-remove':
                    del foreign['keybinds']
                else:
                    foreign['keybinds'] = parent
            put(directory/'foreign.json', foreign)
            env = dict(os.environ, I5_REBASE_DIR=str(directory), I5_REBASE_CASE=name, QML_DISABLE_DISK_CACHE='1')
            for mode in (['save'] if negative else ['save', 'restart']):
                env['I4_VERIFY'] = '1' if mode == 'restart' else '0'
                result = subprocess.run(['timeout','25','qs','-p',str(probe),'--no-color'], env=env,
                    capture_output=True, text=True, timeout=30)
                text = result.stdout+result.stderr
                (args.output/(case+'-'+mode+'.log')).write_text(text)
                print(text, end='', flush=True)
                if negative:
                    assert result.returncode == 2 and 'source-preimage-conflict' in text
                    assert 'I5_PENDING_REBASE_ASSERT: successful publication, not retained failure' in text
                    assert 'I5_PENDING_REBASE: SAVED_PASS' not in text
                    continue
                assert result.returncode == 0, (name, mode, result.returncode, text[-3000:])
                assert 'I5_PENDING_REBASE: '+('RESTART_PASS' if mode == 'restart' else 'SAVED_PASS') in text
                assert not any(x in text for x in ['TypeError:', 'ReferenceError:', 'SyntaxError:', 'I5_PENDING_REBASE_ASSERT:'])
            assert identity(legacy) == before, 'legacy bytes/inode/mtime/mode changed'
            target = directory/'settings'/('ui.json' if name == 'unknown-only' else 'general.json')
            actual = json.loads(target.read_text())
            expected = dict(foreign)
            if negative:
                pass  # Strict policy must leave the exact foreign values untouched.
            elif name == 'unknown-only':
                expected['fontDefaultScale'] = 1.61
            else:
                expected['keybinds'] = dict(expected.get('keybinds', {}), keyUp=['F9'])
            assert actual == expected, (name, actual, expected)
            evidence = list((directory/'evidence').glob('*/metadata.json'))
            roles = {json.loads(p.read_text())['role'] for p in evidence}
            assert {'original', 'foreign'} <= roles, roles
            if negative:
                assert not ({'published', 'readback'} & roles), roles
            else:
                assert {'published', 'readback'} <= roles, roles
            artifacts = []
            for metadata in sorted(evidence):
                entry = dict(metadata=json.loads(metadata.read_text()))
                payload = metadata.with_name('bytes')
                if payload.exists():
                    entry['bytesBase64'] = base64.b64encode(payload.read_bytes()).decode('ascii')
                artifacts.append(entry)
            print('I5_PENDING_REBASE_EVIDENCE: '+json.dumps(dict(case=name,
                legacyIdentity=before, expected=expected, actual=actual, observations=artifacts)), flush=True)
            rows.append(dict(id=case, status='PASS', legacyUnchanged=True, evidenceRoles=sorted(roles)))
        (args.output/'result.json').write_text(json.dumps(dict(status='PASS', cases=rows), indent=2)+'\n')
        print('SETTINGS_CUTOVER: PASS (3 pending-rebase save/file/restart consumers; 3 strict-policy rejecting controls)')
    finally:
        sources.write_bytes(original_sources)
        probe.unlink()


if __name__ == '__main__':
    main()
