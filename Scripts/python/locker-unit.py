#!/usr/bin/env python3
"""Exact session locker units and generation fencing, not backend policy.

Management requests are JSON on stdin. The QML owner chooses adapters and
fallbacks; this adapter serializes launch/grant/auth/retirement transactions,
records systemd identities, and enforces only an ungranted startup deadline.
No operation here performs a Wayland unlock or accepts a password.
"""
import argparse
from contextlib import contextmanager
import fcntl
import json
import os
from pathlib import Path
import re
import secrets
import stat
import subprocess
import sys
import tempfile
import time


FIELDS = ('ActiveState', 'SubState', 'InvocationID', 'ControlGroup', 'MainPID', 'Result')
CLIENT_FIELDS = ('ready', 'requested', 'locked', 'secure', 'terminal', 'authenticated', 'retiring')
DISPLAY_ENV = ('WAYLAND_DISPLAY', 'DISPLAY', 'NIRI_SOCKET', 'HYPRLAND_INSTANCE_SIGNATURE',
               'SWAYSOCK', 'XDG_CURRENT_DESKTOP', 'XDG_SESSION_TYPE', 'XDG_RUNTIME_DIR',
               'DBUS_SESSION_BUS_ADDRESS', 'XDG_CONFIG_HOME', 'XDG_CONFIG_DIRS',
               'XDG_CACHE_HOME', 'XDG_STATE_HOME', 'XDG_DATA_HOME', 'XDG_DATA_DIRS',
               'ATMOSPHERA_CONFIG_DIR', 'ATMOSPHERA_CACHE_DIR', 'ATMOSPHERA_STATE_DIR',
               'ATMOSPHERA_SETTINGS_FILE', 'ATMOSPHERA_PAM_SERVICE', 'QT_QPA_PLATFORM',
               'QML_IMPORT_PATH', 'TMPDIR', 'PATH', 'HOME', 'USER', 'LANG', 'LC_ALL', 'WAYLAND_DEBUG')


class Refused(RuntimeError):
    pass


def command(args, timeout=10, check=True):
    return subprocess.run(args, text=True, capture_output=True, timeout=timeout, check=check)


def properties(args):
    return dict(row.split('=', 1) for row in command(args).stdout.splitlines() if '=' in row)


def proc_identity(pid):
    try:
        body = Path(f'/proc/{int(pid)}/stat').read_text()
        fields = body.rsplit(')', 1)[1].split()
        if fields[0] == 'Z':
            return None
        return {'pid': int(pid), 'start': fields[19]}
    except (FileNotFoundError, ProcessLookupError):
        return None


def same_process(identity):
    return identity is not None and proc_identity(identity['pid']) == identity


def prepare_report(prefix='client'):
    root = runtime_root()
    with tempfile.NamedTemporaryFile(mode='w', dir=root, prefix=prefix + '-', suffix='.report.json', delete=False) as stream:
        os.fchmod(stream.fileno(), 0o600)
        stream.write('{}\n')
        stream.flush()
        os.fsync(stream.fileno())
    return {'path': stream.name, 'token': secrets.token_hex(24)}


