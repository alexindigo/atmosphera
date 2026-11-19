#!/usr/bin/env python3
"""Actual QML-owner progress under refused auxiliary receipts, not native auth."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess

from locker_test_support import require_guest


ROOT = r'''
import QtQuick
import Quickshell
import qs.Commons
import qs.Services.Locker
import "Helpers/OwnedProcess.js" as Adapter
ShellRoot {
  id: root
  property string scenario: Quickshell.env("LOCKER_REVIEW_CASE")
  property var descriptor: ({generation: "g", phase: "starting", requestedAt: 0, emergencyAt: 3,
    deadline: 30, snapshot: {adapter: "bundled"}, units: {}, lockHookStarted: true,
    contractRequested: true, contractRequestId: "request", contractOwner: ":1.10",
    contractVersion: 2, contractSecured: false, sleepWindow: 0, sleepWindowActive: false})
  property int probes: 0
  property int writes: 0
  property int sleepWrites: 0
  property int settlements: 0
  property int ticks: 0
  property bool finished: false
  property bool lastSleep: false
  property bool premature: false
  function respond(callback, value, ok) {
    Qt.callLater(function() { callback({stdout: JSON.stringify(ok === false
      ? {ok: false, error: "controlled transient IO"} : {ok: true, value: value})}); });
  }
  function receive(job, callback) {
    if (job.operation === "inspect") {
      respond(callback, {descriptor: descriptor, units: descriptor.units.real ? {real: {sameInvocation: true, gone: false}}
        : descriptor.units.emergency ? {emergency: {sameInvocation: true, gone: false}} : {},
        now: scenario.indexOf("sleep-") === 0 || ticks < 3 ? 1 : 4});
    } else if (job.operation === "launch" && job.role === "emergency") {
      probes++;
      LockOwnerService._initialized = false;
      respond(callback, descriptor);
    } else if (job.operation === "settle") {
      settlements++;
      descriptor.phase = "settled";
      LockOwnerService._initialized = false;
      respond(callback, descriptor);
    } else if (job.operation === "sleep-window") {
      sleepWrites++;
      if (sleepWrites === 1) {
        if (scenario === "sleep-newer") LockOwnerService.observeSleepWindow(false, "");
        respond(callback, null, false);
      } else {
        lastSleep = job.active;
        descriptor.sleepWindowActive = job.active;
        if (job.active) descriptor.sleepWindow++;
        respond(callback, descriptor);
      }
    } else if (job.operation === "contract-observe" && scenario === "accepted-unlock-retry") {
      writes++;
      if (writes === 1) {
        LockerService.contractOwner = ":1.20";
        respond(callback, null, false);
      } else {
        if (job.owner !== ":1.10" || job.event !== "unlocked") premature = true;
        descriptor.contractUnlocked = true;
        descriptor.sessionUnlockObserved = true;
        respond(callback, descriptor);
      }
    } else {
      writes++;
      respond(callback, null, false);
    }
  }
  Component.onCompleted: {
    Adapter.attach(root);
    if (scenario === "prehook") descriptor.snapshot.prehook = "failing prehook";
    if (scenario === "lockhook") { descriptor.snapshot.lockHook = "failing lockhook"; descriptor.lockHookStarted = false; }
    if (scenario === "note") descriptor.lockHookStarted = false;
    if (scenario === "contract-persist" || scenario === "query-inflight" || scenario === "accepted-unlock-retry") {
      descriptor.snapshot.adapter = "contract";
      LockerService.contractAvailable = true;
    }
    LockOwnerService._session = "session";
    LockOwnerService._initialized = true;
    LockOwnerService._settingsGeneration = "g";
    if (scenario === "settings" || scenario === "settings-secure" || scenario === "settings-ready") LockOwnerService._settingsPending = true;
    if (scenario === "settings-ready")
      descriptor.units.real = {identity: {InvocationID: "real"}, grant: false, client: {ready: true, secure: false}};
    if (scenario === "settings-secure")
      descriptor.units.emergency = {identity: {InvocationID: "emergency"}, client: {secure: true, terminal: false}};
    if (scenario === "intent") LockOwnerService._pendingRequest = true;
    if (scenario === "contract-persist")
      LockerService.contractObservations = {request: {":1.10": {owner: ":1.10", secured: true}}};
    if (scenario === "accepted-unlock-retry") {
      descriptor.contractSecured = true;
      LockerService.contractObservations = {request: {owner: ":1.10", secured: true, unlocked: true,
        ":1.10": {owner: ":1.10", secured: true, unlocked: true},
        ":1.20": {owner: ":1.20", secured: true}}};
    }
    if (scenario !== "query-inflight") LockOwnerService._contractQueried = LockOwnerService.contractKey(descriptor);
    if (scenario.indexOf("sleep-") === 0) {
      descriptor.snapshot.adapter = "opaque";
      descriptor.units.real = {identity: {InvocationID: "real"}, client: {}};
      LockOwnerService.observeSleepWindow(true, "window");
    }
    LockOwnerService.pump();
  }
  Timer {
    interval: 25; repeat: true; running: !root.finished
    onTriggered: {
      root.ticks++;
      LockOwnerService.pump();
      if (root.ticks < 18) return;
      root.finished = true;
      LockOwnerService._initialized = false;
      var passed = root.probes === 1;
      if (root.scenario === "settings-secure") passed = LockOwnerService.secure && root.writes > 0 && root.probes === 0;
      if (root.scenario === "accepted-unlock-retry") passed = root.settlements === 1 && root.writes === 2 && root.probes === 0 && !root.premature;
      if (root.scenario === "sleep-refusal") passed = root.sleepWrites === 2 && root.lastSleep && root.probes === 1;
      if (root.scenario === "sleep-newer") passed = root.sleepWrites === 2 && !root.lastSleep && root.probes === 0;
      console.log("OWNER_PROGRESS_RESULT " + JSON.stringify({scenario: root.scenario, passed: passed,
        probes: root.probes, writes: root.writes, sleepWrites: root.sleepWrites, lastSleep: root.lastSleep,
        settlements: root.settlements, premature: root.premature}));
      Qt.exit(passed ? 0 : 1);
    }
  }
}
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    source, work = require_guest(args.work, args.source)
    shell = work / 'shell'
    for directory in ('Helpers', 'Services/Locker', 'Services/Control', 'Commons'):
        (shell / directory).mkdir(parents=True, exist_ok=True)
    for relative in ('Services/Locker/LockOwnerService.qml', 'Helpers/LockerLifecycle.js', 'Helpers/LockerSettingsInput.js'):
        shutil.copyfile(source / relative, shell / relative)
    (shell / 'Helpers/OwnedProcess.js').write_text('.pragma library\nvar owner = null;\n'
        'function attach(value) { owner = value; }\n'
        'function run(parent, command, input, complete) { owner.receive(JSON.parse(input), complete); }\n')
    (shell / 'Commons/Settings.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { '
        'property var data: ({general: {lockScreenEnabled: true}}); '
        'property var store: ({inputPaths: [["general"]], copyValue: function(v) { return v; }}); '
        'signal effectiveSettingsChanged(string section) }\n')
    (shell / 'Commons/Logger.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { '
        'function i(a,b) {} function e(a,b) {} function w(a,b) {} }\n')
    (shell / 'Services/Control/HooksService.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject {}\n')
    (shell / 'Services/Locker/LockerService.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { '
        'property bool contractAvailable: false; property string contractOwner: ":1.10"; '
        'property var contractObservations: ({}); signal sessionUnlocked; '
        'function queryContract(id, complete) {} function observeSession(id) {} }\n')
    (shell / 'shell.qml').write_text(ROOT)
    results = []
    for scenario in ('settings', 'settings-ready', 'settings-secure', 'prehook', 'lockhook', 'note', 'intent', 'contract-persist',
                     'query-inflight', 'accepted-unlock-retry', 'sleep-refusal', 'sleep-newer'):
        process = subprocess.run(['qs', '-p', str(shell), '--no-color'],
            env=dict(os.environ, LOCKER_REVIEW_CASE=scenario, QT_QPA_PLATFORM='offscreen'),
            check=False, text=True, capture_output=True, timeout=15)
        log = process.stdout + process.stderr
        (work / (scenario + '.log')).write_text(log)
        lines = [line.split('OWNER_PROGRESS_RESULT ', 1)[1] for line in log.splitlines() if 'OWNER_PROGRESS_RESULT ' in line]
        row = json.loads(lines[0]) if len(lines) == 1 else dict(passed=False, scenario=scenario, missingResult=True)
        row['exitCode'] = process.returncode
        results.append(row)
        print(json.dumps(row), flush=True)
    (work / 'result.json').write_text(json.dumps(results, indent=2))
    return 0 if all(row['passed'] and row['exitCode'] == 0 for row in results) else 1


if __name__ == '__main__':
    raise SystemExit(main())
