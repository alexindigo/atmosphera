"""Guest-only plumbing shared by locker lifecycle proofs."""
import errno
import json
import os
from pathlib import Path
import re
import subprocess
import signal
import select
import sys
import time

if sys.flags.optimize:
    raise SystemExit('Locker proofs refuse optimized Python: guest guards and acceptance assertions must remain active')


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
    install_cancellation()
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
    desktop = manager.get('XDG_CURRENT_DESKTOP', '')
    assert desktop in ('niri', 'Hyprland', 'mango', 'Mango', 'sway') or desktop.split(':')[0] == 'labwc', 'real graphical session required'
    for key in ('NIRI_SOCKET', 'HYPRLAND_INSTANCE_SIGNATURE', 'SWAYSOCK', 'WAYLAND_DISPLAY', 'XDG_CURRENT_DESKTOP', 'XDG_SESSION_TYPE'):
        if key in manager:
            os.environ[key] = manager[key]
    assert os.environ.get('WAYLAND_DISPLAY'), 'graphical display required'
    socket = Path(os.environ['XDG_RUNTIME_DIR']) / os.environ['WAYLAND_DISPLAY']
    assert socket.is_socket(), 'Wayland socket missing'
    work.mkdir(mode=0o700)
    (work / 'guest.json').write_text(json.dumps({'uuid': expected, 'source': str(source), 'work': str(work), 'display': str(socket)}, indent=2))
    return source, work


class ProofCancelled(BaseException):
    pass


def install_cancellation():
    def cancel(signum, frame):
        # Do not interrupt the independent finally obligations a second time.
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        raise ProofCancelled('locker proof cancellation requested; preserving any unauthenticated holder')
    signal.signal(signal.SIGTERM, cancel)


def supervise_proof(command, log, timeout, receipt, source=None, recovery_root=None, cleanup_timeout=120):
    """Cancel a proof, never its secure holder, and allow its finally to finish."""
    started = time.monotonic()
    child = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
    timed_out, forced, cancelled = False, False, None
    try:
        code = child.wait(timeout=timeout)
    except BaseException as error:
        timed_out = isinstance(error, subprocess.TimeoutExpired)
        cancelled = None if timed_out else error
        child.send_signal(signal.SIGTERM)
        try:
            code = child.wait(timeout=cleanup_timeout)
        except subprocess.TimeoutExpired:
            forced = True
            child.kill()
            code = child.wait()
    result = dict(command=command, pid=child.pid, exitCode=code, timedOut=timed_out,
        forcedTermination=forced, cleanupHandlerReturned=(timed_out or cancelled is not None) and not forced,
        elapsed=time.monotonic() - started)
    if timed_out or cancelled is not None:
        result['cleanupCompleted'] = False  # A child exit alone is not a cleanup oracle.
        if source is not None:
            try:
                sid = manage(source, {'operation': 'discover'})['session']
                view = manage(source, {'operation': 'inspect', 'session': sid})
                result['guestState'] = view
            except Exception as error:
                result['guestStateError'] = str(error)
        if recovery_root is not None:
            result['recoveryFiles'] = [str(path) for name in ('credential', 'original-shadow-hash')
                for path in recovery_root.rglob(name)]
        print('Proof timed out; no unlock attempted. State and recovery paths:', receipt, file=sys.stderr)
    Path(receipt).write_text(json.dumps(result, indent=2))
    if cancelled is not None:
        raise cancelled
    return subprocess.CompletedProcess(command, 124 if timed_out else code)


def manage(source, job, check=True):
    result = subprocess.run(['python3', '-B', str(source / 'Scripts/python/locker-unit.py'), 'manage'],
                            input=json.dumps(job), text=True, capture_output=True, timeout=20, check=False)
    try:
        reply = json.loads(result.stdout)
    except ValueError as error:
        raise AssertionError(f'adapter returned no JSON: {result.stdout} {result.stderr}') from error
    if check:
        assert result.returncode == 0 and reply['ok'], reply
        return reply['value']
    return reply


def cgroup_pids(group):
    """PIDs in a cgroup tree; a cgroup removed while reading has none."""
    pids = []
    for file in Path(group).rglob('cgroup.procs'):
        try:
            pids += file.read_text().split()
        except OSError as error:
            if error.errno not in (errno.ENOENT, errno.ENODEV):
                raise
    return pids