def refresh_report(data, role, record):
    info = record.get('reportInfo')
    identity = record.get('clientIdentity')
    if info and identity and not record.get('reportRetired'):
        try:
            path = Path(info['path'])
            if path.parent != runtime_root() or not path.name.endswith('.report.json'):
                raise Refused('invalid client report path')
            fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
            with os.fdopen(fd) as stream:
                metadata = os.fstat(stream.fileno())
                if metadata.st_uid != os.getuid() or stat.S_IMODE(metadata.st_mode) != 0o600 or not stat.S_ISREG(metadata.st_mode):
                    raise Refused('invalid client report ownership/mode')
                text = stream.read(4097)
            if len(text) > 4096:
                raise Refused('invalid client report size')
            report = json.loads(text)
            if report:
                expected = {'schema': 1, 'session': data['session'], 'generation': data['generation'],
                    'role': role, 'invocation': record['identity']['InvocationID'],
                    'identity': identity, 'token': info['token']}
                if any(report.get(key) != value for key, value in expected.items()):
                    raise Refused('client report identity mismatch')
                sequence = report.get('sequence')
                event = report.get('event')
                if type(sequence) is not int or sequence < 1 or event not in ('locked', 'finished', 'authenticated-unlock'):
                    raise Refused('invalid client report event/sequence')
                if event in ('locked', 'authenticated-unlock') and report.get('everSecure') is not True:
                    raise Refused('client report lacks secure history')
                if event == 'authenticated-unlock' and data.get('authRole') != role:
                    raise Refused('client report lacks authentication fence')
                previous = record.get('protocolReport')
                if previous is None or sequence > previous['sequence']:
                    record['protocolReport'] = report
                elif sequence == previous['sequence'] and report != previous:
                    raise Refused('client report sequence was rewritten')
            record.pop('reportError', None)
        except (OSError, ValueError, Refused) as error:
            # Invalid/missing evidence cannot create a new secure or auth fact.
            record['reportError'] = str(error)
    report = record.get('protocolReport')
    record['protocolOutcome'] = 'unknown'
    if not report:
        if record.get('client'):
            record['client']['secure'] = False
            record['client']['authenticated'] = False
            if record['client'].get('settlement') in ('finished', 'authenticated-unlock'):
                record['client']['terminal'] = False
                record['client']['settlement'] = ''
        return
    client = record.setdefault('client', {})
    record['everSecure'] = record.get('everSecure', False) or report.get('everSecure') is True
    client['requested'] = True
    if report['event'] == 'locked':
        record['protocolOutcome'] = 'locked'
        client['locked'] = True
        client['secure'] = True
    else:
        authenticated = report['event'] == 'authenticated-unlock'
        record['protocolOutcome'] = 'authenticated-unlock' if authenticated else 'finished'
        client.update(locked=False, secure=False, terminal=True, authenticated=authenticated,
            settlement='authenticated-unlock' if authenticated else 'finished')


def cgroup_members(group):
    if not group or group == '/' or '..' in Path(group).parts:
        raise Refused('invalid saved control group')
    root = Path('/sys/fs/cgroup') / group.lstrip('/')
    if not root.exists():
        return []
    members = []
    for file in [root / 'cgroup.procs', *root.glob('**/cgroup.procs')]:
        try:
            for pid in file.read_text().split():
                identity = proc_identity(pid)
                if identity and identity not in members:
                    members.append(identity)
        except FileNotFoundError:
            pass
    return members


def unit_status(name):
    args = ['systemctl', '--user', 'show', name]
    for field in FIELDS:
        args += ['-p', field]
    result = command(args, check=False)
    if result.returncode and 'not found' not in result.stderr and 'could not be found' not in result.stderr:
        raise Refused('cannot inspect exact unit: ' + result.stderr.strip())
    values = dict(row.split('=', 1) for row in result.stdout.splitlines() if '=' in row)
    return {key: values.get(key, '') for key in FIELDS}


def graphical_session(wanted=None):
    ids = [row.split()[0] for row in command(['loginctl', 'list-sessions', '--no-legend', '--no-pager']).stdout.splitlines() if row.split()]
    candidates = []
    for sid in ids:
        info = properties(['loginctl', 'show-session', sid, '-p', 'Id', '-p', 'User',
                           '-p', 'Type', '-p', 'Class', '-p', 'State', '-p', 'Remote'])
        if (info.get('User') == str(os.getuid()) and info.get('Type') == 'wayland'
                and info.get('Class') == 'user' and info.get('Remote') == 'no'
                and info.get('State') in ('active', 'online')):
            candidates.append(info['Id'])
    # A compositor's own PID binds a systemd-launched shell to its graphical
    # session rather than to this management command's SSH/login session.
    compositor_pid = None
    socket = os.environ.get('NIRI_SOCKET', '')
    if socket:
        match = re.fullmatch(r'niri\..+\.(\d+)\.sock', Path(socket).name)
        if not match or not stat.S_ISSOCK(os.stat(socket).st_mode) or os.stat(socket).st_uid != os.getuid():
            raise Refused('invalid niri display identity')
        compositor_pid = int(match[1])
        if Path(f'/proc/{compositor_pid}/comm').read_text().strip() != 'niri':
            raise Refused('niri display PID does not identify niri')
    elif os.environ.get('HYPRLAND_INSTANCE_SIGNATURE'):
        instances = json.loads(command(['hyprctl', '-j', 'instances']).stdout)
        instances = [item for item in instances if item.get('instance') == os.environ['HYPRLAND_INSTANCE_SIGNATURE']]
        if len(instances) != 1:
            raise Refused('ambiguous Hyprland display identity')
        compositor_pid = int(instances[0]['pid'])
    if compositor_pid:
        groups = Path(f'/proc/{compositor_pid}/cgroup').read_text()
        candidates = [sid for sid in candidates if re.search(r'/session-' + re.escape(sid) + r'\.scope(?:/|\n|$)', groups)]
    else:
        raise Refused('no supported graphical compositor identity')
    if len(candidates) != 1 or (wanted is not None and candidates[0] != wanted):
        raise Refused('graphical session does not match the display')
    return candidates[0]


