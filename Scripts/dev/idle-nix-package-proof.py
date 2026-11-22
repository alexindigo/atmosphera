#!/usr/bin/env python3
"""Check a fully built Nix launcher and its real Quickshell/Python child chain."""
import argparse
import json
import os
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package', type=Path, required=True)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--guest-uuid', required=True)
    args = parser.parse_args()
    assert subprocess.check_output(['id', '-un'], text=True).strip() == 'tester'
    assert subprocess.check_output(['sudo', '-n', 'cat', '/sys/class/dmi/id/product_uuid'], text=True).strip() == args.guest_uuid
    assert subprocess.check_output(['systemd-detect-virt', '--vm'], text=True).strip() in ('qemu', 'kvm')
    package = args.package.resolve()
    assert str(package).startswith('/nix/store/')
    work = args.work.resolve()
    work.mkdir(parents=True, exist_ok=False)
    assert subprocess.check_output(['findmnt', '-T', str(work), '-n', '-o', 'FSTYPE'], text=True).strip() not in ('tmpfs', 'ramfs')
    observer = work / 'observe.py'
    receipt = work / 'child.json'
    observer.write_text('''import json, os, runpy, sys
from pathlib import Path
probe = runpy.run_path(sys.argv[1])
supported = probe['supported']()
libraries = sorted({line.split()[-1] for line in Path('/proc/self/maps').read_text().splitlines() if 'libwayland-client.so' in line})
parent = str(Path('/proc').joinpath(str(os.getppid()), 'exe').resolve())
Path(sys.argv[2]).write_text(json.dumps(dict(supported=supported, libraries=libraries,
    parent=parent, python=sys.executable, library_path=os.environ.get('LD_LIBRARY_PATH', '')), indent=2))
sys.exit(0 if supported else 1)
''')
    command = ['python3', '-B', str(observer), str(package / 'share/atmosphera/Scripts/python/idle-input-protocol.py'), str(receipt)]
    fixture = work / 'shell.qml'
    fixture.write_text('''import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {
    Process {
        command: COMMAND
        running: true
        onExited: (code, status) => Qt.exit(code)
    }
    Timer { interval: 30000; running: true; onTriggered: Qt.exit(124) }
}
'''.replace('COMMAND', json.dumps(command)))
    environment = dict(os.environ, TMPDIR=os.environ['TMPDIR'], WAYLAND_DISPLAY='wayland-1',
        XDG_RUNTIME_DIR='/run/user/1000', PATH='/usr/bin', QT_QUICK_BACKEND='software',
        XDG_CONFIG_HOME=str(work / 'config'), XDG_CACHE_HOME=str(work / 'cache'),
        XDG_STATE_HOME=str(work / 'state'), ATMOSPHERA_STATE_DIR=str(work / 'state'))
    for name in ('LD_LIBRARY_PATH', 'QML_IMPORT_PATH', 'QML2_IMPORT_PATH', 'QT_PLUGIN_PATH',
                 'NIXPKGS_QT6_QML_IMPORT_PATH', 'QS_CONFIG_PATH'):
        environment.pop(name, None)
    result = subprocess.run(['dbus-run-session', '--', str(package / 'bin/atmosphera'),
        'run', '-p', str(fixture), '--no-color'], env=environment,
        capture_output=True, text=True, timeout=60)
    (work / 'launcher.log').write_text(result.stdout + result.stderr)
    assert result.returncode == 0, (result.returncode, result.stdout, result.stderr)
    child = json.loads(receipt.read_text())
    assert child['supported'], child
    assert child['libraries'] and all(path.startswith('/nix/store/') for path in child['libraries']), child
    assert all('/wayland' in path or '-wayland-' in path for path in child['libraries']), child
    assert child['parent'].startswith('/nix/store/'), child
    assert child['python'].startswith('/nix/store/'), child
    assert all(str(Path(path).parent) in child['library_path'].split(':') for path in child['libraries']), child
    (work / 'result.json').write_text(json.dumps(dict(passed=True, package=str(package),
        scope='full Nix build launcher -> packaged Quickshell -> packaged Python -> packaged Wayland on real v2 compositor'), indent=2))
    print('IDLE_NIX_PACKAGE: PASS built launcher child loads packaged Wayland; v2 supported')


if __name__ == '__main__':
    main()
