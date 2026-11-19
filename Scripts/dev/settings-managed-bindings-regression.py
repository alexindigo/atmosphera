#!/usr/bin/env python3
"""Managed FIFO/capture contracts on the actual owners; explicit guest only."""
import argparse
import json
import os
from pathlib import Path
import subprocess
from guest_profile import activate_profile, profile_argument


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('source', 'work-root', 'output'):
        parser.add_argument('--'+name, type=Path, required=True)
    cases = ('reset-queue', 'reset-pending', 'reset-section', 'reset-value', 'external-unrelated')
    parser.add_argument('--case', choices=('all', *cases), default='all')
    profile_argument(parser)
    args = parser.parse_args()
    if not __debug__:
        raise SystemExit('optimized test execution is not supported')
    profile = activate_profile(args.guest_profile)
    for name in ('work_root', 'output'):
        path = getattr(args, name).resolve()
        if not path.is_relative_to(profile.workspace) or path == profile.workspace:
            raise SystemExit('outputs must stay in the assigned workspace')
        path.mkdir(parents=True, exist_ok=False)
        setattr(args, name, path)
    source = args.source.resolve()
    fixture = (source/'Scripts/dev/fixtures/settings-managed-bindings.qml').read_bytes()
    entry = source/'settings-managed-bindings.qml'
    with entry.open('xb') as stream:
        stream.write(fixture)
    rows = []
    try:
        for name in cases:
            if args.case not in ('all', name):
                continue
            root = args.work_root/name
            (root/'config/settings').mkdir(parents=True)
            legacy = '{"settingsVersion":62,"bindings":{"environment":"macos"}}' if name in ('reset-section', 'reset-value') else '{"settingsVersion":62}'
            (root/'config/settings.json').write_text(legacy)
            (root/'config/settings/bindings.json').write_text('{"environment":"none"}')
            (root/'config/settings/ui.json').write_text('{"fontDefaultScale":1}')
            (root/'config/plugins.json').write_text('{"version":5,"states":{},"sources":[]}')
            env = dict(os.environ, **profile.session_environment(), MANAGED_BINDINGS_CASE=name,
                       ATMOSPHERA_CONFIG_DIR=str(root/'config'), ATMOSPHERA_CACHE_DIR=str(root/'cache'),
                       ATMOSPHERA_STATE_DIR=str(root/'state'), ATMOSPHERA_SETTINGS_FILE=str(root/'config/settings.json'),
                       QML_DISABLE_DISK_CACHE='1')
            with (args.output/(name+'.log')).open('x') as log:
                result = subprocess.run(['timeout', '--kill-after=5', '20', 'qs', '-p', str(entry), '--no-color'],
                                        env=env, stdout=log, stderr=subprocess.STDOUT, timeout=30)
            text = (args.output/(name+'.log')).read_text()
            passed = result.returncode == 0 and 'MANAGED_BINDINGS: PASS '+name in text
            if name in ('reset-section', 'reset-value'):
                section = root/'config/settings/bindings.json'
                passed = passed and (not section.exists() or 'environment' not in json.loads(section.read_text()))
            passed = passed and (root/'config/settings.json').read_text() == legacy
            rows.append(dict(case=name, exit=result.returncode, status='PASS' if passed else 'FAIL'))
            print(json.dumps(rows[-1]), flush=True)
        profile.verify()
        (args.output/'result.json').write_text(json.dumps(dict(cases=rows), indent=2)+'\n')
        return 0 if all(row['status'] == 'PASS' for row in rows) else 1
    finally:
        entry.unlink()


if __name__ == '__main__':
    raise SystemExit(main())