def runtime_root():
    runtime = Path(os.environ.get('XDG_RUNTIME_DIR', ''))
    if (not runtime.is_absolute() or runtime.stat().st_uid != os.getuid()
            or runtime.is_symlink()):
        raise Refused('invalid user runtime directory')
    root = runtime / 'atmosphera-lock'
    root.mkdir(mode=0o700, exist_ok=True)
    info = root.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o700:
        raise Refused('locker runtime directory is not private')
    return root


def escaped_session(session):
    if not isinstance(session, str) or not session or '/' in session or '\0' in session:
        raise Refused('invalid session ID')
    return command(['systemd-escape', '--', session]).stdout.strip()


class Session:
    def __init__(self, session):
        self.session = session
        self.escaped = escaped_session(session)
        self.root = runtime_root()
        self.path = self.root / (self.escaped + '.json')

    @contextmanager
    def locked(self, generation=None):
        fd = os.open(self.root / (self.escaped + '.lock'), os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, 'r+') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            try:
                fd = os.open(self.path, os.O_RDONLY | os.O_NOFOLLOW)
            except FileNotFoundError:
                data = None
            else:
                with os.fdopen(fd) as stream:
                    data = json.load(stream)
                if (data['session'] != self.session or data['boot'] != Path('/proc/sys/kernel/random/boot_id').read_text().strip()
                        or data['uid'] != os.getuid()):
                    raise Refused('descriptor identity mismatch')
            if generation is not None and (data is None or data['generation'] != generation):
                raise Refused('stale locker generation')
            yield data

    def write(self, data):
        name = None
        try:
            with tempfile.NamedTemporaryFile(mode='w', dir=self.root, prefix='.' + self.escaped + '-', delete=False) as stream:
                name = stream.name
                os.fchmod(stream.fileno(), 0o600)
                json.dump(data, stream, separators=(',', ':'))
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(name, self.path)
            name = None
        finally:
            if name is not None:
                os.unlink(name)

    def name(self, role):
        if role not in ('real', 'emergency', 'prehook', 'lockhook', 'unlockhook'):
            raise Refused('unknown locker role')
        prefix = {'real': 'atmosphera-lockscreen-', 'emergency': 'atmosphera-emergency-lock-'}.get(role, 'atmosphera-lock-' + role + '-')
        return prefix + self.escaped + '.service'

    def write_settings(self, data, settings_json):
        if not isinstance(settings_json, str) or not isinstance(json.loads(settings_json), dict):
            raise Refused('settings view must be an encoded object')
        path = self.root / (self.escaped + '-' + data['generation'] + '.settings.json')
        revision = data.get('settingsRevision', 0) + 1
        header = json.dumps({'schema': 1, 'session': self.session, 'generation': data['generation'],
                             'revision': str(revision)}, separators=(',', ':'))
        # Keep ConfigQml's exact numeric tokens verbatim. Parsing then dumping
        # the values here would round floating-point JSON observation tokens.
        text = header[:-1] + ',"values":' + settings_json + '}'
        name = None
        try:
            with tempfile.NamedTemporaryFile(mode='w', dir=self.root, prefix='.' + self.escaped + '-settings-', delete=False) as stream:
                name = stream.name
                os.fchmod(stream.fileno(), 0o600)
                stream.write(text)
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(name, path)
            name = None
        finally:
            if name is not None:
                os.unlink(name)
        data['settingsPath'] = str(path)
        data['settingsRevision'] = revision


