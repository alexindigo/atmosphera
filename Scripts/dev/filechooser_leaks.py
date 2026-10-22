"""Idle leak observations for the guest-only chooser resource case.

Instrumentation is installed only in disposable source copies. Native heap
stats are queried in the actual subject, after the explicit QML GC completes.
"""
import json
import os
from pathlib import Path
import re
import socket
import subprocess
import time

KINDS = ("held_replies", "portal_entries", "requests", "browsers", "selections", "previews",
         "playbacks", "windows", "entries", "thumbnail_providers", "thumbnails",
         "thumbnail_workers", "players", "outputs", "controls")


def retention_acceptance(samples):
    """One fixed30+20 acceptance contract, shared by execution and replay."""
    assert len(samples) == 51 and [s["cycle"] for s in samples] == list(range(51)), "requires all50cycles plus baseline"
    for row in samples:
        assert row["forced_gc"] and row["pid"] == samples[0]["pid"] == row["native"]["pid"]
        assert row["native"]["error"] == 0 and row["native"]["exec_env_cleared"]
        assert row["THP_enabled"] == row["AnonHugePages_kib"] == 0
        assert set(row["chooser_live"]) == set(KINDS), "missing lifetime observation"
        assert row["js_live_bytes"] == row["js_regular_live_bytes"] + row["js_large_live_bytes"]
    measured = samples[31:]
    def slope(getter):
        xm = sum(s["cycle"] for s in measured) / 20
        ym = sum(getter(s) for s in measured) / 20
        return sum((s["cycle"] - xm) * (getter(s) - ym) for s in measured) / sum((s["cycle"] - xm) ** 2 for s in measured) / 1024
    js = slope(lambda s: s["js_live_bytes"])
    native = slope(lambda s: s["native"]["allocated_bytes"])
    pss = [s["Pss_kib"] for s in measured]
    fds = [s["fds"] for s in measured]
    idle = all(all(value == 0 for value in s["chooser_live"].values()) for s in samples)
    balanced = all(all(s["chooser_totals"]["created"].get(kind, 0) == s["chooser_totals"]["destroyed"].get(kind, 0)
                       for kind in KINDS) for s in samples)
    checks = {"post-warmup-js-live-slope": js < 16,
              "post-warmup-native-live-slope": native < 64,
              "post-warmup-pss-coarse-span": max(pss) - min(pss) < 32 * 1024,
              "twenty-post-warmup-descriptor-counts-flat": len(set(fds)) == 1,
              "all-idle-chooser-objects-released": idle,
              "all-idle-lifetime-totals-balanced": balanced}
    return {"warmup_cycles": 30, "measured_cycles": [s["cycle"] for s in measured],
            "js_live_slope_kib_per_cycle": js, "js_live_slope_limit_kib_per_cycle": 16,
            "native_live_slope_kib_per_cycle": native, "native_live_slope_limit_kib_per_cycle": 64,
            "span_kib": max(pss) - min(pss), "span_limit_kib": 32 * 1024,
            "fd_counts": fds, "idle_objects_released": idle, "lifetime_totals_balanced": balanced,
            "checks": checks}


def build_probe(source, runtime, output):
    library = runtime / "native-heap.so"
    command = ["cc", "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror", "-fPIC", "-shared",
               str(source / "Scripts/dev/fixtures/filechooser-native-heap.c"), "-ldl", "-pthread", "-o", str(library)]
    result = subprocess.run(["timeout", "45", *command], capture_output=True, text=True, timeout=55)
    (output / "native-probe-build.log").write_text(result.stdout + result.stderr)
    (output / "native-probe-build.json").write_text(json.dumps(command, indent=2))
    assert result.returncode == 0, result.stderr
    return library


def native_query(path, command="S"):
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.settimeout(10)
        client.connect(str(path))
        client.sendall(command.encode())
        chunks = []
        while True:
            data = client.recv(4096)
            if not data:
                break
            chunks.append(data)
    result = json.loads(b"".join(chunks))
    assert result["error"] == 0 and result["allocator_version"], result
    assert result["pid"] > 0 and result["exec_env_cleared"], result
    assert result["allocated_bytes"] > 0 and result["active_bytes"] >= result["allocated_bytes"], result
    return result


def observer(kind):
    return ('property QtObject _f10LeakObserver: QtObject { '
            f'Component.onCompleted: F10Observed.F10LeakLedger.change("{kind}", 1); '
            f'Component.onDestruction: F10Observed.F10LeakLedger.change("{kind}", -1) }}')


