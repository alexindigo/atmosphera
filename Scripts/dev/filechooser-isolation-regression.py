#!/usr/bin/env python3
"""Containment regression and full-shell picker memory exercise (assigned VM)."""

import argparse
import hashlib
import importlib.util
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import sys
import time

from filechooser_isolation import ROOT, cgroup, enter, input_command, profile_env
from filechooser_gate import request_gate


def command(argv, env=None, seconds=15, check=True):
    return subprocess.run(["timeout", str(seconds), *map(str, argv)], env=env,
                          capture_output=True, text=True, timeout=seconds + 5, check=check)


def hashes(path):
    return {str(p.relative_to(path)): hashlib.sha256(p.read_bytes()).hexdigest()
             for p in path.rglob("*") if p.is_file() and not p.is_symlink()}


def pss_slope(samples):
    """Least-squares KiB/cycle, independent of sample wall-clock spacing."""
    xmean = sum(row["cycle"] for row in samples) / len(samples)
    ymean = sum(row["Pss_kib"] for row in samples) / len(samples)
    return sum((row["cycle"] - xmean) * (row["Pss_kib"] - ymean) for row in samples) / sum((row["cycle"] - xmean) ** 2 for row in samples)


def wait(fn, seconds=20):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        try:
            value = fn()
            if value:
                return value
        except (subprocess.CalledProcessError, json.JSONDecodeError, FileNotFoundError):
            pass
        time.sleep(.1)
    raise AssertionError("readiness timeout")


def instrument(shell, filename, handler, imports=""):
    path = shell / filename
    text = path.read_text()
    index = text.rfind("}")
    path.write_text(imports + "import Quickshell.Io\n" + text[:index] + handler + text[index:])