def observe(record):
    current = unit_status(record['name'])
    saved = record.get('identity')
    same = bool(saved and current['InvocationID'] == saved['InvocationID'])
    if saved and current['InvocationID'] and not same:
        raise Refused('exact unit was replaced by another invocation')
    if same and current['ControlGroup'] and current['ControlGroup'] != saved['ControlGroup']:
        raise Refused('recorded invocation changed control group')
    group = saved['ControlGroup'] if saved else ''
    members = cgroup_members(group) if group else []
    alive = [item for item in record.get('members', []) if same_process(item)]
    gone = not members and not alive and current['ActiveState'] in ('', 'inactive', 'failed')
    if saved and group and members:
        record['members'] = members
    return {'unit': current, 'sameInvocation': same, 'members': members, 'gone': gone}


def stop_record(record):
    observation = observe(record)
    if observation['gone']:
        return observation
    if not observation['sameInvocation']:
        raise Refused('cannot stop unit without matching invocation')
    command(['systemctl', '--user', 'stop', record['name']], timeout=8)
    until = time.monotonic() + 5
    while time.monotonic() < until:
        observation = observe(record)
        if observation['gone']:
            return observation
        time.sleep(.025)
    raise Refused('owned invocation/cgroup did not finish stopping')


def valid_client(data, role, pid):
    record = data['units'].get(role)
    if not record or not record.get('identity'):
        raise Refused('no recorded client invocation')
    identity = proc_identity(pid)
    observation = observe(record)
    if identity is None or identity not in observation['members'] or not observation['sameInvocation']:
        raise Refused('client is not in the recorded invocation')
    previous = record.get('clientIdentity')
    if previous is not None and previous != identity:
        raise Refused('another client already registered for this invocation')
    record['clientIdentity'] = identity
    return record


def client_reply(data, role):
    record = data['units'][role]
    return {'grant': bool(record.get('grant') and data['phase'] not in ('unlocking', 'settled')),
            'retire': bool(record.get('retire') or data['phase'] == 'settled'),
            'externalUnlocked': bool(role == 'emergency' and data['snapshot']['adapter'] != 'bundled'
                                     and data.get('sessionUnlockObserved') and not data.get('probeRaceWon')),
            'phase': data['phase'], 'generation': data['generation'],
            'report': dict(record['reportInfo'], schema=1, session=data['session'], generation=data['generation'],
                role=role, invocation=record['identity']['InvocationID'], identity=record['clientIdentity'])}


