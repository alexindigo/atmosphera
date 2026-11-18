#!/usr/bin/env python3
"""Guest-only controlled async adapter receipts against the actual QML owner.

No native lock or authentication is simulated as security evidence. These
controls prove request/settings retention at the adapter acknowledgment edge.
"""
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
  property var beginJob: null
  property var beginReply: null
  property int begins: 0
  property int intents: 0
  property int settingsRevision: 0
  property int suspendCompletions: 0
  property int ticks: 0
  property bool intentRejected: false
  property bool sleeping: false
  property bool finished: false

  function respond(callback, value, ok) {
    Qt.callLater(function () {
      callback({stdout: JSON.stringify(ok === false ? {ok: false, error: "controlled refusal"}
        : {ok: true, value: value})});
    });
  }

  function view() {
    return {descriptor: descriptor, now: 0,
      authenticatedUnlockObserved: descriptor && descriptor.phase === "unlocking",
      units: descriptor ? {real: {sameInvocation: true, gone: descriptor.phase === "unlocking" || descriptor.phase === "settled"}} : {}};
  }

  function fresh(snapshot) {
    return {generation: "fixture-" + begins, phase: "starting", requestedAt: 0,
      emergencyAt: 3, deadline: 30, snapshot: snapshot, suspendPending: snapshot.suspendAfterSecure,
      units: {real: {grant: true, client: {secure: true, terminal: false}}}};
  }

  function receive(job, callback) {
    if (job.operation === "begin") {
      begins++;
      beginJob = job;
      if (scenario === "persistent-begin-refusal") {
        respond(callback, null, false);
        return;
      }
      if (begins === 1 && scenario === "late-begin") {
        beginReply = callback;
        Qt.callLater(function () {
          LockOwnerService.requestLock("later", true);
          LockOwnerService.observeSleepWindow(true);
          Settings.data.general.revision = 2;
          Settings.effectiveSettingsChanged("general");
          root.descriptor = fresh(job.snapshot);
          root.respond(root.beginReply, root.descriptor);
        });
        return;
      }
      if (begins === 1 && scenario === "begin-refusal") {
        respond(callback, null, false);
        return;
      }
      descriptor = fresh(job.snapshot);
      respond(callback, descriptor);
    } else if (job.operation === "inspect") {
      respond(callback, view());
    } else if (job.operation === "intent") {
      intents++;
      if (scenario === "persistent-intent-refusal") {
        respond(callback, null, false);
        return;
      }
      if (scenario === "intent-refusal" && !intentRejected) {
        intentRejected = true;
        descriptor.phase = "unlocking";
      } else if (descriptor.phase !== "unlocking") {
        descriptor.suspendPending = descriptor.suspendPending || job.suspendAfterSecure;
      }
      respond(callback, descriptor);
    } else if (job.operation === "sleep-window") {
      sleeping = job.active;
      respond(callback, descriptor);
    } else if (job.operation === "settings") {
      settingsRevision = JSON.parse(job.settingsJson).general.revision;
      respond(callback, {revision: settingsRevision});
    } else if (job.operation === "note") {
      descriptor.lockHookStarted = true;
      respond(callback, descriptor);
    } else if (job.operation === "consume-suspend") {
      var pending = descriptor.suspendPending;
      descriptor.suspendPending = false;
      respond(callback, {pending: pending});
    } else if (job.operation === "settle") {
      descriptor.phase = "settled";
      respond(callback, descriptor);
    } else {
      throw new Error("unexpected adapter operation: " + job.operation);
    }
  }

  Connections {
    target: LockOwnerService
    function onSuspendReady() { root.suspendCompletions++; }
  }

  Component.onCompleted: {
    Adapter.attach(root);
    LockOwnerService._session = "fixture-session";
    LockOwnerService._initialized = true;
    LockOwnerService._busy = true;
    if (scenario === "unlocking-request" || scenario === "intent-refusal" || scenario === "persistent-intent-refusal") {
      descriptor = fresh({adapter: "bundled"});
      descriptor.phase = scenario === "unlocking-request" ? "unlocking" : "starting";
    }
    LockOwnerService.requestLock("first", scenario !== "late-begin");
    LockOwnerService._busy = false;
    LockOwnerService.pump();
  }

  Timer {
    interval: 20
    repeat: true
    running: !root.finished
    onTriggered: {
      root.ticks++;
      if (root.scenario === "persistent-begin-refusal" || root.scenario === "persistent-intent-refusal") {
        // A failed receipt must retain its request without scheduling another
        // process immediately. The existing owner timer owns retry cadence.
        if (root.ticks < 2)
          return;
        var attempts = root.scenario === "persistent-begin-refusal" ? root.begins : root.intents;
        root.finished = true;
        LockOwnerService._initialized = false;
        var retained = LockOwnerService._pendingRequest;
        console.log("OWNER_INTENT_RESULT " + JSON.stringify({passed: attempts === 1 && retained,
          scenario: root.scenario, attempts: attempts, retained: retained}));
        Qt.exit(attempts === 1 && retained ? 0 : 1);
        return;
      }
      var passed = root.suspendCompletions === 1;
      if (root.scenario === "late-begin")
        passed = passed && root.settingsRevision === 2 && root.sleeping;
      else if (root.scenario === "begin-refusal")
        passed = passed && root.begins === 2;
      else
        passed = passed && root.begins === 1;
      if (!passed && root.ticks < 100)
        return;
      root.finished = true;
      LockOwnerService._initialized = false;
      console.log("OWNER_INTENT_RESULT " + JSON.stringify({passed: passed,
        scenario: root.scenario, begins: root.begins, suspend: root.suspendCompletions,
        settingsRevision: root.settingsRevision, sleeping: root.sleeping}));
      Qt.exit(passed ? 0 : 1);
    }
  }
}
'''

SETTINGS = '''pragma Singleton
import QtQuick
QtObject {
  property var data: ({settingsVersion: 1, general: {lockScreenEnabled: true,
    externalLockCommand: "", revision: 1}, sessionMenu: {powerOptions: []}})
  property var store: ({inputPaths: [["general"]], copyValue: function(value) { return value; }})
  signal effectiveSettingsChanged(string section)
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
    (shell / 'Commons/Settings.qml').write_text(SETTINGS)
    (shell / 'Commons/Logger.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { '
        'function i(tag, message) {} function e(tag, message) {} }\n')
    (shell / 'Services/Control/HooksService.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { '
        'function handlerFor(name) { return null; } function listenerCommandFor(a, b) { return ""; } }\n')
    (shell / 'Services/Locker/LockerService.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { '
        'property bool contractAvailable: false; property var contractObservations: ({}); '
        'signal sessionUnlocked; function observeSession(id) {} }\n')
    (shell / 'shell.qml').write_text(ROOT)
    results = []
    for scenario in ('late-begin', 'begin-refusal', 'unlocking-request', 'intent-refusal',
                     'persistent-begin-refusal', 'persistent-intent-refusal'):
        env = dict(os.environ, LOCKER_REVIEW_CASE=scenario, QT_QPA_PLATFORM='offscreen')
        process = subprocess.run(['qs', '-p', str(shell), '--no-color'], env=env,
            check=False, text=True, capture_output=True, timeout=15)
        log = process.stdout + process.stderr
        (work / (scenario + '.log')).write_text(log)
        lines = [line.split('OWNER_INTENT_RESULT ', 1)[1] for line in log.splitlines() if 'OWNER_INTENT_RESULT ' in line]
        row = json.loads(lines[0]) if len(lines) == 1 else dict(passed=False, scenario=scenario, missingResult=True)
        row['exitCode'] = process.returncode
        results.append(row)
        print(json.dumps(row), flush=True)
    (work / 'result.json').write_text(json.dumps(results, indent=2))
    return 0 if all(row['passed'] and row['exitCode'] == 0 for row in results) else 1


if __name__ == '__main__':
    raise SystemExit(main())