def main():
    leak_diagnostic = "--leak-diagnostic" in sys.argv
    enter(memory_probe=not leak_diagnostic, runtime_seconds=3600 if leak_diagnostic else 1200, gate_probe=not leak_diagnostic)
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--source", type=Path, required=True)
    p.add_argument("--label", required=True)
    p.add_argument("--diagnose", action="store_true", help="trace descriptor ownership by picker phase")
    p.add_argument("--cycles", type=int, default=50, help="media cycles; default30 warm-up plus20 measured")
    p.add_argument("--analyze", type=Path, help="summarize a recorded50+ cycle curve without running picker cycles")
    p.add_argument("--fd-probe", action="store_true", help="prove bounded scan pipes/pidfd ownership in a disposable copy")
    p.add_argument("--heap-probe", action="store_true", help="diagnostic-only paired mapping snapshots around QML GC")
    p.add_argument("--malloc-probe", action="store_true", help="diagnostic-only bounded-arena/immediate-trim allocator comparison")
    p.add_argument("--memory-trace", action="store_true", help="diagnostic-only native memory-release syscall stacks")
    p.add_argument("--jemalloc-probe", action="store_true", help="diagnostic-only immediate jemalloc page decay comparison")
    p.add_argument("--lifetime-probe", action="store_true", help="positive active/native lifetime controls for one media cycle")
    p.add_argument("--leak-diagnostic", action="store_true", help="one120-cycle post-GC JS/native/object diagnostic, no acceptance verdict")
    a = p.parse_args()
    assert 12 <= a.cycles <= 50
    if a.lifetime_probe:
        a.heap_probe = True
        a.cycles = 1
    if a.leak_diagnostic:
        assert not any((a.diagnose, a.analyze, a.fd_probe, a.heap_probe, a.malloc_probe, a.memory_trace, a.jemalloc_probe, a.lifetime_probe))
        a.cycles = 120
    diagnostic = any((a.diagnose, a.analyze, a.fd_probe, a.heap_probe, a.malloc_probe, a.memory_trace, a.jemalloc_probe, a.lifetime_probe, a.leak_diagnostic))
    observe_retention = a.leak_diagnostic or not diagnostic
    if not diagnostic and a.cycles != 50:
        p.error("resource acceptance requires30 warm-up +20 measured cycles")
    source = a.source.resolve()
    output, runtime = ROOT / "evidence" / a.label, ROOT / "runtime" / a.label
    assert source.is_relative_to(ROOT / "sources")
    output.mkdir(); runtime.mkdir()
    if a.analyze:
        assert a.analyze.resolve().is_relative_to(ROOT / "evidence")
        samples = json.loads(a.analyze.read_text())
        if any(str(s["cycle"]).startswith("pre-gc-") for s in samples):
            samples = [s for s in samples if s["cycle"] != 0]
            pairs = []
            for before, after in zip(samples[::2], samples[1::2]):
                assert str(before["cycle"]) == "pre-gc-" + str(after["cycle"])
                old = json.loads((a.analyze.parent / ("mapping-groups-" + str(before["cycle"]) + ".json")).read_text())
                new = json.loads((a.analyze.parent / ("mapping-groups-" + str(after["cycle"]) + ".json")).read_text())
                changes = {key: new.get(key, {}).get("Pss", 0) - old.get(key, {}).get("Pss", 0) for key in old.keys() | new.keys()}
                pairs.append({"cycle": after["cycle"], "before_kib": before["Pss_kib"], "after_kib": after["Pss_kib"], "delta_kib": after["Pss_kib"] - before["Pss_kib"], "before_counts": before.get("nativeCounts"), "after_counts": after.get("nativeCounts"), "mapping_deltas_kib": {k: v for k, v in sorted(changes.items(), key=lambda item: abs(item[1]), reverse=True) if abs(v) > 256}})
            result = {"diagnostic_only": True, "pairs": pairs}
            (output / "heap-analysis.json").write_text(json.dumps(result, indent=2))
            print(json.dumps(result, indent=2))
            return
        assert len(samples) >= 51 and samples[-1]["cycle"] >= 50
        windows = []
        for start in (1, 11, 21, 31, 41):
            rows = [s for s in samples if start <= s["cycle"] < start + 10]
            values = [s["Pss_kib"] for s in rows]
            mean = sum(values) / len(values)
            slope = pss_slope(rows)
            windows.append({"first": start, "last": start + 9, "min_kib": min(values), "max_kib": max(values), "mean_kib": mean, "span_kib": max(values) - min(values), "slope_kib_per_cycle": slope, "fds": sorted(set(s["fds"] for s in rows))})
        tail = samples[-20:]
        result = {"input": str(a.analyze), "windows": windows, "diagnostic_only": True,
                  "descriptive_pss_slope_kib_per_cycle": pss_slope(tail),
                  "peak_cycle": max(samples[1:], key=lambda s: s["Pss_kib"])["cycle"], "last": samples[-1]}
        if all("js_live_bytes" in s and "held_replies" in s.get("chooser_live", {}) for s in samples[:51]):
            from filechooser_leaks import retention_acceptance
            result["recorded_retention_checks"] = retention_acceptance(samples[:51])
        (output / "curve-analysis.json").write_text(json.dumps(result, indent=2))
        print(json.dumps(result, indent=2))
        return
    cases, samples = [], []
    def check(name, condition, detail=None):
        cases.append({"case": name, "pass": bool(condition), "detail": detail})
        print(name, "PASS" if condition else "FAIL", flush=True)
        assert condition, name
    complete, failure = False, ""
    acceptance = None
    shell_proc = session_proc = None
    logs = []
    session_env = None
    try:
        # Fail old trees before executing their unsafe runner. This is the red
        # contract boundary: the old harness has no isolation entrance at all.
        # This driver itself is always in the new runner's disposable outer PID
        # namespace. The candidate's boundary is tested inside it; an old tree
        # can kill only our disposable companion, never a console process.
        check("outer-pid-namespace", os.environ["FILECHOOSER_PID_NAMESPACE"] != os.environ["FILECHOOSER_PARENT_PID_NAMESPACE"])
        candidate_helper = source / "Scripts/dev/filechooser_isolation.py"
        prefix = lambda argv: list(map(str, argv))
        if candidate_helper.exists():
            spec = importlib.util.spec_from_file_location("candidate_isolation", candidate_helper)
            candidate = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(candidate)
            prefix = getattr(candidate, "namespace_command", prefix)
        companion = subprocess.Popen([sys.executable, "-c", "import ctypes,time; ctypes.CDLL(None).prctl(15,b'wlsunset',0,0,0); time.sleep(40)"])
        wait(lambda: Path(f"/proc/{companion.pid}/comm").read_text().strip() == "wlsunset")
        pid_base = Path(os.environ["FILECHOOSER_ISOLATION"]) / "p"
        pid_base.mkdir()
        pid_output = output / "pid-case"
        pid_output.mkdir()
        pid_shell = runtime / "pid-shell"
        shutil.copytree(source, pid_shell, symlinks=True)
        pid_child = runtime / "pid-child.py"
        pid_child.write_text("import json,os,subprocess\nfrom pathlib import Path\n"
            "config=Path(os.environ['XDG_CONFIG_HOME'])/'atmosphera'\nconfig.mkdir()\n"
            "data=json.loads(Path(" + repr(str(source / "Configs/defaults.json")) + ").read_text())\n"
            "data['general']['showChangelogOnStartup']=False\n(config/'settings.json').write_text(json.dumps(data))\n"
            "result=subprocess.run(['timeout','10','qs','-p'," + repr(str(pid_shell / "shell.qml")) + "],capture_output=True,text=True,timeout=18)\n"
            "Path(" + repr(str(pid_output / "shell.log")) + ").write_text(result.stdout+result.stderr)\n"
            "assert result.returncode==124 and 'SingletonCheck' in result.stdout+result.stderr\n")
        helper = Path(__file__).resolve().parent / "filechooser_isolation.py"
        try:
            pid_run = command(prefix([sys.executable, "-B", helper, "--session", pid_base, pid_output, pid_child]), seconds=35, check=False)
            (pid_output / "driver.log").write_text(pid_run.stdout + pid_run.stderr)
            check("candidate-full-shell-started", pid_run.returncode == 0)
            check("startup-cannot-kill-session-companion", companion.poll() is None)
        finally:
            if companion.poll() is None:
                companion.terminate()
            companion.wait(timeout=5)
        shell = runtime / "shell"
        shutil.copytree(source, shell, symlinks=True)
        if observe_retention:
            from filechooser_leaks import build_probe, checkpoint, instrument_choosers, add_checkpoint_handler, retention_acceptance, KINDS
            instrument_choosers(shell, output)
            native_library = build_probe(source, runtime, output)
            native_socket = Path(os.environ["FILECHOOSER_ISOLATION"]) / "run/native-heap.sock"
        if a.fd_probe:
            places = shell / "Services/Files/FilePlaces.qml"
            text = places.read_text()
            needle = "print(json.dumps({'places': places, 'removable': removable, 'recent': recent, 'xdg': xdg}))"
            assert text.count(needle) == 1
            places.write_text(text.replace(needle, "# FILECHOOSER_FD_PROBE\nimport time\ntime.sleep(2)\n" + needle))
        if a.heap_probe:
            # Test-only native lifetime ledger, shared by module name (not
            # relative-JS URLs). No counter or GC hook enters product sources.
            (shell / "Services/Files/F10LifetimeCounter.qml").write_text('pragma Singleton\nimport QtQuick\nimport Quickshell\nSingleton { property int players:0; property int outputs:0; property int controls:0 }\n')
            player = shell / "Services/Files/FilePlayback.qml"
            text = "import qs.Services.Files as F10Probe\n" + player.read_text()
            needle = "sourceComponent: MediaPlayer {"
            assert text.count(needle) == 1
            text = text.replace(needle, needle + "\nComponent.onCompleted: ++F10Probe.F10LifetimeCounter.players\nComponent.onDestruction: --F10Probe.F10LifetimeCounter.players")
            text, count = re.subn(r"audioOutput:\s*AudioOutput\s*\{\s*volume:\s*root\._volume\s*\}", "audioOutput: AudioOutput { volume: root._volume; Component.onCompleted: ++F10Probe.F10LifetimeCounter.outputs; Component.onDestruction: --F10Probe.F10LifetimeCounter.outputs }", text)
            assert count == 1
            player.write_text(text)
            controls = shell / "Modules/FileChooser/FileMediaControls.qml"
            text = controls.read_text()
            needle = "  id: root\n"
            assert text.count(needle) == 1
            controls.write_text("import qs.Services.Files\n" + text.replace(needle, needle + "  Component.onCompleted: ++F10LifetimeCounter.controls\n  Component.onDestruction: --F10LifetimeCounter.controls\n"))
        env = profile_env(runtime / "profile")
        # F10's40-cycle curves plateau around600MiB and native lifetimes return
        # to zero. Release stacks identify Mesa/LLVM's jemalloc dirty-page
        # decay, not retained players. Its default10s decay adds PSS jitter.
        # Coordinator-approved measurement profile: purge already-freed pages
        # immediately, ONLY in this private subject (not clients, companion,
        # product configuration or the shared runner). Live growth still counts.
        subject_env = dict(env, MALLOC_CONF="dirty_decay_ms:0,muzzy_decay_ms:0")
        if observe_retention:
            subject_env.update(QV4_MM_STATS="1", QV4_GC_TIMINGS="1", QT_LOGGING_RULES="qt.qml.gc.statistics=true;qt.qml.gc.allocatorStats=true")
        # F11 handoff§4: always-THP inflated Mesa/llvmpipe resident backing
        # while sampled live heap stayed flat and native objects returned0.
        # Coordinator answer3 approves process-only THP-off for this retained-
        # memory subject. The validated prctl+exec launcher changes neither
        # this parent, companion, independent gate, product nor kernel policy.
        thp_policy = Path("/sys/kernel/mm/transparent_hugepage/enabled").read_text()
        parent_thp = int(next(line.split()[1] for line in Path("/proc/self/status").read_text().splitlines() if line.startswith("THP_enabled:")))
        if a.malloc_probe:
            subject_env.update(MALLOC_ARENA_MAX="2", MALLOC_TRIM_THRESHOLD_="0")
        if a.jemalloc_probe:
            subject_env["MALLOC_CONF"] = "confirm_conf:true,dirty_decay_ms:0,muzzy_decay_ms:0"
        defaults = json.loads((source / "Configs/defaults.json").read_text())
        defaults["general"]["showChangelogOnStartup"] = False
        (runtime / "profile/config/settings.json").write_text(json.dumps(defaults))
        # Diagnostic observer exists only in this disposable copy. It observes
        # the real production portal's window and real renderer at the consumer.
        instrument(shell, "shell.qml", '''
  IpcHandler {
    target: "f8Shell"
    function ready(): string { return JSON.stringify(shellRoot.settingsLoaded && shellRoot.i18nLoaded); }
    function workState(): string { return JSON.stringify({places: FilePlaces.loading}); }
    function refreshPlaces(): void { FilePlaces.refresh(); }
    function collectGarbage(): void { gc(); }
    function quit(): void { Qt.quit(); }
  }
''', imports="import qs.Services.Files\n")
        if observe_retention:
            add_checkpoint_handler(shell)
        if a.heap_probe:
            path = shell / "shell.qml"
            text = path.read_text()
            needle = "    function collectGarbage(): void { gc(); }"
            assert text.count(needle) == 1
            path.write_text(text.replace(needle, needle + '\n    function lifetimes(): string { return JSON.stringify({players:F10LifetimeCounter.players, outputs:F10LifetimeCounter.outputs, controls:F10LifetimeCounter.controls, requests:Object.keys(FileChooserPortal.activeRequests).length}); }'))
        instrument(shell, "Modules/FileChooser/FileChooserWindow.qml", '''
  IpcHandler {
    target: "f8Picker"
    function state(): string { return JSON.stringify({
      ready: request.browser.status === "ready", count: request.browser.count,
      name: request.browser.entry(request.selection.cursor)?.name || "",
      preview: root.quickLookOpen, kind: root.preview.kind,
       rendered: root.previewRenderer ? root.previewRenderer.previewState : "",
       playback: root.playbackState,
      position: root.previewRenderer && root.previewRenderer.position !== undefined ? root.previewRenderer.position : -1,
      tiles: root.thumbnailState().tiles
    }); }
  }
''')
        # A second disposable session has its own compositor, HOME and bus.
        # The shared supervisor is reused, not another hand-written recipe.
        session_base = Path(os.environ["FILECHOOSER_ISOLATION"]) / "s"
        session_base.mkdir()
        session_output = output / "session-like"
        session_output.mkdir()
        session_shell = runtime / "session-shell"
        shutil.copytree(source, session_shell, symlinks=True)
        probe = session_shell / "probe.qml"
        probe.write_text('''import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
ShellRoot {
  IpcHandler {
    target: "f8Session"
    function state(): string { return JSON.stringify(Settings.isLoaded); }
    function quit(): void { Qt.quit(); }
  }
}
''')
        log = (output / "session-supervisor.log").open("w"); logs.append(log)
        helper = Path(__file__).resolve().parent / "filechooser_isolation.py"
        # The supervisor takes a Python entry point, so a tiny owned driver
        # waits for this session's qs; no login session environment is inherited.
        child = runtime / "session-child.py"
        child.write_text("import os,shutil,subprocess\nfrom pathlib import Path\n"
                         "config=Path(os.environ['XDG_CONFIG_HOME'])/'atmosphera'\nconfig.mkdir()\n"
                         "shutil.copyfile(" + repr(str(source / "Configs/defaults.json")) + ",config/'settings.json')\n"
                          "seconds=int(os.environ['FILECHOOSER_SESSION_SECONDS'])\n"
                          "raise SystemExit(subprocess.run(['timeout',str(seconds),'qs','-p'," + repr(str(probe)) + "], timeout=seconds+10).returncode)\n")
        session_proc = subprocess.Popen([sys.executable, "-B", str(helper), "--session", str(session_base), str(session_output), str(child)], stdout=log, stderr=subprocess.STDOUT)
        wait(lambda: (session_output / "environment.json").exists())
        session_env = json.loads((session_output / "environment.json").read_text())
        def session_ipc(member):
            result = command(["qs", "-p", probe, "ipc", "call", "f8Session", member], session_env, check=False)
            (output / "session-ipc.json").write_text(json.dumps({"exit": result.returncode, "stdout": result.stdout, "stderr": result.stderr}, indent=2))
            return result.stdout.strip()
        wait(lambda: session_ipc("state") == "true")
        time.sleep(3)
        protected = {name: hashes(session_base / name) for name in ("home", "config", "cache", "state", "data")}
        check("session-and-dev-identities-disjoint", all(env[k] != session_env[k] for k in ("HOME", "XDG_RUNTIME_DIR", "DBUS_SESSION_BUS_ADDRESS", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "XDG_STATE_HOME", "XDG_DATA_HOME")))
        log = (output / "shell.log").open("w"); logs.append(log)
        trace = (["strace", "-f", "-qq", "-yy", "-ttt", "-s", "512",
                   "-e", "trace=openat,close,dup,dup2,dup3,clone,clone3,execve", "-o", str(output / "commands.trace")]
                  if a.diagnose else [])
        if a.memory_trace:
            trace = ["strace", "-f", "-k", "-qq", "-ttt", "-e", "trace=madvise,munmap", "-o", str(output / "memory-release.trace")]
        subject_command = ["qs", "-p", str(shell / "shell.qml")]
        if observe_retention:
            subject_command = ["env", "LD_PRELOAD=" + str(native_library), "FILECHOOSER_NATIVE_SOCKET=" + str(native_socket), *subject_command]
        shell_proc = subprocess.Popen(["timeout", env["FILECHOOSER_SESSION_SECONDS"], *trace, sys.executable, "-B",
                                       str(source / "Scripts/dev/filechooser-no-thp.py"), *subject_command],
                                      env=subject_env, stdout=log, stderr=subprocess.STDOUT)
        def ipc(target, member, *values):
            return command(["qs", "-p", shell / "shell.qml", "ipc", "call", target, member, *values], env).stdout.strip()
        wait(lambda: ipc("f8Shell", "ready") == "true", 90 if a.memory_trace else 35)
        wait(lambda: command(["busctl", "--address=" + env["DBUS_SESSION_BUS_ADDRESS"], "call", "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "NameHasOwner", "s", "org.freedesktop.impl.portal.desktop.atmosphera"], env).stdout.strip() == "b true")
        pid = int(command(["busctl", "--address=" + env["DBUS_SESSION_BUS_ADDRESS"], "call", "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "GetConnectionUnixProcessID", "s", "org.freedesktop.impl.portal.desktop.atmosphera"], env).stdout.split()[1])
        actual_profile = next(value.split(b"=", 1)[1].decode() for value in Path(f"/proc/{pid}/environ").read_bytes().split(b"\0") if value.startswith(b"MALLOC_CONF="))
        check("subject-only-allocator-profile", actual_profile == subject_env["MALLOC_CONF"] and "MALLOC_CONF" not in env and "MALLOC_CONF" not in session_env, actual_profile)
        subject_thp = int(next(line.split()[1] for line in Path(f"/proc/{pid}/status").read_text().splitlines() if line.startswith("THP_enabled:")))
        parent_after = int(next(line.split()[1] for line in Path("/proc/self/status").read_text().splitlines() if line.startswith("THP_enabled:")))
        check("subject-only-thp-disabled", subject_thp == 0 and parent_after == parent_thp
              and Path("/sys/kernel/mm/transparent_hugepage/enabled").read_text() == thp_policy,
              {"subject": subject_thp, "parent_before": parent_thp, "parent_after": parent_after, "kernel_policy": thp_policy})
        (output / "resource-profile.json").write_text(json.dumps({"pid": pid, "MALLOC_CONF": actual_profile, "THP_enabled": subject_thp,
            "parent_THP_enabled": parent_thp, "unchanged_kernel_policy": thp_policy, "scope": "private media resource-test subject only"}, indent=2))
        def descriptors():
            links, owners = {}, {}
            for fd in Path(f"/proc/{pid}/fd").iterdir():
                try:
                    link = os.readlink(fd)
                    links[fd.name] = link
                    if link == "anon_inode:[pidfd]":
                        info = Path(f"/proc/{pid}/fdinfo/{fd.name}").read_text()
                        target = int(next(line.split()[1] for line in info.splitlines() if line.startswith("Pid:")))
                        argv = Path(f"/proc/{target}/cmdline").read_bytes().replace(b"\0", b" ").decode(errors="replace") if target > 0 else ""
                        owners[fd.name] = {"pid": target, "command": argv, "fdinfo": info}
                except (FileNotFoundError, ProcessLookupError):
                    pass
            return {"links": links, "owners": owners}
        def work_state():
            return json.loads(ipc("f8Shell", "workState"))
        def sample(cycle):
            live_checkpoint = checkpoint(ipc, output / "shell.log", native_socket, output, cycle, pid) if observe_retention else None
            # Retention is measured at the owner's idle phase, not halfway
            # through a periodic scan with correctly live pipes and a pidfd.
            # Preserve every interrupted/raw capture; do not inspect counts
            # to decide whether a phase is eligible or discount any descriptor.
            raw = []
            deadline = time.monotonic() + 20
            while True:
                before = work_state()
                capture = descriptors()
                after = work_state()
                if not before["places"] and not after["places"]:
                    break
                raw.append({"before": before, "after": after, **capture})
                assert time.monotonic() < deadline, "places scan did not reach idle"
                time.sleep(.05)
            (output / f"raw-phases-{cycle}.json").write_text(json.dumps(raw, indent=2))
            mappings = Path(f"/proc/{pid}/smaps").read_text()
            (output / f"smaps-{cycle}.txt").write_text(mappings)
            groups, group = {}, ""
            for line in mappings.splitlines():
                if re.match(r"^[0-9a-f]+-[0-9a-f]+ ", line):
                    fields = line.split(None, 5)
                    group = fields[5] if len(fields) > 5 else "[anonymous]"
                    groups.setdefault(group, {"Pss": 0, "Private_Dirty": 0, "Rss": 0})
                elif group and line.split(":", 1)[0] in ("Pss", "Private_Dirty", "Rss"):
                    key, value = line.split(":", 1)
                    groups[group][key] += int(value.split()[0])
            (output / f"mapping-groups-{cycle}.json").write_text(json.dumps(groups, indent=2))
            values = {}
            for line in Path(f"/proc/{pid}/smaps_rollup").read_text().splitlines():
                parts = line.split()
                if parts[0] in ("Rss:", "Pss:", "Private_Dirty:", "Anonymous:"):
                    values[parts[0][:-1] + "_kib"] = int(parts[1])
            row = {"cycle": cycle, "pid": pid, "time": time.time(), **values, "fds": len(capture["links"]),
                   "cgroup_bytes": int((cgroup() / "memory.current").read_text())}
            status = Path(f"/proc/{pid}/status").read_text()
            (output / f"status-{cycle}.txt").write_text(status)
            row["THP_enabled"] = int(next(line.split()[1] for line in status.splitlines() if line.startswith("THP_enabled:")))
            row["AnonHugePages_kib"] = sum(int(line.split()[1]) for line in mappings.splitlines() if line.startswith("AnonHugePages:"))
            assert row["THP_enabled"] == 0 and row["AnonHugePages_kib"] == 0, row
            if a.heap_probe:
                row["nativeCounts"] = json.loads(ipc("f8Shell", "lifetimes"))
            if live_checkpoint is not None:
                row.update(live_checkpoint)
            samples.append(row)
            (output / f"fds-{cycle}.json").write_text(json.dumps(capture["links"], indent=2))
            (output / f"fd-owners-{cycle}.json").write_text(json.dumps(capture["owners"], indent=2))
            (output / "memory.json").write_text(json.dumps(samples, indent=2))
            print("MEMORY", json.dumps(row), flush=True)
        def state():
            value = json.loads(ipc("f8Picker", "state"))
            (output / "last-picker-state.json").write_text(json.dumps(value, indent=2))
            return value
        def keys(*args):
            command(input_command(["ydotool", *args]), env)
            time.sleep(.15)
        fixtures = runtime / "media"
        fixtures.mkdir()
        videos = fixtures / "videos"
        shutil.copytree("/home/tester/Videos/Thumbnail Library", videos)
        check("48-video-fixture", len(list(videos.iterdir())) == 48)
        audio = fixtures / "audio"
        audio.mkdir()
        source_audio = next(Path("/home/tester/Music").glob("*.wav"))
        shutil.copy2(source_audio, audio / "Sound.wav")
        # Exercise production DBus request ownership, including destruction on
        # cancel, rather than the dev harness's long-lived request.
        def open_folder(folder, index):
            client_out = output / f"request-{index}.log"
            log = client_out.open("w"); logs.append(log)
            proc = subprocess.Popen(["timeout", "30", "gdbus", "call", "--session", "--dest", "org.freedesktop.impl.portal.desktop.atmosphera",
                 "--object-path", "/org/freedesktop/portal/desktop", "--method", "org.freedesktop.impl.portal.FileChooser.OpenFile",
                 f"/org/freedesktop/portal/desktop/request/f8/r{index}", "dev.filechooser.memory", "", "F8 memory exercise",
                 "{'current_folder': <" + str(list(os.fsencode(folder) + b"\0")) + ">}"], env=env, stdout=log, stderr=subprocess.STDOUT)
            wait(lambda: state().get("ready"))
            return proc
        time.sleep(2); sample(0)
        if a.fd_probe:
            wait(lambda: not work_state()["places"])
            before = descriptors()
            ipc("f8Shell", "refreshPlaces")
            wait(lambda: work_state()["places"])
            busy = descriptors()
            held = {key: owner for key, owner in busy["owners"].items() if "FILECHOOSER_FD_PROBE" in owner["command"]}
            check("scan-pidfd-owned", bool(held), held)
            pipes = set(busy["links"].values()) - set(before["links"].values())
            pipes = {link for link in pipes if link.startswith("pipe:")}
            check("scan-three-live-pipes", len(pipes) == 3, sorted(pipes))
            sample("scan-finished")
            after = descriptors()
            check("scan-exact-pipes-closed", not pipes.intersection(after["links"].values()), after)
            check("scan-pidfd-reaped", all(not Path(f"/proc/{owner['pid']}").exists() for owner in held.values()))
            phases = json.loads((output / "raw-phases-scan-finished.json").read_text())
            check("busy-phase-retained", bool(phases) and any(p["before"]["places"] or p["after"]["places"] for p in phases))
            (output / "fd-probe.json").write_text(json.dumps({"before": before, "busy": busy, "after": after, "pipes": sorted(pipes)}, indent=2))
            ipc("f8Shell", "quit"); shell_proc.wait(timeout=12)
            complete = True
            return
        if a.diagnose:
            folders = {}
            for name in ("empty", "image", "text", "pdf"):
                folders[name] = fixtures / name
                folders[name].mkdir()
            shutil.copy2(next(Path("/home/tester/Pictures").glob("*.png")), folders["image"] / "Sample.png")
            (folders["text"] / "Sample.txt").write_text("Resource ownership fixture\n")
            shutil.copy2("/home/tester/Documents/Weekend itinerary.pdf", folders["pdf"] / "Sample.pdf")
            phases = [("empty", folders["empty"], ""), ("image", folders["image"], ""),
                      ("thumbnails", videos, ""), ("browse", videos, ""),
                      ("video", videos, "video"), ("audio", audio, "audio"),
                      ("text", folders["text"], "text"), ("pdf", folders["pdf"], "pdf")]
            for index, (name, folder, kind) in enumerate(phases):
                sample(name + "-before")
                proc = open_folder(folder, index)
                time.sleep(.5); sample(name + "-open")
                if name == "browse":
                    for _ in range(12):
                        keys("key", "108:1", "108:0")
                if kind:
                    keys("key", "102:1", "102:0")
                    keys("key", "57:1", "57:0")
                    wait(lambda: state()["preview"] and state()["kind"] == kind and state()["rendered"] in ("ready", "info"))
                    time.sleep(.5); sample(name + "-preview")
                    keys("key", "1:1", "1:0")
                    wait(lambda: not state()["preview"])
                    time.sleep(.5); sample(name + "-preview-closed")
                keys("key", "1:1", "1:0")
                proc.wait(timeout=8)
                time.sleep(1); sample(name + "-closed")
            ipc("f8Shell", "quit"); shell_proc.wait(timeout=12)
            complete = True
            return
        for cycle in range(1, a.cycles + 1):
            for folder, kind in ((videos, "video"), (audio, "audio")):
                proc = open_folder(folder, cycle * 2 + (kind == "audio"))
                check(f"cycle-{cycle}-{kind}-listing", state()["count"] == (48 if kind == "video" else 1))
                if kind == "video":
                    # Scroll through all 48 visible-interest sets, then return
                    # to Home and observe consumer images ready.
                    for _ in range(12):
                        keys("key", "108:1", "108:0")
                    keys("key", "102:1", "102:0")
                    wait(lambda: state()["tiles"] and all(t["ready"] for t in state()["tiles"]))
                else:
                    keys("key", "102:1", "102:0")
                keys("key", "57:1", "57:0")
                wait(lambda: state()["preview"] and state()["kind"] == kind and state()["rendered"] == "ready")
                if a.heap_probe:
                    counts = json.loads(ipc("f8Shell", "lifetimes"))
                    check(f"cycle-{cycle}-{kind}-active-native-counts", counts == {"players": 1, "outputs": 1, "controls": 1, "requests": 1}, counts)
                if observe_retention:
                    ledger = json.loads(ipc("f8Shell", "leakCounts"))
                    live = {key: ledger["live"].get(key, 0) for key in KINDS}
                    singles = ("portal_entries", "requests", "browsers", "selections", "previews", "playbacks", "windows", "thumbnail_providers", "players", "outputs", "controls")
                    # Settled JS-owned replies may remain live until the idle
                    # GC after BOTH media kinds; pending ownership is not an
                    # exact count of collectable objects before that GC.
                    check(f"cycle-{cycle}-{kind}-active-chooser-objects", all(live[key] == 1 for key in singles) and live["entries"] > 0
                          and live["held_replies"] >= 1 and ledger["created"]["held_replies"] == ledger["created"]["portal_entries"]
                          and (kind != "video" or (live["thumbnails"] > 0 and live["thumbnail_workers"] > 0)), live)
                before = state()["position"]
                time.sleep(.5)
                # Position can wrap at the end of a correctly looping video.
                check(f"cycle-{cycle}-{kind}-playing", state()["position"] != before)
                keys("key", "1:1", "1:0")
                wait(lambda: not state()["preview"])
                keys("key", "1:1", "1:0")
                proc.wait(timeout=8)
                check(f"cycle-{cycle}-{kind}-closed", proc.returncode == 0)
            time.sleep(1)
            if a.heap_probe:
                sample("pre-gc-" + str(cycle))
                ipc("f8Shell", "collectGarbage")
            sample(cycle)
        if a.leak_diagnostic:
            ipc("f8Shell", "quit"); shell_proc.wait(timeout=30)
            acceptance = {"diagnostic_only": True, "resource_acceptance_run": False, "cycles": a.cycles,
                          "metrics": "post-GC regular+large JS bytes; exact epoch-refreshed jemalloc stats.allocated; native object ledger; FDs/PSS"}
            complete = True
            return
        if a.heap_probe:
            ipc("f8Shell", "quit"); shell_proc.wait(timeout=12)
            complete = True
            return
        if diagnostic:
            ipc("f8Shell", "quit"); shell_proc.wait(timeout=12)
            acceptance = {"diagnostic_only": True, "resource_acceptance_run": False}
            complete = True
            return
        # Answer4/5: measure retention, not physical-page sawtooth. The complete
        # corrected1.1.0 curve f10r12-chooser120-full (30warm-up+90observed)
        # has JS slope0.00002984KiB/cycle, native8.86666 (last20:-0.48803).
        # All71overlapping20-cycle windows have native slope<=20.17165 and
        # JS<=0.001786; all15idle object counts0 and actualFDs95 throughout.
        # The earlier attributable inline-compiler/held-reply owners were fixed
        # before choosing these guards. Keep answer4's generous16/64KiB/cycle
        # live-state limits, balanced idle lifetimes over ALL51checkpoints, and
        # flat20FDcounts. PSS is only a32MiB sanity span: no slope/mean gate.
        # Preserve every checkpoint and the subject-only allocator/THP profile;
        # the GC/GUI-transaction barrier observes deferred native destruction.
        acceptance = retention_acceptance(samples)
        for name, condition in acceptance["checks"].items():
            check(name, condition, acceptance)
        ipc_fds_before = len(list(Path(f"/proc/{pid}/fd").iterdir()))
        for _ in range(25):
            ipc("f8Shell", "ready")
        ipc_fds_after = len(list(Path(f"/proc/{pid}/fd").iterdir()))
        check("ipc-polling-keeps-descriptors-flat", ipc_fds_before == ipc_fds_after)
        # Only the outer launcher's control plane can contact the user manager.
        # Request its fixed 64 MiB probe while this protected session stays live.
        base = Path(os.environ["FILECHOOSER_ISOLATION"])
        pending = base / "memory-probe.pending"
        pending.write_text("64MiB\n")
        pending.replace(base / "memory-probe.request")
        probe_receipt = ROOT / "evidence" / (a.label + "-isolation") / "memory-probe.json"
        wait(lambda: probe_receipt.exists(), 45)
        result = json.loads(probe_receipt.read_text())
        check("hungry-stopped-by-own-limit", result["passed"], result)
        check("session-still-responsive", session_proc.poll() is None and session_ipc("state") == "true")
        check("session-files-unchanged", protected == {name: hashes(session_base / name) for name in protected})
        ipc("f8Shell", "quit"); shell_proc.wait(timeout=12)
        check("dev-shell-clean-exit", shell_proc.returncode == 0)
        # Exercise the real harness entrance beside the protected session, then
        # the same exact-source gate used for milestone acceptance.
        harness_label = a.label + "-harness"
        log = (output / "harness-driver.log").open("w"); logs.append(log)
        harness = subprocess.Popen([sys.executable, "-B", str(source / "Scripts/dev/filechooser-harness.py"),
                                   "--source", str(source), "--label", harness_label], stdout=log, stderr=subprocess.STDOUT)
        harness_probe = ROOT / "runtime" / harness_label / "shell/filechooser-harness.qml"
        wait(lambda: json.loads(command(["qs", "-p", harness_probe, "ipc", "call", "filechooserHarness", "state"]).stdout)["ready"])
        check("harness-next-to-session", session_ipc("state") == "true")
        command(["qs", "-p", harness_probe, "ipc", "call", "filechooserHarness", "quit"])
        harness.wait(timeout=12)
        check("harness-clean-exit", harness.returncode == 0)
        # The companion must stay alive, but the gate must not share its
        # memory.high/CPU quota. The media subject/harness are already stopped.
        # Only the outer trusted controller can launch this fixed sibling slot.
        gate = request_gate(ROOT / "evidence" / (a.label + "-isolation"))
        (output / "independent-gate.json").write_text(json.dumps(gate, indent=2))
        check("contained-shell-gate-next-to-session", gate["passed"] and gate["exit"] == 0, gate)
        gate_output = Path(gate["output"])
        (output / "gate.log").write_text((gate_output / "service.log").read_text())
        gate_group = Path("/sys/fs/cgroup" + gate["properties"]["ControlGroup"])
        check("gate-independent-cgroup-budget", gate_group != cgroup() and gate_group.parent == cgroup().parent
              and int(gate["properties"]["MemoryMax"]) <= 768 * 1024 * 1024
              and int(gate["properties"]["MemoryHigh"]) <= int((cgroup() / "memory.high").read_text()), gate)
        gate_env = json.loads((gate_output / "environment.json").read_text())
        check("gate-private-session-disjoint", all(gate_env[key] != os.environ[key] for key in ("HOME", "XDG_RUNTIME_DIR", "DBUS_SESSION_BUS_ADDRESS", "FILECHOOSER_PID_NAMESPACE")))
        gate_audit = json.loads((gate_output / "process-cgroups.json").read_text())
        lint = [row for row in gate_audit["processes"] if row["command"] and Path(row["command"].split()[0]).name in ("qmllint", "qmllint6")]
        check("qmllint-independent-contained", bool(lint) and not gate_audit["errors"] and not gate_audit["violations"]
              and all(row["cgroup"] == str(gate_group) and row["oom_score_adj"] == "1000" for row in lint), [{key: row[key] for key in ("pid", "cgroup", "oom_score_adj")} for row in lint])
        check("session-responsive-after-harness-and-gate", session_proc.poll() is None and session_ipc("state") == "true")
        check("session-files-unchanged-after-harness-and-gate", protected == {name: hashes(session_base / name) for name in protected})
        check("parent-kernel-thp-policy-unchanged", parent_thp == int(next(line.split()[1] for line in Path("/proc/self/status").read_text().splitlines() if line.startswith("THP_enabled:")))
              and Path("/sys/kernel/mm/transparent_hugepage/enabled").read_text() == thp_policy)
        complete = True
    except Exception as error:
        failure = repr(error)
        raise
    finally:
        if shell_proc and shell_proc.poll() is None:
            try:
                ipc("f8Shell", "quit"); shell_proc.wait(timeout=12)
            except Exception as error:
                failure += " dev cleanup: " + repr(error)
        if session_proc and session_proc.poll() is None and session_env:
            try:
                session_ipc("quit"); session_proc.wait(timeout=12)
            except Exception as error:
                failure += " session cleanup: " + repr(error)
        for log in logs:
            log.close()
        (output / "result.json").write_text(json.dumps({"passed": complete and all(c["pass"] for c in cases), "complete": complete,
            "cases": cases, "memory": samples, "failure": failure, "acceptance": acceptance,
            "diagnostic": {"heap": a.heap_probe, "fd": a.fd_probe, "malloc": a.malloc_probe, "memory_trace": a.memory_trace, "jemalloc": a.jemalloc_probe, "lifetime": a.lifetime_probe, "leak": a.leak_diagnostic}}, indent=2))


if __name__ == "__main__":
    main()