def manage(job):
    operation = job['operation']
    if operation == 'discover':
        sid = graphical_session()
        # niri's dead-client replacement was verified against the installed
        # protocol implementation. Other compositors remain fail-closed until
        # their restore option AND the corresponding takeover proof are known.
        return {'session': sid, 'now': time.monotonic(), 'takeover': bool(os.environ.get('NIRI_SOCKET')),
                'environment': {k: os.environ[k] for k in DISPLAY_ENV if k in os.environ}}
    session = Session(job['session'])
    if operation == 'begin':
        graphical_session(session.session)
        with session.locked() as old:
            if old is not None:
                if old['phase'] != 'settled' or any(not observe(record)['gone'] for record in old['units'].values()):
                    raise Refused('reconcile the existing generation before beginning another')
            for role in ('real', 'emergency', 'prehook', 'lockhook', 'unlockhook'):
                if unit_status(session.name(role))['ActiveState'] not in ('', 'inactive', 'failed'):
                    raise Refused('session unit exists without adoptable descriptor')
            now = time.monotonic()
            data = {'schema': 1, 'session': session.session, 'uid': os.getuid(),
                    'boot': Path('/proc/sys/kernel/random/boot_id').read_text().strip(),
                    'generation': secrets.token_hex(24), 'requestedAt': now,
                    'emergencyAt': now + 3, 'deadline': now + 30,
                    'phase': 'starting', 'snapshot': job['snapshot'],
                    'environment': {k: os.environ[k] for k in DISPLAY_ENV if k in os.environ},
                    'units': {}, 'handoverCommitted': False, 'authRole': None,
                    'suspendPending': job['snapshot'].get('suspendAfterSecure') is True,
                    'contractRequested': False, 'contractFailed': False, 'realLaunchFailed': False,
                    'probeEvents': {}, 'sleepWindow': 1 if job['snapshot'].get('sleepWindow') else 0,
                    'sleepWindowActive': job['snapshot'].get('sleepWindow') is True,
                    'probeRaceWon': False}
            if job.get('settingsJson') is not None:
                session.write_settings(data, job['settingsJson'])
            session.write(data)
            return data
    with session.locked(None if operation == 'inspect' else job['generation']) as data:
        if data is None:
            return {'descriptor': None, 'now': time.monotonic()}
        for saved_role, saved_record in data['units'].items():
            if saved_role in ('real', 'emergency'):
                refresh_report(data, saved_role, saved_record)
        if operation == 'inspect':
            observations = {role: observe(record) for role, record in data['units'].items()}
            session.write(data)
            return {'descriptor': data, 'units': observations, 'now': time.monotonic()}
        role = job.get('role')
        if operation == 'settings':
            if data['phase'] in ('unlocking', 'settled'):
                raise Refused('generation no longer accepts settings input')
            session.write_settings(data, job['settingsJson'])
            session.write(data)
            return {'revision': data['settingsRevision']}
        if operation == 'launch':
            if data['phase'] == 'settled' or (data['phase'] == 'unlocking' and role != 'unlockhook'):
                raise Refused('generation has lost launch authority')
            name = session.name(role)
            previous = data['units'].get(role)
            if previous and not observe(previous)['gone']:
                return previous
            if role == 'emergency' and data['snapshot']['adapter'] != 'bundled':
                if data.get('sessionUnlockObserved') and not data.get('probeRaceWon'):
                    raise Refused('external unlock revoked probe launch authority')
                events = job.get('events', [])
                if events and all(event in data.get('probeEvents', {}) for event in events):
                    raise Refused('probe events were already consumed')
            if role == 'emergency' and data['handoverCommitted']:
                real = data['units'].get('real')
                if real and not observe(real)['gone']:
                    raise Refused('cannot recover emergency while takeover candidate is live')
                data['handoverCommitted'] = False
                data['phase'] = 'fallback'
            args = ['systemd-run', '--user', '--unit=' + name, '--slice=session.slice', '--collect',
                    '--property=KillMode=control-group', '--property=TimeoutStopSec=2s',
                    '--property=SendSIGKILL=yes', '--property=ExitType=cgroup']
            environment = dict(data['environment'], ATMOSPHERA_LOCK_SESSION=data['session'],
                               ATMOSPHERA_LOCK_GENERATION=data['generation'], ATMOSPHERA_LOCK_ROLE=role,
                                 ATMOSPHERA_LOCK_ADAPTER=str(Path(__file__).resolve()))
            report_info = prepare_report(session.escaped + '-' + data['generation'] + '-' + role) if role in ('real', 'emergency') else None
            if role == 'real' and data['snapshot']['adapter'] == 'bundled' and data.get('settingsPath'):
                environment['ATMOSPHERA_LOCK_SETTINGS_FILE'] = data['settingsPath']
            args += ['--setenv=' + key + '=' + value for key, value in environment.items()]
            startup_deadline = 'none'
            if role == 'real' and data['snapshot']['adapter'] == 'bundled':
                startup_deadline = str(data['deadline'])
            elif role in ('prehook', 'unlockhook'):
                startup_deadline = str(time.monotonic() + 5)
            args += ['--', sys.executable, str(Path(__file__).resolve()), 'run', '--generation',
                     data['generation'], '--deadline', startup_deadline,
                     '--', 'sh', '-c', job['command']]
            try:
                command(args)
            except BaseException:
                if report_info:
                    Path(report_info['path']).unlink(missing_ok=True)
                raise
            identity = unit_status(name)
            if not identity['InvocationID'] or not identity['ControlGroup']:
                raise Refused('new unit has no invocation/cgroup identity')
            record = {'name': name, 'identity': identity, 'members': cgroup_members(identity['ControlGroup']),
                       'startedAt': time.monotonic(), 'grant': role == 'emergency', 'retire': False, 'client': None}
            if report_info:
                record['reportInfo'] = report_info
            if previous:
                data.setdefault('retiredInvocations', []).append(previous)
            data['units'][role] = record
            if role == 'emergency':
                record['probeEvents'] = job.get('events', [])
                for event in job.get('events', []):
                    data.setdefault('probeEvents', {})[event] = identity['InvocationID']
            session.write(data)
            return record
        if operation == 'client':
            pid = int(job['pid'])
            if os.getppid() != pid:
                raise Refused('client publication must come from its own process')
            record = valid_client(data, role, pid)
            payload = job['status']
            if payload.get('session') != data['session'] or payload.get('generation') != data['generation'] or payload.get('role') != role:
                raise Refused('client protocol identity mismatch')
            record['client'] = {key: payload.get(key) is True for key in CLIENT_FIELDS}
            settlement = payload.get('settlement', '')
            record['client']['settlement'] = settlement if settlement in ('finished', 'retired', 'authenticated-unlock', 'authentication-revoked', 'stale-generation') else ''
            record['client']['observedAt'] = time.monotonic()
            refresh_report(data, role, record)
            if role == 'real' and time.monotonic() >= data['deadline'] and not record['grant'] and not record.get('everSecure'):
                record['retire'] = True
            session.write(data)
            return client_reply(data, role)
        if operation == 'grant':
            record = data['units'][role]
            if data['phase'] in ('unlocking', 'settled') or record['retire']:
                return {'granted': False}
            if role == 'real' and time.monotonic() >= data['deadline']:
                return {'granted': False}
            if not record.get('client') or not record['client']['ready'] or observe(record)['gone']:
                return {'granted': False}
            other = data['units'].get('emergency' if role == 'real' else 'real')
            if role == 'real' and other and data['handoverCommitted'] and not observe(other)['gone']:
                return {'granted': False}
            record['grant'] = True
            session.write(data)
            return {'granted': True}
        if operation == 'handover':
            emergency = data['units'].get('emergency')
            real = data['units'].get('real')
            if (data['phase'] in ('unlocking', 'settled') or data['authRole'] is not None
                    or not emergency or not emergency.get('client') or not emergency['client']['secure']
                    or observe(emergency)['gone'] or not real or not real.get('client')
                    or not real['client']['ready'] or time.monotonic() >= data['deadline']):
                return {'committed': False}
            data['handoverCommitted'] = True
            data['handoverAt'] = time.monotonic()
            data['phase'] = 'handing-over'
            emergency['retire'] = True
            emergency['grant'] = False
            session.write(data)
            return {'committed': True}
        if operation == 'authenticated':
            pid = int(job['pid'])
            if os.getppid() != pid:
                raise Refused('authentication fence must come from its client')
            record = valid_client(data, role, pid)
            if (data['phase'] == 'settled' or record['retire']
                    or (role == 'emergency' and data['handoverCommitted'])
                    or data['authRole'] not in (None, role)):
                return {'unlock': False, 'retire': True}
            # This is a mechanical compare-and-set and stop barrier. Only the
            # caller's private successful-PAM path consumes the returned permit.
            # Merely observing this descriptor can never unlock another client.
            data['authRole'] = role
            data['phase'] = 'unlocking'
            for other in data['units'].values():
                other['grant'] = False
            session.write(data)
            for other_role, other in data['units'].items():
                if other_role != role:
                    other['retire'] = True
                    stop_record(other)
            session.write(data)
            return {'unlock': True, 'retire': False}
        if operation == 'stop':
            record = data['units'][role]
            if (role == 'emergency' and data['snapshot']['adapter'] != 'bundled'
                    and data.get('sessionUnlockObserved') and data['phase'] not in ('unlocking', 'settled')
                    and not observe(record)['gone'] and not (record.get('client') or {}).get('terminal')):
                raise Refused('resolve the in-flight emergency probe before retirement')
            record['grant'] = False
            record['retire'] = True
            session.write(data)
            result = stop_record(record)
            session.write(data)
            return result
        if operation == 'phase':
            if data['phase'] == 'unlocking' and job['phase'] != 'settled':
                return data
            data['phase'] = job['phase']
            session.write(data)
            return data
        if operation == 'intent':
            if data['phase'] not in ('unlocking', 'settled'):
                data['suspendPending'] = data.get('suspendPending', False) or job.get('suspendAfterSecure') is True
                if job.get('unconfirmed') is True and not data.get('sessionUnlockObserved'):
                    # Addendum 07: each request while unconfirmed is one probe event.
                    data['unconfirmedRequests'] = data.get('unconfirmedRequests', 0) + 1
            session.write(data)
            return data
        if operation == 'consume-suspend':
            pending = data.get('suspendPending', False) and data['phase'] not in ('unlocking', 'settled')
            data['suspendPending'] = False
            session.write(data)
            return {'pending': pending}
        if operation == 'sleep-window':
            active = job.get('active') is True
            if (active and not data.get('sleepWindowActive') and data['phase'] not in ('unlocking', 'settled')
                    and not data.get('sessionUnlockObserved')):
                data['sleepWindow'] = data.get('sleepWindow', 0) + 1
            data['sleepWindowActive'] = active
            session.write(data)
            return data
        if operation == 'cover-probe-events':
            record = data['units']['emergency']
            if observe(record)['gone'] or (record.get('client') or {}).get('terminal'):
                return {'covered': False}
            for event in job['events']:
                data.setdefault('probeEvents', {})[event] = record['identity']['InvocationID']
            session.write(data)
            return {'covered': True}
        if operation == 'probe-race':
            record = data['units']['emergency']
            client = record.get('client') or {}
            if observe(record)['gone'] or not client.get('secure') or client.get('terminal'):
                return {'retained': False}
            first = not data.get('probeRaceWon')
            data['probeRaceWon'] = True
            data['sessionUnlockObserved'] = False
            session.write(data)
            return {'retained': True, 'first': first}
        if operation == 'note':
            # Durable owner observations/once-only effects, not lock policy.
            for key in ('contractRequested', 'contractFailed', 'realLaunchFailed', 'lockHookStarted',
                        'unlockHookStarted', 'sessionUnlockObserved'):
                if job.get(key) is True:
                    data[key] = True
            if data.get('contractRequested') and not data.get('contractRequestId'):
                # Unguessable per-generation Locker1 request ID; never the
                # generation token itself, which fences local adapter effects.
                data['contractRequestId'] = secrets.token_hex(16)
            session.write(data)
            return data
        if operation == 'contract-observe':
            # Locker1 v2 observations, fenced by request ID and the bus owner
            # that accepted the request. Presence alone never confirms secure.
            if data['snapshot']['adapter'] != 'contract' or job.get('requestId') != data.get('contractRequestId'):
                raise Refused('stale contract request')
            event = job.get('event')
            owner = job.get('owner')
            if not isinstance(owner, str) or not owner.startswith(':'):
                raise Refused('contract observation lacks a unique bus owner')
            if event == 'requested':
                version = job.get('version')
                if type(version) is not int or version < 1:
                    raise Refused('invalid contract version')
                if data.get('contractOwner') not in (None, owner):
                    data['contractFailed'] = True
                else:
                    data['contractOwner'] = owner
                    data['contractVersion'] = version
            elif data.get('contractOwner') != owner:
                raise Refused('contract owner changed')
            elif data.get('contractVersion', 1) < 2:
                raise Refused('contract version has no correlated observations')
            elif event == 'secured':
                data['contractSecured'] = True
            elif event == 'unlocked':
                if not data.get('contractSecured'):
                    raise Refused('contract unlock without secure history')
                if data['phase'] not in ('unlocking', 'settled'):
                    data['contractUnlocked'] = True
                    data['sessionUnlockObserved'] = True
            elif event == 'failed':
                data['contractFailed'] = True
            else:
                raise Refused('unknown contract observation')
            session.write(data)
            return data
        if operation == 'recover':
            # Only reset a completed authenticated transaction if its holder
            # vanished before publishing protocol teardown. Never unlock here.
            if any(not observe(record)['gone'] for record in data['units'].values()):
                raise Refused('recovery requires every old invocation to be gone')
            data['phase'] = 'fallback'
            data['authRole'] = None
            data['handoverCommitted'] = False
            data['sessionUnlockObserved'] = False
            session.write(data)
            return data
        if operation == 'settle':
            for record in data['units'].values():
                if not observe(record)['gone']:
                    raise Refused('cannot settle while an owned invocation remains')
            data['phase'] = 'settled'
            for record in [*data['units'].values(), *data.get('retiredInvocations', [])]:
                info = record.get('reportInfo')
                if info:
                    path = Path(info['path'])
                    if path.parent != session.root or not path.name.endswith('.report.json'):
                        raise Refused('invalid retired report path')
                    path.unlink(missing_ok=True)
                    record['reportRetired'] = True
            if data.get('settingsPath'):
                expected = session.root / (session.escaped + '-' + data['generation'] + '.settings.json')
                if str(expected) != data['settingsPath']:
                    raise Refused('settings input path identity mismatch')
                expected.unlink(missing_ok=True)
            session.write(data)
            return data
        raise Refused('unknown locker management operation')


