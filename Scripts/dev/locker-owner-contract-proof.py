#!/usr/bin/env python3
"""Guest-only owner confirmation controls; not native lock/auth evidence."""
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
  property var descriptor: ({generation: "generation", phase: "starting", snapshot: {adapter: "contract"},
    units: {}, requestedAt: 0, emergencyAt: 3, deadline: 30, lockHookStarted: true,
    contractRequested: true, contractRequestId: "request", contractOwner: ":1.10",
    contractVersion: 2, contractSecured: true, contractFailed: false})
  property var observeReply: null
  property var observeJob: null
  property bool premature: false
  property bool wasSecure: false
  property bool withdrawn: false
  property int probes: 0
  property int settlements: 0
  property int ticks: 0
  property bool finished: false
  property var oldQueryReply: null
  property int sleepConfirmations: 0

  function respond(callback, value) {
    Qt.callLater(function () { callback({stdout: JSON.stringify({ok: true, value: value})}); });
  }
  function apply(job) {
    if (job.event === "secured") descriptor.contractSecured = true;
    if (job.event === "failed") descriptor.contractFailed = true;
    if (job.event === "unlocked") {
      descriptor.contractUnlocked = true;
      descriptor.sessionUnlockObserved = true;
    }
  }
  function receive(job, callback) {
    if (job.operation === "inspect")
      respond(callback, {descriptor: descriptor, units: {}, now: 1});
    else if (job.operation === "contract-observe") {
      if (scenario === "query-persistence" && !observeReply) {
        observeJob = job;
        observeReply = callback;
      } else {
        apply(job);
        respond(callback, descriptor);
      }
    } else if (job.operation === "sleep-window") {
      respond(callback, descriptor);
    } else if (job.operation === "note") {
      descriptor.contractFailed = job.contractFailed || descriptor.contractFailed;
      respond(callback, descriptor);
    } else if (job.operation === "launch") {
      probes++;
      LockOwnerService._initialized = false;
      respond(callback, descriptor);
    } else if (job.operation === "settle") {
      settlements++;
      descriptor.phase = "settled";
      respond(callback, descriptor);
    } else {
      throw new Error("unexpected operation " + job.operation);
    }
  }

  Component.onCompleted: {
    Adapter.attach(root);
    LockOwnerService._session = "session";
    LockOwnerService._initialized = true;
    LockOwnerService.pump();
  }
  Connections {
    target: LockOwnerService
    ignoreUnknownSignals: true
    function onSleepConfirmed(window, confirmed, opaque) {
      if (confirmed) {
        root.sleepConfirmations++;
        if (root.scenario === "sleep-query-inflight" && root.ticks < 10)
          root.premature = true;
      }
    }
  }
  Timer {
    interval: 20
    running: !root.finished
    repeat: true
    onTriggered: {
      root.ticks++;
      if (root.scenario === "sleep-query-inflight" && root.ticks === 3) {
        root.oldQueryReply = LockerService.reply;
        LockOwnerService.observeSleepWindow(true, "current-window");
      }
      LockOwnerService.pump();
      if (root.ticks < 5 || ((root.scenario === "query-persistence" || root.scenario === "sleep-query-inflight") && root.ticks < 10))
        root.premature = root.premature || LockOwnerService.secure;
      if (root.ticks === 5 && LockerService.reply) {
        var reply = root.oldQueryReply || LockerService.reply;
        reply({ok: true, owner: ":1.10", state: root.scenario === "query-pending" ? "pending" : root.scenario === "query-unlocked" ? "unlocked" : "secure"});
      }
      if (root.scenario === "sleep-query-inflight" && root.ticks === 10)
        LockerService.reply({ok: true, owner: ":1.10", state: "secure"});
      if (root.scenario === "sleep-after-auth" && root.ticks === 12)
        LockOwnerService.observeSleepWindow(true, "current-window");
      if (root.scenario === "sleep-after-auth" && root.ticks === 15)
        LockerService.reply({ok: true, owner: ":1.10", state: "unlocked"});
      if (root.ticks === 10 && root.observeReply) {
        root.apply(root.observeJob);
        root.respond(root.observeReply, root.descriptor);
      }
      if (root.scenario === "owner-replacement" && root.ticks >= 12 && !root.wasSecure && LockOwnerService.secure) {
        root.wasSecure = true;
        LockerService.contractOwner = ":1.20";
        root.withdrawn = !LockOwnerService.secure;
      }
      if (root.ticks < 20)
        return;
      var passed = !root.premature;
      if (root.scenario === "owner-replacement")
        passed = passed && root.wasSecure && root.withdrawn && root.probes === 1 && !LockOwnerService.secure;
      else if (root.scenario === "query-pending")
        passed = passed && !LockOwnerService.secure && root.probes === 1;
      else if (root.scenario === "query-unlocked")
        passed = passed && !LockOwnerService.secure && root.probes === 0 && root.settlements === 1;
      else if (root.scenario === "sleep-query-inflight")
        passed = passed && LockOwnerService.secure && LockerService.queries === 2 && root.sleepConfirmations > 0;
      else if (root.scenario === "sleep-after-auth")
        passed = passed && !LockOwnerService.secure && LockerService.queries === 2 && root.sleepConfirmations === 0 && root.settlements === 1;
      else
        passed = passed && LockOwnerService.secure;
      root.finished = true;
      LockOwnerService._initialized = false;
      console.log("OWNER_CONTRACT_RESULT " + JSON.stringify({scenario: root.scenario, passed: passed,
        premature: root.premature, secure: LockOwnerService.secure, withdrawn: root.withdrawn, probes: root.probes,
        queries: LockerService.queries, sleepConfirmations: root.sleepConfirmations}));
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
        'property var data: ({general: {lockScreenEnabled: true}}); signal effectiveSettingsChanged(string section) }\n')
    (shell / 'Commons/Logger.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { '
        'function i(tag, message) {} function e(tag, message) {} }\n')
    (shell / 'Services/Control/HooksService.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject {}\n')
    (shell / 'Services/Locker/LockerService.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { '
        'property bool contractAvailable: true; property string contractOwner: ":1.10"; '
        'property var contractObservations: ({}); property var reply: null; property int queries: 0; signal sessionUnlocked; '
        'function queryContract(id, complete) { queries++; reply = complete; } function observeSession(id) {} }\n')
    (shell / 'shell.qml').write_text(ROOT)
    results = []
    for scenario in ('query-inflight', 'query-persistence', 'query-pending', 'owner-replacement', 'query-unlocked',
                     'sleep-query-inflight', 'sleep-after-auth'):
        process = subprocess.run(['qs', '-p', str(shell), '--no-color'],
            env=dict(os.environ, LOCKER_REVIEW_CASE=scenario, QT_QPA_PLATFORM='offscreen'),
            check=False, text=True, capture_output=True, timeout=15)
        log = process.stdout + process.stderr
        (work / (scenario + '.log')).write_text(log)
        lines = [line.split('OWNER_CONTRACT_RESULT ', 1)[1] for line in log.splitlines() if 'OWNER_CONTRACT_RESULT ' in line]
        row = json.loads(lines[0]) if len(lines) == 1 else dict(passed=False, scenario=scenario, missingResult=True)
        row['exitCode'] = process.returncode
        results.append(row)
        print(json.dumps(row), flush=True)
    (work / 'result.json').write_text(json.dumps(results, indent=2))
    return 0 if all(row['passed'] and row['exitCode'] == 0 for row in results) else 1


if __name__ == '__main__':
    raise SystemExit(main())