def instrument_choosers(shell, output):
    folder = shell / "Services/Files"
    ledger = '''pragma Singleton
import QtQuick
import Quickshell
Singleton {
  property var live: ({})
  property var createdTotals: ({})
  property var destroyedTotals: ({})
  function change(kind, delta) {
    var next = Object.assign({}, live); next[kind] = (next[kind] || 0) + delta; live = next;
    var total = Object.assign({}, delta > 0 ? createdTotals : destroyedTotals);
    total[kind] = (total[kind] || 0) + 1;
    if (delta > 0) createdTotals = total; else destroyedTotals = total;
  }
  function snapshot() { return {live: live, created: createdTotals, destroyed: destroyedTotals}; }
}
'''
    (folder / "F10LeakLedger.qml").write_text(ledger)
    targets = (("Portals/FileChooserPortal.qml", "entry", "portal_entries"),
               ("Services/Files/FileRequest.qml", "root", "requests"),
               ("Services/Files/FileBrowser.qml", "root", "browsers"),
               ("Services/Files/FileSelection.qml", "root", "selections"),
               ("Services/Files/FilePreview.qml", "root", "previews"),
               ("Services/Files/FilePlayback.qml", "root", "playbacks"),
               ("Services/Files/FileThumbnails.qml", "root", "thumbnail_providers"),
               ("Services/Files/FileThumbnail.qml", "root", "thumbnails"),
               ("Modules/FileChooser/FileChooserWindow.qml", "root", "windows"),
               ("Modules/FileChooser/FileEntry.qml", "root", "entries"),
               ("Modules/FileChooser/FileMediaControls.qml", "root", "controls"))
    for name, root_id, kind in targets:
        path = shell / name
        text = path.read_text()
        needle = "id: " + root_id + "\n"
        assert text.count(needle) == 1, (name, needle)
        text = text.replace(needle, needle + "  " + observer(kind) + "\n")
        # Keep Singleton pragmas before imports in instrumented portal types.
        at = re.search(r"^import\s", text, re.MULTILINE).start()
        text = text[:at] + 'import qs.Services.Files as F10Observed\n' + text[at:]
        if kind == "portal_entries":
            needle = "  function beginRequest(handle, appId, parentWindow, title, options, method, reply) {"
            assert text.count(needle) == 1
            text = text.replace(needle, needle + "\n    _f10HeldReplyObserverFactory.createObject(reply);")
            at = text.rfind("}")
            factory = '''  Component {
    id: _f10HeldReplyObserverFactory
    QtObject {
      Component.onCompleted: F10Observed.F10LeakLedger.change("held_replies", 1)
      Component.onDestruction: F10Observed.F10LeakLedger.change("held_replies", -1)
    }
  }
'''
            text = text[:at] + factory + text[at:]
        if kind == "playbacks":
            needle = "sourceComponent: MediaPlayer {"
            assert text.count(needle) == 1
            text = text.replace(needle, needle + "\n" + observer("players"))
            text, count = re.subn(r"audioOutput:\s*AudioOutput\s*\{\s*volume:\s*root\._volume\s*\}",
                                 "audioOutput: AudioOutput { volume: root._volume; " + observer("outputs") + " }", text)
            assert count == 1
        if kind == "thumbnail_providers":
            needle = "  property bool enabled: true"
            assert text.count(needle) == 1
            factory = '  Component { id: _f10WorkerObserverFactory; QtObject { Component.onCompleted: F10Observed.F10LeakLedger.change("thumbnail_workers", 1); Component.onDestruction: F10Observed.F10LeakLedger.change("thumbnail_workers", -1) } }\n'
            text = text.replace(needle, factory + needle)
            needle = "      if (_process) {"
            assert text.count(needle) == 1
            text = text.replace(needle, needle + "\n        _f10WorkerObserverFactory.createObject(_process);")
        path.write_text(text)
        dest = output / "observed-source" / name
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(text)
    (output / "observed-ledger.qml").write_text(ledger)


def add_checkpoint_handler(shell):
    path = shell / "shell.qml"
    text = path.read_text()
    needle = "    function collectGarbage(): void { gc(); }"
    assert text.count(needle) == 1
    method = '''
    function leakCounts(): string { return JSON.stringify(F10LeakLedger.snapshot()); }
    function leakCheckpoint(token: string): string {
      Logger.i("F10Leak", "GC_BEGIN_" + token);
      gc();
      Logger.i("F10Leak", "GC_END_" + token);
      return JSON.stringify(F10LeakLedger.snapshot());
    }
'''
    path.write_text(text.replace(needle, needle + method))


def checkpoint(ipc, log_path, native_socket, output, cycle, expected_pid=None):
    token = str(cycle)
    offset = log_path.stat().st_size
    immediate_counts = json.loads(ipc("f8Shell", "leakCheckpoint", token))
    deadline = time.monotonic() + 10
    while True:
        with log_path.open("rb") as stream:
            stream.seek(offset)
            raw = stream.read()
        text = re.sub(r"\x1b\[[0-9;]*m", "", raw.decode(errors="replace"))
        begin, end = "GC_BEGIN_" + token, "GC_END_" + token
        if end in text and begin in text:
            segment = text[text.index(begin):text.index(end)]
            regular = re.findall(r"Regular item memory after GC: (\d+)", segment)
            large = re.findall(r"Large item memory after GC: (\d+)", segment)
            # Qt omits the large-item section when there are no such chunks.
            # Only accept that sparse zero after a complete GC-end record.
            if regular and "======== End GC ========" in segment:
                break
        assert time.monotonic() < deadline, ("post-GC stats incomplete", cycle, text[-2000:])
        time.sleep(.05)
    (output / f"gc-{cycle}.log").write_bytes(raw)
    # Read ownership on a separate GUI transaction after the GC call returns
    # to the event loop, so queued QObject destruction is not mistaken for
    # retention. Keep the immediate snapshot as evidence of that phase too.
    counts = json.loads(ipc("f8Shell", "leakCounts"))
    native = native_query(native_socket)
    assert expected_pid is None or native["pid"] == expected_pid, ("native observer is not the subject", native, expected_pid)
    live = {kind: int(counts["live"].get(kind, 0)) for kind in KINDS}
    large_bytes = int(large[-1]) if large else 0
    return {"js_regular_live_bytes": int(regular[-1]), "js_large_live_bytes": large_bytes,
            "js_large_stat_emitted": bool(large), "js_live_bytes": int(regular[-1]) + large_bytes, "native": native,
            "chooser_live": live, "chooser_totals": counts, "chooser_immediate_after_gc": immediate_counts,
            "gc_log_start": offset, "gc_log_end": offset + len(raw), "forced_gc": True}
