"""Real logind sleep/inhibitor path with a guest-only no-kernel-sleep barrier."""
import json
from pathlib import Path

from locker_test_support import run, wait_for


class SleepHarness:
    def __init__(self, source, work):
        self.source, self.work = source, work
        self.override = Path('/run/systemd/system/systemd-suspend.service.d/90-locker-proof.conf')
        self.installed = False
        self.original = run(['systemctl', 'show', 'systemd-suspend.service', '-p', 'ExecStart', '--value']).stdout

    def install(self):
        assert not self.override.exists(), 'another sleep fixture is installed'
        assert run(['systemctl', 'show', 'systemd-suspend.service', '-p', 'ActiveState', '--value']).stdout.strip() == 'inactive'
        fixture = self.source / 'Scripts/dev/fixtures/locker-sleep-service.py'
        # JSON double quotes use the same escaping for these systemd argument
        # bytes; double dollars/specifiers keep paths literal through ExecStart.
        def argument(path):
            return json.dumps(str(path).replace('$', '$$').replace('%', '%%'), ensure_ascii=False)
        self.content = '[Service]\nExecStart=\nExecStart=/usr/bin/python3 -B ' + argument(fixture) + ' --work ' + argument(self.work) + '\n'
        candidate = self.work / 'sleep-service-override.conf'
        candidate.write_text(self.content)
        run(['sudo', '-n', 'install', '-Dm644', str(candidate), str(self.override)])
        self.installed = True
        run(['sudo', '-n', 'systemctl', 'daemon-reload'])
        effective = run(['systemctl', 'show', 'systemd-suspend.service', '-p', 'ExecStart', '--value']).stdout
        assert str(fixture) in effective and '/usr/lib/systemd/systemd-sleep' not in effective, effective
        (self.work / 'sleep-service-effective.json').write_text(json.dumps({'original': self.original, 'fixture': effective}))

    def events(self):
        path = self.work / 'inhibitor-events.jsonl'
        complete = path.read_text().rpartition('\n')[0] if path.exists() else ''
        return [json.loads(line) for line in complete.splitlines()]

    def inhibitors(self, pid):
        import dbus
        manager = dbus.Interface(dbus.SystemBus().get_object('org.freedesktop.login1', '/org/freedesktop/login1'),
            'org.freedesktop.login1.Manager')
        return [list(row) for row in manager.ListInhibitors() if int(row[5]) == pid]

    def held(self):
        acquired = wait_for(lambda: next((row for row in self.events() if row['value']['event'] == 'acquired'), None), 15)
        self.pid = acquired['pid']
        rows = self.inhibitors(self.pid)
        assert len(rows) == 1 and rows[0][0] == 'sleep' and rows[0][3] == 'delay', rows
        (self.work / 'inhibitor-held.json').write_text(json.dumps({'pid': self.pid, 'rows': rows, 'event': acquired}, indent=2))

    def entered(self, native_secure):
        path = self.work / 'sleep-service-entered.json'
        wait_for(path.exists, 20)
        entered = json.loads(path.read_text())
        released = wait_for(lambda: next((row for row in self.events() if row['pid'] == self.pid and row['value']['event'] == 'released'), None), 10)
        assert released['value']['secure'], 'delay inhibitor released without confirmed secure'
        assert native_secure <= released['value']['closeMonotonic'] <= entered['monotonic'], 'secure/release/sleep ordering violated'
        assert not self.inhibitors(self.pid), 'real delay inhibitor fd remained held after secure release'
        (self.work / 'inhibitor-ordering.json').write_text(json.dumps({'nativeSecure': native_secure,
            'released': released, 'sleepServiceEntered': entered, 'remainingInhibitors': []}, indent=2))
        (self.work / 'release-sleep-service').touch(mode=0o600)

    def close(self):
        if not self.installed:
            return
        try:
            (self.work / 'release-sleep-service').touch(mode=0o600)
            wait_for(lambda: run(['systemctl', 'show', 'systemd-suspend.service', '-p', 'ActiveState', '--value']).stdout.strip() in ('inactive', 'failed'), 65)
        finally:
            if self.override.exists():
                assert self.override.read_text() == self.content, 'sleep fixture changed ownership'
                run(['sudo', '-n', 'rm', '--', str(self.override)])
            run(['sudo', '-n', 'systemctl', 'daemon-reload'])
        restored = run(['systemctl', 'show', 'systemd-suspend.service', '-p', 'ExecStart', '--value']).stdout
        assert restored == self.original, 'original sleep service was not restored'
        (self.work / 'sleep-service-restored.json').write_text(json.dumps({'restored': restored, 'overrideAbsent': not self.override.exists()}))
