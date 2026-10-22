#!/usr/bin/env python3
"""Validate idle JS/native allocation and actual QObject lifetime observers."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

from filechooser_isolation import ROOT, enter, profile_env
from filechooser_leaks import build_probe, checkpoint, instrument_choosers, native_query, observer


def main():
    enter(runtime_seconds=240)
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--label", required=True)
    args = parser.parse_args()
    source = args.source.resolve()
    assert source.is_relative_to(ROOT / "sources")
    runtime, output = ROOT / "runtime" / args.label, ROOT / "evidence" / args.label
    runtime.mkdir(); output.mkdir()
    shell = runtime / "shell"
    shutil.copytree(source, shell, symlinks=True)
    instrument_choosers(shell, output)
    library = build_probe(source, runtime, output)
    address = Path(os.environ["FILECHOOSER_ISOLATION"]) / "run/native-heap.sock"
    env = dict(profile_env(runtime / "profile"), MALLOC_CONF="dirty_decay_ms:0,muzzy_decay_ms:0",
               QV4_MM_STATS="1", QV4_GC_TIMINGS="1",
               QT_LOGGING_RULES="qt.qml.gc.statistics=true;qt.qml.gc.allocatorStats=true")
    defaults = json.loads((source / "Configs/defaults.json").read_text())
    (runtime / "profile/config/settings.json").write_text(json.dumps(defaults))
    probe = shell / "leak-canary.qml"
    probe.write_text('''import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Files
import qs.Services.Files as F10Observed
ShellRoot {
  id: root
  property var held: null
  property var owned: null
  property int childExit: -999
  Process {
    id: child
    command: ["python3", "-B", "-c", "import os; assert 'LD_PRELOAD' not in os.environ and 'FILECHOOSER_NATIVE_SOCKET' not in os.environ"]
    onExited: (code, status) => { root.childExit = status === 0 ? code : -100 - status; }
  }
  Component { id: factory; QtObject { ''' + observer("requests") + ''' } }
  IpcHandler {
    target: "f8Shell"
    function ready(): bool { return true; }
    function runChild(): void { child.running = true; }
    function childResult(): int { return root.childExit; }
    function hold(): void { root.held = Array.from({length: 16384}, (_, i) => ({name: "canary-" + i, value: i})); }
    function release(): void { root.held = null; }
    function createObject(): void { root.owned = factory.createObject(root); }
    function releaseObject(): void { root.owned.destroy(); root.owned = null; }
    function leakCounts(): string { return JSON.stringify(F10LeakLedger.snapshot()); }
    function leakCheckpoint(token: string): string {
      Logger.i("F10Leak", "GC_BEGIN_" + token); gc(); Logger.i("F10Leak", "GC_END_" + token);
      return JSON.stringify(F10LeakLedger.snapshot());
    }
    function quit(): void { Qt.quit(); }
  }
}
''')
    def ipc(target, member, *values):
        return subprocess.run(["timeout", "10", "qs", "-p", str(probe), "ipc", "call", target, member, *values],
                              env=env, capture_output=True, text=True, check=True, timeout=15).stdout.strip()
    cases = []
    def check(name, condition, detail=None):
        cases.append({"case": name, "pass": bool(condition), "detail": detail})
        print(name, "PASS" if condition else "FAIL", flush=True)
        assert condition, name
    log_path = output / "subject.log"
    with log_path.open("w") as log:
        app = subprocess.Popen(["timeout", "150", sys.executable, "-B", str(source / "Scripts/dev/filechooser-no-thp.py"),
                                "env", "LD_PRELOAD=" + str(library), "FILECHOOSER_NATIVE_SOCKET=" + str(address), "qs", "-p", str(probe)],
                               env=env, stdout=log, stderr=subprocess.STDOUT)
        try:
            end = time.monotonic() + 30
            while True:
                try:
                    if address.exists() and ipc("f8Shell", "ready") == "true": break
                except subprocess.CalledProcessError: pass
                assert app.poll() is None and time.monotonic() < end, "canary startup failed"
                time.sleep(.1)
            time.sleep(2)
            baseline = checkpoint(ipc, log_path, address, output, "baseline")
            ipc("f8Shell", "runChild")
            deadline = time.monotonic() + 10
            while ipc("f8Shell", "childResult") == "-999":
                assert time.monotonic() < deadline
                time.sleep(.05)
            check("probe-not-inherited-by-exec-child", ipc("f8Shell", "childResult") == "0"
                  and native_query(address)["pid"] == baseline["native"]["pid"])
            before = native_query(address)
            during = native_query(address, "A")
            after = native_query(address, "F")
            check("native-held-2MiB-observed", during["allocated_bytes"] - before["allocated_bytes"] >= 2 * 1024 * 1024, [before, during, after])
            check("native-released-2MiB-observed", during["allocated_bytes"] - after["allocated_bytes"] >= 2 * 1024 * 1024)
            ipc("f8Shell", "hold")
            held = checkpoint(ipc, log_path, address, output, "held")
            check("js-reachable-held-observed", held["js_live_bytes"] - baseline["js_live_bytes"] > 256 * 1024, [baseline["js_live_bytes"], held["js_live_bytes"]])
            ipc("f8Shell", "release")
            released = checkpoint(ipc, log_path, address, output, "released")
            check("js-unreachable-released-observed", held["js_live_bytes"] - released["js_live_bytes"] > 256 * 1024, released["js_live_bytes"])
            ipc("f8Shell", "createObject")
            check("native-object-positive-control", json.loads(ipc("f8Shell", "leakCounts"))["live"]["requests"] == 1)
            ipc("f8Shell", "releaseObject")
            closed = checkpoint(ipc, log_path, address, output, "object-closed")
            check("native-object-destruction-observed", closed["chooser_live"]["requests"] == 0, closed["chooser_totals"])
            check("no-parent-preload", "LD_PRELOAD" not in os.environ and "FILECHOOSER_NATIVE_SOCKET" not in os.environ)
            ipc("f8Shell", "quit"); app.wait(timeout=15)
            check("canary-exit", app.returncode == 0)
            (output / "result.json").write_text(json.dumps({"passed": True, "cases": cases, "baseline": baseline, "held": held, "released": released, "closed": closed}, indent=2))
        finally:
            if app.poll() is None:
                ipc("f8Shell", "quit"); app.wait(timeout=15)


if __name__ == "__main__":
    main()
