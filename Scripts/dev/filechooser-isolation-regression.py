#!/usr/bin/env python3
"""Containment regression and full-shell picker memory exercise (assigned VM)."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

from filechooser_isolation import ROOT, cgroup, enter, input_command, profile_env


def command(argv, env=None, seconds=15, check=True):
    return subprocess.run(["timeout", str(seconds), *map(str, argv)], env=env,
                          capture_output=True, text=True, timeout=seconds + 5, check=check)


def hashes(path):
    return {str(p.relative_to(path)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in path.rglob("*") if p.is_file() and not p.is_symlink()}


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


def instrument(shell, filename, handler):
    path = shell / filename
    text = path.read_text()
    index = text.rfind("}")
    path.write_text("import Quickshell.Io\n" + text[:index] + handler + text[index:])


def main():
    enter()
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--source", type=Path, required=True)
    p.add_argument("--label", required=True)
    a = p.parse_args()
    source = a.source.resolve()
    output, runtime = ROOT / "evidence" / a.label, ROOT / "runtime" / a.label
    assert source.is_relative_to(ROOT / "sources")
    output.mkdir(); runtime.mkdir()
    cases, samples = [], []
    def check(name, condition, detail=None):
        cases.append({"case": name, "pass": bool(condition), "detail": detail})
        print(name, "PASS" if condition else "FAIL", flush=True)
        assert condition, name
    complete, failure = False, ""
    shell_proc = session_proc = None
    logs = []
    session_env = None
    try:
        # Fail old trees before executing their unsafe runner. This is the red
        # contract boundary: the old harness has no isolation entrance at all.
        check("source-has-shared-isolation-boundary", (source / "Scripts/dev/filechooser_isolation.py").is_file())
        shell = runtime / "shell"
        shutil.copytree(source, shell, symlinks=True)
        env = profile_env(runtime / "profile")
        defaults = json.loads((source / "Configs/defaults.json").read_text())
        defaults["general"]["showChangelogOnStartup"] = False
        (runtime / "profile/config/settings.json").write_text(json.dumps(defaults))
        # Diagnostic observer exists only in this disposable copy. It observes
        # the real production portal's window and real renderer at the consumer.
        instrument(shell, "shell.qml", '''
  IpcHandler {
    target: "f8Shell"
    function ready(): string { return JSON.stringify(shellRoot.settingsLoaded && shellRoot.i18nLoaded); }
    function quit(): void { Qt.quit(); }
  }
''')
        instrument(shell, "Modules/FileChooser/FileChooserWindow.qml", '''
  IpcHandler {
    target: "f8Picker"
    function state(): string { return JSON.stringify({
      ready: request.browser.status === "ready", count: request.browser.count,
      name: request.browser.entry(request.selection.cursor)?.name || "",
      preview: root.quickLookOpen, kind: root.preview.kind,
      rendered: root.previewRenderer ? root.previewRenderer.previewState : "",
      position: root.previewRenderer && root.previewRenderer.position !== undefined ? root.previewRenderer.position : -1,
      tiles: root.thumbnailState().tiles
    }); }
  }
''')
        # A second disposable session has its own compositor, HOME and bus.
        # The shared supervisor is reused, not another hand-written recipe.
        session_base = ROOT / "runtime" / ("s" + str(os.getpid()))
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
        helper = source / "Scripts/dev/filechooser_isolation.py"
        # The supervisor takes a Python entry point, so a tiny owned driver
        # waits for this session's qs; no login session environment is inherited.
        child = runtime / "session-child.py"
        child.write_text("import os,shutil,subprocess\nfrom pathlib import Path\n"
                         "config=Path(os.environ['XDG_CONFIG_HOME'])/'atmosphera'\nconfig.mkdir()\n"
                         "shutil.copyfile(" + repr(str(source / "Configs/defaults.json")) + ",config/'settings.json')\n"
                         "raise SystemExit(subprocess.run(['timeout','650','qs','-p'," + repr(str(probe)) + "], timeout=660).returncode)\n")
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
        shell_proc = subprocess.Popen(["timeout", "600", "qs", "-p", str(shell / "shell.qml")], env=env, stdout=log, stderr=subprocess.STDOUT)
        def ipc(target, member):
            return command(["qs", "-p", shell / "shell.qml", "ipc", "call", target, member], env).stdout.strip()
        wait(lambda: ipc("f8Shell", "ready") == "true", 35)
        wait(lambda: command(["busctl", "--address=" + env["DBUS_SESSION_BUS_ADDRESS"], "call", "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "NameHasOwner", "s", "org.freedesktop.impl.portal.desktop.atmosphera"], env).stdout.strip() == "b true")
        pid = int(command(["busctl", "--address=" + env["DBUS_SESSION_BUS_ADDRESS"], "call", "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "GetConnectionUnixProcessID", "s", "org.freedesktop.impl.portal.desktop.atmosphera"], env).stdout.split()[1])
        def sample(cycle):
            values = {}
            for line in Path(f"/proc/{pid}/smaps_rollup").read_text().splitlines():
                parts = line.split()
                if parts[0] in ("Rss:", "Pss:", "Private_Dirty:", "Anonymous:"):
                    values[parts[0][:-1] + "_kib"] = int(parts[1])
            row = {"cycle": cycle, **values, "fds": len(list(Path(f"/proc/{pid}/fd").iterdir())),
                   "cgroup_bytes": int((cgroup() / "memory.current").read_text())}
            samples.append(row)
            descriptors = {}
            for fd in Path(f"/proc/{pid}/fd").iterdir():
                try:
                    descriptors[fd.name] = os.readlink(fd)
                except FileNotFoundError:
                    pass
            (output / f"fds-{cycle}.json").write_text(json.dumps(descriptors, indent=2))
            (output / "memory.json").write_text(json.dumps(samples, indent=2))
            print("MEMORY", json.dumps(row), flush=True)
        def state():
            return json.loads(ipc("f8Picker", "state"))
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
        for cycle in range(1, 13):
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
                before = state()["position"]
                time.sleep(.5)
                check(f"cycle-{cycle}-{kind}-playing", state()["position"] > before)
                keys("key", "1:1", "1:0")
                wait(lambda: not state()["preview"])
                keys("key", "1:1", "1:0")
                proc.wait(timeout=8)
                check(f"cycle-{cycle}-{kind}-closed", proc.returncode == 0)
            time.sleep(1); sample(cycle)
        # Warm-up allocations are distinct from retained growth. Preserve all
        # measurements even on failure; the final six-cycle range is reported.
        tail = [s["Pss_kib"] for s in samples[-6:]]
        check("post-warmup-memory-bounded", max(tail) - min(tail) < 64 * 1024, tail)
        # Separate IPC polling from a dependency's child-process bookkeeping.
        # This diagnostic imports no Atmosphera code and preserves its result;
        # it cannot justify a product workaround for a native resource leak.
        ipc_fds_before = len(list(Path(f"/proc/{pid}/fd").iterdir()))
        for _ in range(25):
            ipc("f8Shell", "ready")
        ipc_fds_after = len(list(Path(f"/proc/{pid}/fd").iterdir()))
        native_probe = runtime / "native-process.qml"
        native_probe.write_text('''import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {
  id: root
  property int completed: 0
  Component {
    id: factory
    Process {
      command: ["/usr/bin/true"]
      stdout: StdioCollector {}
      stderr: StdioCollector {}
      onExited: { root.completed++; destroy(); }
    }
  }
  IpcHandler {
    target: "f8Native"
    function run(): void { var process = factory.createObject(root); process.running = true; }
    function state(): string { return JSON.stringify(root.completed); }
    function quit(): void { Qt.quit(); }
  }
}
''')
        log = (output / "native-process.log").open("w"); logs.append(log)
        native = subprocess.Popen(["qs", "-p", str(native_probe)], env=env, stdout=log, stderr=subprocess.STDOUT)
        def native_ipc(member):
            return command(["qs", "-p", native_probe, "ipc", "call", "f8Native", member], env).stdout.strip()
        try:
            wait(lambda: native_ipc("state") == "0")
            def null_fds():
                result = []
                for fd in Path(f"/proc/{native.pid}/fd").iterdir():
                    try:
                        if os.readlink(fd) == "/dev/null":
                            result.append(fd.name)
                    except FileNotFoundError:
                        pass
                return result
            before = null_fds()
            for _ in range(25):
                native_ipc("run")
            wait(lambda: native_ipc("state") == "25")
            time.sleep(.5)
            after = null_fds()
            (output / "native-fds.json").write_text(json.dumps({"ipc_only_before": ipc_fds_before, "ipc_only_after": ipc_fds_after,
                "native_processes": 25, "native_null_fds_before": before, "native_null_fds_after": after}, indent=2))
        finally:
            native_ipc("quit"); native.wait(timeout=12)
        # A small deliberately hungry sibling unit proves kernel cgroup OOM,
        # without approaching global exhaustion or exercising the console.
        admin = dict(os.environ, XDG_RUNTIME_DIR="/run/user/1000", DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/1000/bus")
        unit = "filechooser-" + a.label + "-hungry"
        hungry = command(["systemd-run", "--user", "--wait", "--pipe", "--unit=" + unit,
                          "-p", "MemoryMax=64M", "-p", "MemoryHigh=infinity", "-p", "MemorySwapMax=0", "-p", "CPUQuota=25%",
                          "-p", "RuntimeMaxSec=20", "-p", "OOMPolicy=stop", "--setenv=TMPDIR=" + str(ROOT / "tmp"),
                          "/usr/bin/env", "-i", *[k + "=" + v for k, v in env.items()],
                          sys.executable, "-c", "x=bytearray(128*1024*1024)"], admin, 30, False)
        result = command(["systemctl", "--user", "show", unit, "-p", "Result", "-p", "MemoryMax", "-p", "MemoryPeak"], admin).stdout
        (output / "hungry.log").write_text(hungry.stdout + hungry.stderr + result)
        check("hungry-stopped-by-own-limit", hungry.returncode != 0 and "Result=oom-kill" in result, result)
        command(["systemctl", "--user", "reset-failed", unit], admin)
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
        gate = command([sys.executable, "-B", ROOT / "tools/shell-gate.py", "--source", source, "--label", a.label + "-gate", "--audit"], seconds=420, check=False)
        (output / "gate.log").write_text(gate.stdout + gate.stderr)
        check("contained-shell-gate-next-to-session", gate.returncode == 0, gate.stdout + gate.stderr)
        check("session-responsive-after-harness-and-gate", session_proc.poll() is None and session_ipc("state") == "true")
        check("session-files-unchanged-after-harness-and-gate", protected == {name: hashes(session_base / name) for name in protected})
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
            "cases": cases, "memory": samples, "failure": failure}, indent=2))


if __name__ == "__main__":
    main()
