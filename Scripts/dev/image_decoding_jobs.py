"""Single-owner durable VM jobs for long image regression cohorts."""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

from guest_profile import HeadlessWaylandProfile, ProcessIdentity, ProfileBlocked
from image_decoding_evidence import source_manifest


LONG_CASES = {'all', 'plugins', 'packaging', 'shell', 'chooser-wallpaper'}


def write(path, value):
    pending = path.with_suffix('.pending')
    pending.write_text(json.dumps(value, indent=2) + '\n')
    pending.replace(path)


def identity(args, profile):
    return dict(argv=sys.argv[1:], profile=profile.record(), inputs={key: source_manifest(path)['sha256'] for key, path in
                (('source', args.source), ('plugins', args.plugins), ('baselineSource', args.baseline_source),
                 ('baselinePlugins', args.baseline_plugins)) if path is not None})


def in_owned_job():
    unit = os.environ.get('ATMOSPHERA_IMAGE_JOB', '')
    return unit.startswith('image-decoding-') and any(
        line.rstrip().endswith('/' + unit + '.service') for line in Path('/proc/self/cgroup').read_text().splitlines())


def linger_lease(profile, unit, control, acquire):
    """The last owned job restores the one original Linger value."""
    lock = profile.journal_base / '.image-decoding-linger.lock'
    state = profile.journal_base / '.image-decoding-linger.json'
    with lock.open('a') as stream:
        fcntl.flock(stream, fcntl.LOCK_EX)
        data = json.loads(state.read_text()) if state.exists() else None
        if acquire:
            if data is None:
                original = subprocess.run(['loginctl', 'show-user', str(profile.uid), '-p', 'Linger', '--value'],
                                          capture_output=True, text=True, check=True, timeout=15).stdout.strip()
                if original not in ('yes', 'no'):
                    raise ProfileBlocked('could not capture original Linger')
                data = dict(original=original, owners={})
            if unit in data['owners']:
                raise ProfileBlocked('job already owns a Linger lease')
            data['owners'][unit] = str(control)
            # Persist before the mutation, so an interrupted acquisition remains
            # recoverable rather than forgetting the original account setting.
            write(state, data)
            if data['original'] == 'no':
                subprocess.run(['sudo', '-n', 'loginctl', 'enable-linger', str(profile.uid)], check=True, timeout=15)
            return data['original']
        if data is None or data['owners'].get(unit) != str(control):
            raise ProfileBlocked('missing matching Linger lease')
        del data['owners'][unit]
        if data['owners']:
            write(state, data)
        else:
            if data['original'] == 'no':
                subprocess.run(['sudo', '-n', 'loginctl', 'disable-linger', str(profile.uid)], check=True, timeout=15)
            state.unlink()
        return data['original']


