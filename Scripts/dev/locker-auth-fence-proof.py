#!/usr/bin/env python3
"""Actual LockClient retry boundary with controlled receipts, not PAM evidence."""
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
import qs.Services.Locker
import "Helpers/OwnedProcess.js" as Adapter
ShellRoot {
  id: root
  property int attempts: 0
  property bool premature: false
  property bool persistent: Quickshell.env("LOCKER_REVIEW_CASE") === "persistent"
  QtObject {
    id: fakeEndpoint
    property bool secure: true
    property bool locked: true
    onLockedChanged: {
      if (!locked && (root.attempts < 3 || root.persistent)) root.premature = true;
      if (!locked) secure = false;
    }
  }
  QtObject { id: fakeAuth; signal unlocked; function retire() {} }
  LockClient { id: client; endpoint: fakeEndpoint; auth: fakeAuth; prepared: true }
  function receive(job, complete) {
    // Keep only the fixture's terminal receipt pending so its final assertion
    // can observe normal client settlement before production self-exit.
    if (job.operation === "client" && job.status.terminal) return;
    var reply;
    if (job.operation === "authenticated") {
      attempts++;
      reply = attempts < 3 || persistent ? {ok: false, error: "controlled peer-stop refusal"}
        : {ok: true, value: {unlock: true, retire: false}};
    } else {
      reply = {ok: true, value: {generation: "g", grant: false, retire: false}};
    }
    Qt.callLater(function() { complete({stdout: JSON.stringify(reply)}); });
  }
  Component.onCompleted: {
    Adapter.attach(root);
    client._requested = true;
    Qt.callLater(function() { fakeAuth.unlocked(); });
  }
  Timer {
    interval: 1700; running: true
    onTriggered: {
      var passed = root.attempts >= 3 && !root.premature && fakeEndpoint.locked === root.persistent;
      if (!root.persistent) passed = passed && root.attempts === 3 && client.terminal;
      console.log("AUTH_FENCE_RESULT " + JSON.stringify({passed: passed, persistent: root.persistent,
        attempts: root.attempts, locked: fakeEndpoint.locked, premature: root.premature}));
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
    (shell / 'Services/Locker').mkdir(parents=True)
    (shell / 'Helpers').mkdir()
    shutil.copyfile(source / 'Services/Locker/LockClient.qml', shell / 'Services/Locker/LockClient.qml')
    (shell / 'Helpers/OwnedProcess.js').write_text('.pragma library\nvar owner = null;\n'
        'function attach(value) { owner = value; }\n'
        'function run(parent, command, input, complete) { owner.receive(JSON.parse(input), complete); }\n')
    (shell / 'shell.qml').write_text(ROOT)
    results = []
    for scenario in ('transient', 'persistent'):
        process = subprocess.run(['qs', '-p', str(shell), '--no-color'], env=dict(os.environ,
            LOCKER_REVIEW_CASE=scenario, QT_QPA_PLATFORM='offscreen', ATMOSPHERA_LOCK_SESSION='fixture',
            ATMOSPHERA_LOCK_GENERATION='g', ATMOSPHERA_LOCK_ROLE='emergency', ATMOSPHERA_LOCK_ADAPTER='controlled'),
            capture_output=True, text=True, timeout=10)
        text = process.stdout + process.stderr
        (work / (scenario + '.log')).write_text(text)
        rows = [json.loads(line.split('AUTH_FENCE_RESULT ', 1)[1]) for line in text.splitlines() if 'AUTH_FENCE_RESULT ' in line]
        row = rows[0] if len(rows) == 1 else dict(passed=False, missingResult=True)
        row.update(scenario=scenario, exitCode=process.returncode)
        results.append(row)
        print(json.dumps(row), flush=True)
    (work / 'result.json').write_text(json.dumps(results, indent=2))
    return 0 if all(row['passed'] and row['exitCode'] == 0 for row in results) else 1


if __name__ == '__main__':
    raise SystemExit(main())
