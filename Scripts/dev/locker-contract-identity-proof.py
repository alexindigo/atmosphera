#!/usr/bin/env python3
"""Guest-only real private-bus owner replacement controls, without native locks."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

from locker_test_support import require_guest


ROOT = r'''
import QtQuick
import Quickshell
import DBus 1.0
import qs.Services.Locker
ShellRoot {
  id: root
  property bool started: false
  property string scenario: Quickshell.env("LOCKER_REVIEW_CASE")
  Timer {
    interval: 10
    repeat: true
    running: !root.started
    onTriggered: {
      if (!LockerService.contractAvailable) return;
      root.started = true;
      var done = function(result) {
        if (root.scenario === "signals-replacement") {
          SessionBus.asyncCall({service: "app.atmosphera.Locker", path: "/app/atmosphera/Locker",
            iface: "app.atmosphera.Fixture", member: "Switch", arguments: [], signature: ""});
          signalCheck.start();
          return;
        }
        console.log("CONTRACT_IDENTITY_RESULT " + JSON.stringify(result));
        Qt.quit();
      };
      if (root.scenario === "query-replacement" || root.scenario === "query-normal" || root.scenario === "signals-replacement")
        LockerService.queryContract("request", done);
      else
        LockerService.requestContract("request", done);
    }
  }
  Timer {
    id: signalCheck
    interval: 300
    onTriggered: {
      var observations = LockerService.contractObservations;
      console.log("CONTRACT_IDENTITY_RESULT " + JSON.stringify({ok: !observations.old && observations.current?.secured === true,
        owner: observations.current?.owner}));
      Qt.quit();
    }
  }
  Timer { interval: 5000; running: true; onTriggered: Qt.exit(2) }
}
'''


def driver(shell, scenario, work):
    import dbus
    import dbus.mainloop.glib
    import dbus.service
    from gi.repository import GLib
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    a, b = dbus.SessionBus(private=True), dbus.SessionBus(private=True)
    name = 'app.atmosphera.Locker'
    iface = name + '1'
    a.request_name(name, dbus.bus.NAME_FLAG_ALLOW_REPLACEMENT | dbus.bus.NAME_FLAG_DO_NOT_QUEUE)
    events = []
    replaced = False

    def replace():
        nonlocal replaced
        if not replaced:
            assert b.request_name(name, dbus.bus.NAME_FLAG_REPLACE_EXISTING | dbus.bus.NAME_FLAG_DO_NOT_QUEUE) == 1
            replaced = True
        return False

    class Locker(dbus.service.Object):
        def __init__(self, bus, label):
            super().__init__(bus, '/app/atmosphera/Locker')
            self.label = label

        @dbus.service.method(iface, in_signature='s', out_signature='s', async_callbacks=('ok', 'error'))
        def RequestState(self, request, ok, error):
            events.append([self.label, 'RequestState'])
            if scenario == 'query-replacement':
                replace()
            GLib.timeout_add(100, lambda: (ok('secure'), False)[1])

        @dbus.service.method(dbus.PROPERTIES_IFACE, in_signature='ss', out_signature='v', async_callbacks=('ok', 'error'))
        def Get(self, interface, prop, ok, error):
            events.append([self.label, 'Get'])
            if scenario == 'version-replacement' and self.label == 'A':
                replace()
            GLib.timeout_add(100, lambda: (ok(dbus.Int32(2)), False)[1])

        @dbus.service.method(dbus.PROPERTIES_IFACE, in_signature='s', out_signature='a{sv}')
        def GetAll(self, interface):
            return {'Version': dbus.Int32(2)}

        @dbus.service.method(iface, in_signature='s', out_signature='', async_callbacks=('ok', 'error'))
        def LockRequest(self, request, ok, error):
            events.append([self.label, 'LockRequest'])
            if scenario == 'lock-replacement' and self.label == 'A':
                replace()
            GLib.timeout_add(100, lambda: (ok(), False)[1])

        @dbus.service.method(iface, in_signature='', out_signature='')
        def Lock(self):
            events.append([self.label, 'Lock'])

        @dbus.service.signal(iface, signature='s')
        def Secured(self, request):
            pass

        @dbus.service.method('app.atmosphera.Fixture', in_signature='', out_signature='')
        def Switch(self):
            replace()
            def emit():
                services[0].Secured('old')
                services[1].Secured('current')
                return False
            GLib.timeout_add(30, emit)

    services = [Locker(a, 'A'), Locker(b, 'B')]
    loop = GLib.MainLoop()
    with (work / (scenario + '.log')).open('w') as log:
        child = subprocess.Popen(['qs', '-p', str(shell), '--no-color'], stdout=log, stderr=log,
            env=dict(os.environ, LOCKER_REVIEW_CASE=scenario, QT_QPA_PLATFORM='offscreen'))
        def check():
            if child.poll() is not None:
                loop.quit()
                return False
            return True
        GLib.timeout_add(10, check)
        loop.run()
    text = (work / (scenario + '.log')).read_text()
    lines = [line.split('CONTRACT_IDENTITY_RESULT ', 1)[1] for line in text.splitlines() if 'CONTRACT_IDENTITY_RESULT ' in line]
    result = json.loads(lines[0]) if len(lines) == 1 else {}
    normal = scenario in ('query-normal', 'request-normal', 'signals-replacement')
    passed = child.returncode == 0 and result.get('ok') is normal and not any(row[0] == 'B' for row in events)
    if normal:
        passed = passed and result.get('owner') == (b if scenario == 'signals-replacement' else a).get_unique_name()
    row = dict(scenario=scenario, passed=passed, result=result, events=events, exitCode=child.returncode)
    (work / (scenario + '.json')).write_text(json.dumps(row, indent=2))
    print(json.dumps(row), flush=True)
    assert services
    return 0 if passed else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--driver', type=Path)
    parser.add_argument('--scenario')
    args = parser.parse_args()
    if args.driver:
        return driver(args.driver, args.scenario, args.work)
    source, work = require_guest(args.work, args.source)
    shell = work / 'shell'
    (shell / 'Services/Locker').mkdir(parents=True)
    (shell / 'Commons').mkdir()
    shutil.copyfile(source / 'Services/Locker/LockerService.qml', shell / 'Services/Locker/LockerService.qml')
    (shell / 'Commons/Logger.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { '
        'function i(tag, message) {} function w(tag, message) {} }\n')
    (shell / 'shell.qml').write_text(ROOT)
    results = []
    for scenario in ('query-normal', 'request-normal', 'query-replacement', 'version-replacement', 'lock-replacement', 'signals-replacement'):
        process = subprocess.run(['dbus-run-session', '--', sys.executable, '-B', __file__,
            '--driver', str(shell), '--scenario', scenario, '--work', str(work)],
            text=True, capture_output=True, timeout=15)
        print(process.stdout, end='', flush=True)
        (work / (scenario + '-driver.log')).write_text(process.stdout + process.stderr)
        results.append(json.loads((work / (scenario + '.json')).read_text()))
    (work / 'result.json').write_text(json.dumps(results, indent=2))
    return 0 if all(row['passed'] for row in results) else 1


if __name__ == '__main__':
    raise SystemExit(main())
