#!/usr/bin/env python3
"""Evaluate Nix's actual install recipe and inspect its assembled named configs.

Nixpkgs/Qt dependencies are evaluation sentinels. This is explicitly an assembly
check, not a Nix package build, wrapper execution or NixOS/Home Manager boot.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess

from locker_test_support import require_guest, run


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, required=True)
    args = parser.parse_args()
    source, work = require_guest(args.work, Path(__file__).resolve().parents[2])
    fixture = source / 'Scripts/dev/fixtures/locker-nix-assembly.nix'
    environment = dict(os.environ, NIX_REMOTE='local', XDG_CACHE_HOME=str(work / 'cache'))
    records = {}
    for calendar in (False, True):
        result = run(['sudo', '-n', 'env', 'TMPDIR=' + os.environ['TMPDIR'], 'NIX_REMOTE=local',
            'XDG_CACHE_HOME=' + str(work / 'cache'), 'nix-instantiate', '--eval', '--read-write-mode', '--strict', '--json',
            str(fixture), '--arg', 'calendarSupport', 'true' if calendar else 'false'], timeout=90)
        recipe = json.loads(result.stdout)
        (work / ('recipe-calendar-' + str(calendar).lower() + '.json')).write_text(json.dumps(recipe, indent=2))
        assert '/dependencies/python-dbus-python-pygobject3/bin' in recipe['preFixup'], 'sleep bindings missing without calendar support'
        assert '/dependencies/quickshell/bin' in recipe['preFixup'], 'managed child qs missing from runtime PATH'
        assert '--prefix XDG_CONFIG_DIRS : "$out/etc/xdg"' in recipe['preFixup'], 'named configs not on XDG search route'
        records[str(calendar)] = {'source': recipe['src'], 'runtimeBindings': True, 'namedConfigSearchPath': True}
        if calendar:
            continue
        # A dependency sentinel cannot execute Quickshell; resolve only that
        # install-time symlink to the guest's installed binary for this check.
        stage = work / 'stage'
        phase = recipe['installPhase'].replace('/dependencies/quickshell/bin/qs', '/usr/bin/qs')
        installed = run(['bash', '-eu', '-c', phase], cwd=recipe['src'],
            env=dict(environment, out=str(stage)), timeout=90)
        (work / 'install-output.txt').write_text(installed.stdout + installed.stderr)
        configs = stage / 'etc/xdg/quickshell'
        assert (configs / 'atmosphera').resolve() == stage / 'share/atmosphera'
        real, emergency = configs / 'atmosphera-lockscreen', configs / 'atmosphera-emergency-lock'
        manifest = [line for line in (source / 'Quickshell/atmosphera-lockscreen/runtime-files.txt').read_text().splitlines()
            if line and not line.startswith('#')]
        for name in manifest:
            original = 'Commons/LockerSettings.qml' if name == 'Commons/Settings.qml' else name
            assert (real / name).read_bytes() == (source / original).read_bytes(), name
        for name in ('shell.qml', 'LockSession.qml'):
            assert (real / name).read_bytes() == (source / 'Quickshell/atmosphera-lockscreen' / name).read_bytes()
        for name in ('Assets', 'Configs', 'Scripts', 'Shaders'):
            assert (real / name).resolve() == stage / 'share/atmosphera' / name
        expected = {'shell.qml', 'EmergencyLock.qml', 'Services/Locker/LockAuth.qml', 'Services/Locker/LockClient.qml',
            'Helpers/OwnedProcess.js', 'Helpers/OwnedProcessChild.qml'}
        assert {str(path.relative_to(emergency)) for path in emergency.rglob('*') if path.is_file()} == expected
        assert not any(path.is_symlink() for path in emergency.rglob('*'))
        assert not (stage / 'share/atmosphera/Scripts/dev').exists()
        assert not (real / 'Portals').exists() and not (real / 'Services/Plugins/Registry.qml').exists()
        for config in (real, emergency):
            assert all(path.resolve().is_relative_to(stage) for path in config.rglob('*'))
            # Real Quickshell's named-config resolver, not just file existence.
            query = subprocess.run(['qs', 'ipc', '-c', config.name, 'show'], text=True, capture_output=True,
                env=dict(os.environ, XDG_CONFIG_DIRS=str(stage / 'etc/xdg')), timeout=10)
            output = query.stdout + query.stderr
            assert 'No running instances' in output and 'Could not find' not in output, output
            (work / (config.name + '-resolution.txt')).write_text(output)
    (work / 'result.json').write_text(json.dumps({'assembly': records,
        'scope': 'actual Nix evaluation/installPhase and native named-config resolution; no Nix runtime build'}, indent=2))
    (work / 'result.txt').write_text('PASS nix-assembly\n')
    print('PASS nix-assembly (not a Nix runtime build)', work)


if __name__ == '__main__':
    main()
