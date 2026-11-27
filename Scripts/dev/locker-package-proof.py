#!/usr/bin/env python3
"""Inspect actual package assembly; runtime/PAM proofs are separate subcases."""
import argparse
import json
import os
from pathlib import Path

from locker_imports import unresolved_imports
from locker_test_support import require_guest, run


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, required=True)
    args = parser.parse_args()
    source, work = require_guest(args.work, Path(__file__).resolve().parents[2])
    stage = work / 'stage'
    run(['bash', '-eu', '-c', 'source "$1/packaging/aur/package.sh"; package', 'stage', str(source)],
        env=dict(os.environ, srcdir=str(source.parent), _gitname=source.name, pkgdir=str(stage), pkgver='0.9.3'), timeout=60)
    configs = stage / 'etc/xdg/quickshell'
    real = configs / 'atmosphera-lockscreen'
    emergency = configs / 'atmosphera-emergency-lock'
    manifest = [line for line in (source / 'Quickshell/atmosphera-lockscreen/runtime-files.txt').read_text().splitlines()
        if line and not line.startswith('#')]
    for name in manifest:
        expected = source / ('Commons/LockerSettings.qml' if name == 'Commons/Settings.qml' else name)
        assert (real / name).read_bytes() == expected.read_bytes(), name
    for name in ('shell.qml', 'LockSession.qml'):
        assert (real / name).read_bytes() == (source / 'Quickshell/atmosphera-lockscreen' / name).read_bytes()
    for name in ('Assets', 'Configs', 'Scripts', 'Shaders'):
        assert (real / name).is_symlink()
        assert (real / name).resolve() == configs / 'atmosphera' / name
    for name in ('Commons', 'Services', 'Modules', 'Widgets', 'Helpers', 'builtin'):
        assert not (real / name).is_symlink(), 'whole-tree locker dependency link: ' + name
    for name in ('Portals', 'Services/Plugins/Registry.qml', 'Services/Plugins/Service.qml', 'Commons/Migrations/Migration36.qml'):
        assert not (real / name).exists(), 'non-lock startup dependency: ' + name
    expected = {'shell.qml', 'EmergencyLock.qml', 'Services/Locker/LockAuth.qml', 'Services/Locker/LockClient.qml',
        'Helpers/OwnedProcess.js', 'Helpers/OwnedProcessChild.qml', 'Scripts/python/locker-unit.py'}
    files = {str(path.relative_to(emergency)) for path in emergency.rglob('*') if path.is_file()}
    assert files == expected, (files, expected)
    assert not any(path.is_symlink() for path in emergency.rglob('*'))
    assert not (configs / 'atmosphera/Scripts/dev').exists(), 'development fixtures installed in production tree'
    for config in (real, emergency):
        assert (config / 'shell.qml').is_file()
        assert all(path.resolve().is_relative_to(stage) for path in config.rglob('*'))
    # Every static import inside each staged closure must resolve within it.
    # A stack merge that adds an import to a manifest file must update the
    # reviewed manifest; Quickshell's startup scanner would otherwise warn
    # and a later instantiation would fail at runtime.
    unresolved = [problem for config in (real, emergency) for problem in unresolved_imports(source, config)]
    assert not unresolved, unresolved
    (work / 'layout.json').write_text(json.dumps({'bundled': manifest, 'emergency': sorted(files)}, indent=2))
    (work / 'result.txt').write_text('PASS package-layout\n')
    print('PASS package-layout', work)


if __name__ == '__main__':
    main()
