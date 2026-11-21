#!/usr/bin/env python3
"""Real Idle settings controls, owning save and cold-load consumer. Guest only."""
import argparse
import json
import os
from pathlib import Path
import subprocess
from probe_files import ProbeFiles


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--work-root', type=Path, required=True)
    parser.add_argument('--guest-uuid', required=True)
    parser.add_argument('--case', choices=('builtin', 'custom', 'native', 'all'), default='all')
    args = parser.parse_args()
    assert subprocess.check_output(['id', '-un'], text=True).strip() == 'tester'
    assert subprocess.check_output(['sudo', '-n', 'cat', '/sys/class/dmi/id/product_uuid'], text=True).strip() == args.guest_uuid
    assert subprocess.check_output(['systemd-detect-virt', '--vm'], text=True).strip() in ('qemu', 'kvm')
    work = args.work_root.resolve()
    work.mkdir(parents=True, exist_ok=False)
    (work / 'tmp').mkdir()
    assert subprocess.check_output(['findmnt', '-T', str(work), '-n', '-o', 'FSTYPE'], text=True).strip() not in ('tmpfs', 'ramfs')
    env = dict(os.environ, TMPDIR=str(work / 'tmp'), XDG_RUNTIME_DIR='/run/user/1000',
               DBUS_SESSION_BUS_ADDRESS='unix:path=/run/user/1000/bus', QML_DISABLE_DISK_CACHE='1')
    session = subprocess.check_output(['systemctl', '--user', 'show-environment'], env=env, text=True)
    env.update(line.split('=', 1) for line in session.splitlines() if line.startswith(('WAYLAND_DISPLAY=', 'NIRI_SOCKET=', 'XDG_CURRENT_DESKTOP=')))
    fixture = ProbeFiles(args.source, args.source / 'Scripts/dev/fixtures/idle-stage-toggles.qml')
    try:
        for case in ('builtin', 'custom', 'native') if args.case == 'all' else (args.case,):
            root = work / case
            (root / 'c/settings').mkdir(parents=True)
            (root / 'c/settings.json').write_text('{"settingsVersion":62}')
            current = dict(env, IDLE_TOGGLES_CASE=case, ATMOSPHERA_CONFIG_DIR=str(root / 'c'),
                           ATMOSPHERA_CACHE_DIR=str(root / 'cache'), ATMOSPHERA_STATE_DIR=str(root / 'state'))
            for cold in (False,) if case == 'native' else (False, True):
                result = subprocess.run(['timeout', '30', 'dbus-run-session', '--', 'qs', '-p', str(fixture.probe), '--no-color'],
                    cwd=args.source, env=dict(current, IDLE_TOGGLES_COLD='1' if cold else '0'), capture_output=True, text=True, timeout=35)
                text = result.stdout + result.stderr
                log = work / (case + ('-cold' if cold else '-save') + '.log')
                log.write_text(text)
                print(str(log) + ': exit=' + str(result.returncode), flush=True)
                marker = 'IDLE_TOGGLES: NATIVE_PASS' if case == 'native' else 'IDLE_TOGGLES: COLD_PASS' if cold else 'IDLE_TOGGLES: SAVED_PASS'
                assert result.returncode == 0 and marker in text, text[-5000:]
                assert not any(token in text for token in ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Failed to load configuration'))
            if case != 'native':
                persisted = json.loads((root / 'c/settings/idle.json').read_text())
                assert persisted['suspendTimeout'] == 0
                assert json.loads(persisted['customCommands'])[0]['timeout'] == 0
        print('IDLE_STAGE_TOGGLES: PASS (' + args.case + ')')
    finally:
        fixture.close()


if __name__ == '__main__':
    main()