HYPR_RESTORE = 'misc:allow_session_lock_restore'


def hypr_option():
    value = json.loads(run(['hyprctl', '-j', 'getoption', HYPR_RESTORE]).stdout)
    assert value['option'] == HYPR_RESTORE
    return {'int': value['int'], 'set': value['set']}


def set_hypr_option(value):
    """Runtime-only change for the disposable guest; never product configuration."""
    assert run(['hyprctl', 'keyword', HYPR_RESTORE, str(value)]).stdout.strip() == 'ok'
    assert hypr_option()['int'] == value


def restore_hypr_option(original):
    if hypr_option() == original:
        return
    set_hypr_option(original['int'])
    if not original['set']:
        # Only a config reload clears the runtime keyword's `set` flag.
        assert run(['hyprctl', 'reload']).stdout.strip() == 'ok'
        wait_for(lambda: hypr_option() == original, 5)
    assert hypr_option() == original, 'restore option not restored'


def wlroots_desktop():
    """Sway/Labwc publish neither a logind lock hint nor lock notifications."""
    desktop = os.environ.get('XDG_CURRENT_DESKTOP', '')
    return desktop == 'sway' or desktop.split(':')[0] == 'labwc'


def protocol_transitions(events):
    """ext-session-lock state from holder traces: the compositor's locked()
    event and the unlock_and_destroy request; a dead holder stays locked."""
    rows = []
    for event in events:
        if event['kind'] != 'journal':
            continue
        if re.search(r'ext_session_lock_v1#\d+\.locked\(\)', event['message']):
            locked = True
        elif re.search(r'ext_session_lock_v1#\d+\.unlock_and_destroy\(', event['message']):
            locked = False
        else:
            continue
        rows.append(dict(kind='protocol-lock', locked=locked, observed=event['sourceMonotonic'],
            invocation=event['invocation']))
    return rows


def compositor_transitions(events):
    """Native Hyprland notifications, niri's compositor-owned logind hint, or
    the ext-session-lock protocol state on Sway/Labwc."""
    if wlroots_desktop():
        return protocol_transitions(events)
    kind = 'compositor-lock' if os.environ.get('HYPRLAND_INSTANCE_SIGNATURE') else 'locked-hint'
    return [event for event in events if event['kind'] == kind]


def compositor_locked(work, session):
    if wlroots_desktop():
        raw = (work / 'observer/events.jsonl').read_text()
        transitions = protocol_transitions([json.loads(line) for line in raw.rpartition('\n')[0].splitlines()])
        return bool(transitions) and transitions[-1]['locked']
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
        def validate():
            current = manage(source, {'operation': 'inspect', 'session': session})
            actual = current['descriptor']['units'][role]
            assert actual['identity'] == record['identity'] and actual['clientIdentity'] == parent
            assert current['units'][role]['sameInvocation'] and actual['client']['secure']
            assert not actual['client']['authenticated']
            assert identity(parent['pid'])['start'] == parent['start']
            assert identity(child['pid']) == child
            assert any(item['pid'] == child['pid'] and item['start'] == child['start'] for item in current['units'][role]['members'])
        if not signal_pinned_child(child['pid'], validate):
            continue
        after = manage(source, {'operation': 'inspect', 'session': session})
        assert after['units'][role]['sameInvocation'] and after['descriptor']['units'][role]['client']['secure']
        recovered.append(child)
    if recovered:
        (work / 'known-pam-hang-recovery.json').write_text(json.dumps({'holder': parent,
            'invocation': record['identity']['InvocationID'], 'children': recovered}, indent=2))
        print('KNOWN NATIVE PAM HANG: verified child recovery; holder stayed secure', flush=True)
    return bool(recovered)


def signal_pinned_child(pid, validate):
    """Pin before final validation; never signal a reused numeric PID."""
    try:
        fd = os.pidfd_open(pid)
    except ProcessLookupError:
        return False
    try:
        if select.select([fd], [], [], 0)[0]:
            return False
        try:
            validate()
        except (FileNotFoundError, ProcessLookupError):
            return False
        try:
            signal.pidfd_send_signal(fd, signal.SIGKILL)
        except ProcessLookupError:
            return False
        wait_for(lambda: bool(select.select([fd], [], [], 0)[0]))
        return True
    finally:
        os.close(fd)
