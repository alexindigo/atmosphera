"""Guest-only plumbing shared by locker lifecycle proofs."""
import json
import os
from pathlib import Path
import subprocess
import signal
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


def compositor_transitions(events):
    """Native Hyprland notifications, or niri's compositor-owned logind hint."""
    kind = 'compositor-lock' if os.environ.get('HYPRLAND_INSTANCE_SIGNATURE') else 'locked-hint'
    return [event for event in events if event['kind'] == kind]


def compositor_locked(work, session):
    if not os.environ.get('HYPRLAND_INSTANCE_SIGNATURE'):
        return run(['loginctl', 'show-session', session, '-p', 'LockedHint', '--value']).stdout.strip() == 'yes'
    raw = (work / 'observer/events.jsonl').read_text()
    # Ignore an in-progress final write, never an already completed event.
    events = [json.loads(line) for line in raw.rpartition('\n')[0].splitlines()]
    native = [event for event in events if event['kind'] in ('compositor-initial', 'compositor-lock')]
    assert native, 'native Hyprland observation not initialized'
    return native[-1]['locked']


def recover_known_pam_hang(source, session, role, work):
    """Optional test-only recovery for the separately tracked native syslog hang.

    Never retire the secure GUI holder. A matching native stack plus stable
    parent/start-time/cgroup identity is required before signalling its child.
    This is not a product fix or an alternative authentication path.
    """
    before = manage(source, {'operation': 'inspect', 'session': session})
    record = before['descriptor']['units'][role]
    observation = before['units'][role]
    assert observation['sameInvocation'] and not observation['gone']
    parent = record['clientIdentity']
    assert record['client']['secure'] and not record['client']['authenticated']

    def identity(pid):
        path = Path('/proc') / str(pid)
        fields = (path / 'stat').read_text().split(') ', 1)[1].split()
        return {'pid': pid, 'parent': int(fields[1]), 'start': fields[19]}

    assert identity(parent['pid'])['start'] == parent['start']
    recovered = []
    for member in observation['members']:
        try:
            child = identity(member['pid'])
            if child['parent'] != parent['pid'] or child['start'] != member['start']:
                continue
            if (Path('/proc') / str(child['pid']) / 'exe').resolve() != (Path('/proc') / str(parent['pid']) / 'exe').resolve():
                continue
        except FileNotFoundError:
            continue
        trace = run(['sudo', '-n', 'gdb', '-q', '-batch', '-p', str(child['pid']), '-ex', 'thread apply all bt'], timeout=20)
        stack = trace.stdout + trace.stderr
        (work / ('pam-child-' + str(child['pid']) + '-stack.txt')).write_text(stack)
        if not all(frame in stack for frame in ('__lll_lock_wait_private', '__syslog_chk', 'pam_syslog', 'pam_sm_authenticate', 'pam_unix.so')):
            continue
        current = manage(source, {'operation': 'inspect', 'session': session})
        actual = current['descriptor']['units'][role]
        assert actual['identity'] == record['identity'] and actual['clientIdentity'] == parent
        assert current['units'][role]['sameInvocation'] and actual['client']['secure']
        assert not actual['client']['authenticated']
        assert identity(parent['pid'])['start'] == parent['start']
        assert identity(child['pid']) == child
        assert any(item['pid'] == child['pid'] and item['start'] == child['start'] for item in current['units'][role]['members'])
        os.kill(child['pid'], signal.SIGKILL)
        wait_for(lambda: not (Path('/proc') / str(child['pid'])).exists())
        after = manage(source, {'operation': 'inspect', 'session': session})
        assert after['units'][role]['sameInvocation'] and after['descriptor']['units'][role]['client']['secure']
        recovered.append(child)
    if recovered:
        (work / 'known-pam-hang-recovery.json').write_text(json.dumps({'holder': parent,
            'invocation': record['identity']['InvocationID'], 'children': recovered}, indent=2))
        print('KNOWN NATIVE PAM HANG: verified child recovery; holder stayed secure', flush=True)
    return bool(recovered)
