#!/usr/bin/env python3
"""Actual QML owner sleep/consume interleavings; not native lock/auth evidence."""
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
  property var descriptor: null
  property var heldInspect: null
  property var heldConsume: null
  property int inspections: 0
  property int consumedAt: 0
  property int suspendedAt: 0
  property int begins: 0
  property int suspends: 0
  property int ticks: 0
  property var confirmations: []
  property bool premature: false
  property bool finished: false
  property var sleepJobs: []

  function copy(value) { return JSON.parse(JSON.stringify(value)); }
  function respond(callback, value) {
    var receipt = copy(value);
    Qt.callLater(function () { callback({stdout: JSON.stringify({ok: true, value: receipt})}); });
  }
  function fresh(snapshot) {
    return {generation: "generation-" + begins, phase: "starting", snapshot: snapshot,
      requestedAt: 0, emergencyAt: 3, deadline: 30, lockHookStarted: true,
      suspendPending: snapshot.suspendAfterSecure, units: {real: {grant: true,
        client: {secure: true, terminal: false}}}};
  }
  function inspect() {
    return {descriptor: descriptor, now: 1, authenticatedUnlockObserved: descriptor.phase === "unlocking",
      units: {real: {sameInvocation: true, gone: descriptor.phase === "unlocking" || descriptor.phase === "settled"}}};
  }
  function authenticate() {
    descriptor.phase = "unlocking";
    descriptor.units.real.client = {secure: false, locked: false, terminal: true, authenticated: true};
  }
  function receive(job, callback) {
    if (job.operation === "inspect") {
      inspections++;
      if ((scenario === "sleep-inflight" || scenario === "resume-then-sleep") && inspections === 1)
        heldInspect = callback;
      else
        respond(callback, inspect());
    } else if (job.operation === "begin") {
      begins++;
      descriptor = fresh(job.snapshot);
      respond(callback, descriptor);
    } else if (job.operation === "consume-suspend") {
      // Like the adapter: a stale generation is refused, and the receipt
      // reports the intent captured before it was cleared.
      if (job.generation !== descriptor.generation) {
        Qt.callLater(function () { callback({stdout: JSON.stringify({ok: false, error: "stale locker generation"})}); });
        return;
      }
      var pending = descriptor.suspendPending === true;
      consumedAt = inspections;
      descriptor.suspendPending = false;
      if (scenario === "suspend-auth" && begins === 0)
        heldConsume = callback;
      else
        respond(callback, {pending: pending});
    } else if (job.operation === "sleep-window") {
      sleepJobs.push(job.active);
      if (job.active && !descriptor.sleepWindowActive)
        descriptor.sleepWindow = (descriptor.sleepWindow || 0) + 1;
      descriptor.sleepWindowActive = job.active;
      respond(callback, descriptor);
    } else if (job.operation === "settings") {
      respond(callback, descriptor);
    } else if (job.operation === "intent") {
      if (descriptor.phase !== "unlocking" && descriptor.phase !== "settled")
        descriptor.suspendPending = descriptor.suspendPending || job.suspendAfterSecure;
      respond(callback, descriptor);
    } else if (job.operation === "settle") {
      descriptor.phase = "settled";
      respond(callback, descriptor);
    } else {
      throw new Error("unexpected operation " + job.operation);
    }
  }
  Connections {
    target: LockOwnerService
    ignoreUnknownSignals: true
    function onSuspendReady() {
      root.suspends++;
      root.suspendedAt = root.inspections;
      if (root.descriptor.phase === "unlocking" || root.descriptor.phase === "settled")
        root.premature = true;
    }
    function onSleepConfirmed(window, confirmed, opaque) {
      if (confirmed) {
        root.confirmations.push({window: window, generation: root.descriptor.generation});
        if (root.scenario === "sleep-inflight" && (window !== "window-2" || root.ticks < 5 || root.descriptor.phase === "unlocking"))
          root.premature = true;
      }
    }
  }
  Component.onCompleted: {
    Adapter.attach(root);
    descriptor = fresh({adapter: "bundled", suspendAfterSecure: scenario.indexOf("suspend-") === 0});
    LockOwnerService._session = "fixture";
    LockOwnerService._initialized = true;
    LockOwnerService._settingsGeneration = descriptor.generation;
    LockOwnerService.pump();
    if (scenario === "sleep-inflight") {
      LockOwnerService.observeSleepWindow(true, "window-1");
      LockOwnerService.observeSleepWindow(true, "window-2");
    }
    if (scenario === "resume-then-sleep") {
      // Resume and the next sleep both arrive while an adapter call is held.
      descriptor.sleepWindow = 1;
      descriptor.sleepWindowActive = true;
      LockOwnerService.observeSleepWindow(false, "");
      LockOwnerService.observeSleepWindow(true, "window-3");
    }
  }
  Timer {
    interval: 20
    repeat: true
    running: !root.finished
    onTriggered: {
      root.ticks++;
      if (root.ticks === 5) {
        if (root.heldInspect && root.scenario === "resume-then-sleep") {
          root.respond(root.heldInspect, root.inspect());
          root.heldInspect = null;
        } else if (root.heldInspect) {
        var old = root.copy(root.inspect());
          root.authenticate();
          root.respond(root.heldInspect, old);
          LockOwnerService.requestLock("prepare-for-sleep", false);
        }
        if (root.heldConsume) {
          root.authenticate();
          root.respond(root.heldConsume, {pending: true});
          root.heldConsume = null;
        }
      }
      LockOwnerService.pump();
      if (root.ticks < 30)
        return;
      var passed = !root.premature;
      if (root.scenario === "resume-then-sleep")
        passed = passed && JSON.stringify(root.sleepJobs) === "[false,true]" && root.descriptor.sleepWindow === 2;
      else if (root.scenario === "sleep-inflight")
        passed = passed && root.confirmations.length > 0 && root.begins === 1
          && root.confirmations.every(function (row) { return row.generation === "generation-1"; });
      else
        passed = passed && root.suspends === 1 && root.suspendedAt > root.consumedAt
          && (root.scenario !== "suspend-auth" || root.begins === 1);
      root.finished = true;
      LockOwnerService._initialized = false;
      console.log("OWNER_SLEEP_RESULT " + JSON.stringify({scenario: root.scenario, passed: passed,
        premature: root.premature, begins: root.begins, suspends: root.suspends,
        consumedAt: root.consumedAt, suspendedAt: root.suspendedAt, confirmations: root.confirmations,
        sleepJobs: root.sleepJobs, sleepWindow: root.descriptor.sleepWindow}));
      Qt.exit(passed ? 0 : 1);
    }
  }
}
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, required=True)
    args = parser.parse_args()
    source, work = require_guest(args.work, Path(__file__).resolve().parents[2])
    shell = work / 'shell'
    for directory in ('Helpers', 'Services/Locker', 'Services/Control', 'Commons'):
        (shell / directory).mkdir(parents=True, exist_ok=True)
    for relative in ('Services/Locker/LockOwnerService.qml', 'Helpers/LockerLifecycle.js', 'Helpers/LockerSettingsInput.js'):
        shutil.copyfile(source / relative, shell / relative)
    (shell / 'Helpers/OwnedProcess.js').write_text('.pragma library\nvar owner = null;\n'
        'function attach(value) { owner = value; }\n'
        'function run(parent, command, input, complete) { owner.receive(JSON.parse(input), complete); }\n')
    (shell / 'Commons/Settings.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { '
        'property var data: ({general: {lockScreenEnabled: true, externalLockCommand: ""}, sessionMenu: {powerOptions: []}}); '
        'property var store: ({inputPaths: [], copyValue: function(value) { return value; }}); '
        'signal effectiveSettingsChanged(string section) }\n')
    (shell / 'Commons/Logger.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { '
        'function i(tag, message) {} function e(tag, message) {} }\n')
    (shell / 'Services/Control/HooksService.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { '
        'function handlerFor(name) { return null; } function listenerCommandFor(a, b) { return ""; } }\n')
    (shell / 'Services/Locker/LockerService.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { '
        'property bool contractAvailable: false; property string contractOwner: ""; property var contractObservations: ({}); '
        'signal sessionUnlocked; function observeSession(id) {} }\n')
    (shell / 'shell.qml').write_text(ROOT)
    results = []
    for scenario in ('sleep-inflight', 'suspend-auth', 'suspend-normal', 'resume-then-sleep'):
        process = subprocess.run(['qs', '-p', str(shell), '--no-color'],
            env=dict(os.environ, LOCKER_REVIEW_CASE=scenario, QT_QPA_PLATFORM='offscreen'),
            check=False, text=True, capture_output=True, timeout=15)
        log = process.stdout + process.stderr
        (work / (scenario + '.log')).write_text(log)
        lines = [line.split('OWNER_SLEEP_RESULT ', 1)[1] for line in log.splitlines() if 'OWNER_SLEEP_RESULT ' in line]
        row = json.loads(lines[0]) if len(lines) == 1 else dict(passed=False, scenario=scenario, missingResult=True)
        row['exitCode'] = process.returncode
        results.append(row)
        print(json.dumps(row), flush=True)
    (work / 'result.json').write_text(json.dumps(results, indent=2))
    return 0 if all(row['passed'] and row['exitCode'] == 0 for row in results) else 1


if __name__ == '__main__':
    raise SystemExit(main())