def supervise(args, profile):
    """Return a completed job's rc, or None when this process executes the case.

    Reattaching the identical invocation joins its persisted job, never relaunches
    it. A dead job without an exit receipt is a failure, not a retry invitation.
    Container CI is already supervised by its bounded container invocation.
    """
    if args.job_control or args.case not in LONG_CASES or isinstance(profile, HeadlessWaylandProfile) or in_owned_job():
        return None
    control = args.output.with_name(args.output.name + '.control')
    for value, parent in ((args.output, profile.journal_base), (control, profile.journal_base), (args.work_root, profile.work_base)):
        if value != value.resolve() or not value.is_relative_to(parent) or value == parent:
            raise ProfileBlocked('canonical owned job paths required')
    contract = identity(args, profile)
    unit = 'image-decoding-' + hashlib.sha256(str(args.output).encode()).hexdigest()[:16]
    if control.exists():
        if json.loads((control / 'contract.json').read_text()) != contract:
            raise ProfileBlocked('existing job has different inputs; retain it and use a fresh output')
        print('Joining ' + unit + ' at ' + str(control), flush=True)
    else:
        if args.output.exists() or args.work_root.exists():
            raise ProfileBlocked('fresh output/work required before job launch')
        control.mkdir(parents=True, mode=0o700)
        write(control / 'contract.json', contract)
        linger = linger_lease(profile, unit, control, True)
        write(control / 'supervisor.json', dict(unit=unit, originalLinger=linger))
        argv = ['systemd-run', '--user', '--unit=' + unit, '--property=KillMode=control-group',
                '--property=WorkingDirectory=' + str(args.source),
                '--property=StandardOutput=append:' + str(control / 'job.log'), '--property=StandardError=inherit',
                '--setenv=TMPDIR=' + os.environ['TMPDIR'], '--setenv=QML_DISABLE_DISK_CACHE=1',
                '--setenv=ATMOSPHERA_IMAGE_JOB=' + unit, sys.executable, '-B', str(Path(sys.argv[0]).resolve()),
                *sys.argv[1:], '--job-control', str(control)]
        launch = subprocess.run(argv, capture_output=True, text=True, timeout=30)
        (control / 'launch.log').write_text(launch.stdout + launch.stderr)
        if launch.returncode:
            linger_lease(profile, unit, control, False)
            raise RuntimeError('could not launch owned image job: ' + launch.stderr)
    last = None
    while not (control / 'exit.json').exists():
        observed = subprocess.run(['systemctl', '--user', 'show', unit, '-p', 'ActiveState', '--value'],
                                  capture_output=True, text=True, check=True, timeout=15).stdout.strip()
        if observed in ('inactive', 'failed'):
            # Re-read after the unit state; an orderly exit writes its receipt
            # before the service becomes inactive.
            if not (control / 'exit.json').exists():
                raise RuntimeError('owned image job ended without an exit receipt: ' + str(control))
        captured = control / 'identity.json'
        if captured.exists() and not (control / 'exit.json').exists():
            saved = json.loads(captured.read_text())
            process = ProcessIdentity(**dict(saved['process'], argv=tuple(saved['process']['argv'])))
            try:
                actual = ProcessIdentity.read(process.pid)
                cgroup = (Path('/proc') / str(process.pid) / 'cgroup').read_text()
            except (OSError, ProcessLookupError):
                if not (control / 'exit.json').exists():
                    raise ProfileBlocked('owned worker disappeared without exit evidence')
            else:
                if actual != process or cgroup != saved['cgroup']:
                    raise ProfileBlocked('owned worker identity/cgroup changed')
        status = args.output / 'status.json'
        if status.exists():
            data = json.loads(status.read_text())
            progress = (data['state'], len(data['cases']))
            if progress != last:
                print('JOB ' + unit + ': ' + data['state'] + ', ' + str(progress[1]) + ' completed checks', flush=True)
                last = progress
        time.sleep(.5)
    result = json.loads((control / 'exit.json').read_text())
    print((control / 'job.log').read_text(), end='', flush=True)
    return result['exit']


class Worker:
    def __init__(self, args, profile):
        self.args, self.profile, self.lock = args, profile, None

    def __enter__(self):
        control = self.args.job_control
        if control is None:
            return self
        if not in_owned_job() or control != control.resolve() or not control.is_relative_to(self.profile.journal_base):
            raise ProfileBlocked('job worker is not in its recorded owned unit')
        self.lock = (control / 'lock').open('a')
        fcntl.flock(self.lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        write(control / 'identity.json', dict(process=ProcessIdentity.read(os.getpid()).record(),
                                             cgroup=Path('/proc/self/cgroup').read_text()))
        return self

    def __exit__(self, kind, error, traceback):
        control = self.args.job_control
        if control is not None:
            supervisor = json.loads((control / 'supervisor.json').read_text())
            original = supervisor['originalLinger']
            restoration_error = ''
            try:
                linger_lease(self.profile, supervisor['unit'], control, False)
            except Exception as failure:
                restoration_error = repr(failure)
            code = 0 if kind is None else 1
            if restoration_error:
                code = 1
            write(control / 'exit.json', dict(exit=code, error=repr(error) if error else '',
                                             originalLinger=original, lingerRestored=not restoration_error,
                                             restorationError=restoration_error))
            self.lock.close()
            if code and kind is None:
                raise RuntimeError('could not restore original job Linger')
