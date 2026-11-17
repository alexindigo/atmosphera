#!/usr/bin/env python3
"""Guest-only proof of native read-only main-source declarations.

This tests the reusable source capability without activating a new locker path.
It also cold-loads the selected tree's real main root and checks its state IPC.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

from locker_test_support import require_guest, run, wait_for


FIXTURE = '''import QtQuick
import Quickshell
import qs.Commons
ShellRoot {
  id: root
  property bool ran: false
  property int completed: 0
  SettingsStore {
    id: reader
    readOnly: Quickshell.env("PROOF_READONLY") === "1"
    legacyFile: Quickshell.env("ATMOSPHERA_CONFIG_DIR") + "/settings.json"
    overridesDirectory: Quickshell.env("ATMOSPHERA_CONFIG_DIR") + "/settings"
    evidencePath: Quickshell.env("ATMOSPHERA_CACHE_DIR") + "/settings-conflicts"
    homeDirectory: Quickshell.env("HOME")
    defaultFont: Application.font.family
    fixedFont: "monospace"
    onStatusChanged: {
      if (!ready || root.ran) return;
      root.ran = true;
      var rejected = false;
      try { setUser(["general", "compactLockScreen"], true); }
      catch (error) { rejected = true; }
      if (rejected !== readOnly || schema.version !== 0) {
        console.error("FAIL source capability", rejected, readOnly, schema.version);
        Qt.exit(1);
        return;
      }
      save();
      if (readOnly) flush();
      close();
    }
    onCompleted: result => {
      if (["save", "flush", "close"].indexOf(result.operation) === -1) return;
      if ((readOnly && result.status !== "nothing_to_save") ||
          (!readOnly && result.status !== (root.completed === 0 ? "saved" : "nothing_to_save"))) {
        console.error("FAIL source publication", result.operation, result.status);
        Qt.exit(2);
        return;
      }
      root.completed++;
      if (root.completed === (readOnly ? 3 : 2)) {
        console.log("PASS source capability", readOnly);
        Qt.quit();
      }
    }
  }
  Timer { interval: 20000; running: true; onTriggered: { console.error("TIMEOUT", reader.status, reader.error); Qt.exit(3); } }
}
'''


def tree(path):
    return {str(p.relative_to(path)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in path.rglob('*') if p.is_file()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    source, work = require_guest(args.work, args.source)
    entry = source / '.locker-settings-sources-proof.qml'
    created = False
    try:
        with entry.open('x') as output:
            created = True
            output.write(FIXTURE)
        for mode in ('existing', 'missing', 'writer'):
            case = work / mode
            case.mkdir()
            config = case / 'config'
            config.mkdir()
            if mode != 'missing':
                (config / 'settings.json').write_text('{"settingsVersion":26,"general":{"compactLockScreen":false}}')
            before = tree(config)
            env = dict(os.environ, PROOF_READONLY='0' if mode == 'writer' else '1',
                       ATMOSPHERA_CONFIG_DIR=str(config), ATMOSPHERA_CACHE_DIR=str(case / 'cache'),
                       ATMOSPHERA_STATE_DIR=str(case / 'state'))
            result = subprocess.run(['qs', '-p', str(entry), '--no-color'], text=True, capture_output=True, env=env, timeout=30)
            (case / 'journal.txt').write_text(result.stdout + result.stderr)
            assert result.returncode == 0 and 'PASS source capability' in result.stdout + result.stderr, result.stdout + result.stderr
            assert (config / 'settings.json').read_bytes() == b'{"settingsVersion":26,"general":{"compactLockScreen":false}}' if mode != 'missing' else not (config / 'settings.json').exists()
            if mode == 'writer':
                assert json.loads((config / 'settings/general.json').read_text())['compactLockScreen'] is True
            else:
                assert tree(config) == before, 'read-only store published settings/defaults/migrations'
                assert not list(config.rglob('*.lock')) and not list(config.rglob('*.bak'))
    finally:
        if created:
            entry.unlink()

    # The capability's default remains the existing main writer, not a global
    # persistence-policy change. Exercise the actual main root, not the fixture.
    stage = work / 'stage'
    run(['bash', '-eu', '-c', 'source "$1/packaging/aur/package.sh"; package', 'stage', str(source)],
        env=dict(os.environ, srcdir=str(source.parent), _gitname=source.name, pkgdir=str(stage), pkgver='0.9.3'), timeout=60)
    config = work / 'main-config'
    config.mkdir()
    (config / 'settings.json').write_text(json.dumps({'settingsVersion': 62, 'general': {
        'lockOnSuspend': False, 'showChangelogOnStartup': False}, 'idle': {'enabled': False}}))
    environment = dict(os.environ, ATMOSPHERA_CONFIG_DIR=str(config), ATMOSPHERA_CACHE_DIR=str(work / 'main-cache'),
                       ATMOSPHERA_STATE_DIR=str(work / 'main-state'), XDG_CONFIG_DIRS=str(stage / 'etc/xdg') + ':/etc/xdg')
    entry = stage / 'etc/xdg/quickshell/atmosphera/shell.qml'
    unit = 'locker-settings-main-proof.service'
    invocation = None
    try:
        command = ['systemd-run', '--user', '--unit=' + unit, '--collect', '--property=KillMode=control-group', '--property=TimeoutStopSec=2s']
        keys = ('WAYLAND_DISPLAY', 'NIRI_SOCKET', 'HYPRLAND_INSTANCE_SIGNATURE', 'XDG_CURRENT_DESKTOP',
                'XDG_SESSION_TYPE', 'XDG_RUNTIME_DIR', 'DBUS_SESSION_BUS_ADDRESS', 'TMPDIR', 'HOME', 'USER',
                'XDG_CONFIG_DIRS', 'ATMOSPHERA_CONFIG_DIR', 'ATMOSPHERA_CACHE_DIR', 'ATMOSPHERA_STATE_DIR', 'PATH')
        command += ['--setenv=' + key + '=' + environment[key] for key in keys if key in environment]
        run(command + ['--', 'qs', '-p', str(entry), '--no-color'])
        invocation = run(['systemctl', '--user', 'show', unit, '-p', 'InvocationID', '--value']).stdout.strip()
        def ready():
            result = subprocess.run(['qs', 'ipc', '-p', str(entry), 'call', 'state', 'all'], env=environment,
                                    text=True, capture_output=True, timeout=5)
            if result.returncode:
                return None
            try:
                snapshot = json.loads(result.stdout)
                return snapshot if isinstance(snapshot, dict) and isinstance(snapshot.get('settings'), dict) and isinstance(snapshot.get('state'), dict) else None
            except ValueError:
                return None
        snapshot = wait_for(ready, 45)
        (work / 'main-state.json').write_text(json.dumps(snapshot, indent=2))
        assert snapshot['settings']['general']['lockOnSuspend'] is False
        assert run(['systemctl', '--user', 'show', unit, '-p', 'ActiveState', '--value']).stdout.strip() == 'active'
    finally:
        if invocation:
            assert run(['systemctl', '--user', 'show', unit, '-p', 'InvocationID', '--value']).stdout.strip() == invocation
            journal = run(['journalctl', '--user', '-b', '--no-pager', '-o', 'cat', '_SYSTEMD_INVOCATION_ID=' + invocation]).stdout
            (work / 'main-journal.txt').write_text(journal)
            run(['systemctl', '--user', 'stop', unit])
            status = run(['systemctl', '--user', 'show', unit, '-p', 'ActiveState', '-p', 'MainPID', '-p', 'ControlGroup']).stdout
            assert 'ActiveState=inactive' in status and 'MainPID=0' in status and 'ControlGroup=\n' in status
            (work / 'main-final.txt').write_text(status)
    print('PASS settings-sources-and-main', work)


if __name__ == '__main__':
    main()
