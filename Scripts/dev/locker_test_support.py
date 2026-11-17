"""Guest-only plumbing shared by locker lifecycle proofs."""
import json
import os
from pathlib import Path
import subprocess
import time


WORKSPACE = Path('/home/tester/Projects/locker')


def run(command, **kwargs):
    return subprocess.run(command, check=True, text=True, capture_output=True, timeout=kwargs.pop('timeout', 15), **kwargs)


def wait_for(predicate, timeout=10):
    end = time.monotonic() + timeout
    last = None
    while time.monotonic() < end:
        last = predicate()
        if last:
            return last
        time.sleep(.05)
    raise AssertionError(f'condition did not settle within {timeout}s, last={last!r}')


def require_guest(work, source):
    assert run(['id', '-un']).stdout.strip() == 'tester', 'guest tester account required'
    expected = os.environ['LOCKER_TEST_VM_UUID']
    assert run(['sudo', '-n', 'cat', '/sys/class/dmi/id/product_uuid']).stdout.strip().lower() == expected.lower(), 'wrong guest UUID'
    assert run(['systemd-detect-virt', '--vm']).stdout.strip() in ('qemu', 'kvm'), 'QEMU guest required'
    source = source.resolve(strict=True)
    work = work.resolve()
    assert source.is_relative_to(WORKSPACE) and work.is_relative_to(WORKSPACE), 'workspace must be inside the guest task disk'
    temporary = Path(os.environ['TMPDIR']).resolve(strict=True)
    assert temporary.is_relative_to(WORKSPACE), 'TMPDIR must be in the disk-backed workspace'
    for path in (source, work.parent, temporary):
        assert run(['findmnt', '-T', str(path), '-n', '-o', 'FSTYPE']).stdout.strip() not in ('tmpfs', 'ramfs'), 'disk-backed paths required'
    os.environ.update(XDG_RUNTIME_DIR='/run/user/1000', DBUS_SESSION_BUS_ADDRESS='unix:path=/run/user/1000/bus')
    manager = dict(line.split('=', 1) for line in run(['systemctl', '--user', 'show-environment']).stdout.splitlines() if '=' in line)
    assert manager.get('XDG_CURRENT_DESKTOP') in ('niri', 'Hyprland'), 'real graphical session required'
    for key in ('NIRI_SOCKET', 'HYPRLAND_INSTANCE_SIGNATURE', 'WAYLAND_DISPLAY', 'XDG_CURRENT_DESKTOP', 'XDG_SESSION_TYPE'):
        if key in manager:
            os.environ[key] = manager[key]
    assert os.environ.get('WAYLAND_DISPLAY'), 'graphical display required'
    socket = Path(os.environ['XDG_RUNTIME_DIR']) / os.environ['WAYLAND_DISPLAY']
    assert socket.is_socket(), 'Wayland socket missing'
    work.mkdir(mode=0o700)
    (work / 'guest.json').write_text(json.dumps({'uuid': expected, 'source': str(source), 'work': str(work), 'display': str(socket)}, indent=2))
    return source, work


def manage(source, job, check=True):
    result = subprocess.run(['python3', '-B', str(source / 'Scripts/python/locker-unit.py'), 'manage'],
                            input=json.dumps(job), text=True, capture_output=True, timeout=20)
    try:
        reply = json.loads(result.stdout)
    except ValueError as error:
        raise AssertionError(f'adapter returned no JSON: {result.stdout} {result.stderr}') from error
    if check:
        assert result.returncode == 0 and reply['ok'], reply
        return reply['value']
    return reply