def run_unit(args):
    session = Session(os.environ['ATMOSPHERA_LOCK_SESSION'])
    role = os.environ['ATMOSPHERA_LOCK_ROLE']
    # Launch records identity while holding this same lock. A cancellation or
    # authentication that wins before exec fences off the late systemd job.
    with session.locked(args.generation) as data:
        record = data['units'].get(role)
        if not record or data['phase'] == 'settled' or (data['phase'] == 'unlocking' and role != 'unlockhook') or record['retire']:
            return 0
        if record['identity']['InvocationID'] != os.environ.get('INVOCATION_ID'):
            raise Refused('wrapper invocation does not match its launch record')
    child = subprocess.Popen(args.command)
    last_session_check = time.monotonic()
    while True:
        child.poll()
        with session.locked(args.generation) as data:
            record = data['units'][role]
            members = [p for p in cgroup_members(record['identity']['ControlGroup']) if p['pid'] != os.getpid()]
            if not members:
                return child.returncode or 0
            # Once a grant has escaped the wrapper, the client may already be
            # secure before publishing that fact. Never turn startup expiry
            # into an active-lock lifetime. The owner resolves in-flight fate.
            expired = (args.deadline is not None and time.monotonic() >= args.deadline
                       and not record['grant'] and not record.get('everSecure'))
            cancelled = (record['retire'] and not record.get('everSecure')) or data['phase'] == 'settled'
        if expired or cancelled:
            command(['systemctl', '--user', 'stop', '--no-block', session.name(role)])
        if time.monotonic() - last_session_check >= 1:
            last_session_check = time.monotonic()
            result = command(['loginctl', 'show-session', session.session, '-p', 'State', '--value'], check=False)
            if result.returncode or result.stdout.strip() == 'closing':
                command(['systemctl', '--user', 'stop', '--no-block', session.name(role)])
        time.sleep(.1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='mode', required=True)
    sub.add_parser('manage')
    sub.add_parser('prepare-report')
    retire = sub.add_parser('retire-report')
    retire.add_argument('path')
    wrapper = sub.add_parser('run')
    wrapper.add_argument('--generation', required=True)
    wrapper.add_argument('--deadline', required=True)
    wrapper.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    try:
        if args.mode == 'prepare-report':
            identity = proc_identity(os.getppid())
            if identity is None:
                raise Refused('standalone report requires a live parent')
            info = prepare_report('standalone-' + str(identity['pid']) + '-' + identity['start'])
            info.update(schema=1, identity=identity, session=graphical_session(), generation='', role='standalone',
                invocation=os.environ.get('INVOCATION_ID', ''))
            print(json.dumps({'ok': True, 'value': info}, separators=(',', ':')))
            return 0
        if args.mode == 'retire-report':
            # Only the calling standalone client's own report, by exact name.
            identity = proc_identity(os.getppid())
            path = Path(args.path)
            prefix = 'standalone-' + str(identity['pid']) + '-' + identity['start'] + '-' if identity else None
            if args.path and (not prefix or path.parent != runtime_root() or not path.name.startswith(prefix)
                              or not path.name.endswith('.report.json')):
                raise Refused('not this standalone client\'s report')
            if args.path:
                path.unlink(missing_ok=True)
            print(json.dumps({'ok': True, 'value': None}, separators=(',', ':')))
            return 0
        if args.mode == 'run':
            args.deadline = None if args.deadline == 'none' else float(args.deadline)
            if args.command and args.command[0] == '--':
                args.command.pop(0)
            return run_unit(args)
        value = manage(json.load(sys.stdin))
        print(json.dumps({'ok': True, 'value': value}, separators=(',', ':')))
        return 0
    except (OSError, ValueError, KeyError, Refused, subprocess.SubprocessError) as error:
        print(json.dumps({'ok': False, 'error': str(error)}, separators=(',', ':')))
        return 1


if __name__ == '__main__':
    sys.exit(main())
