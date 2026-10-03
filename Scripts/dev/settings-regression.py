#!/usr/bin/env python3
"""Retained Settings regression runner (plan: post-071-settings-icons-release-notes).

Runs INSIDE the test guest. For each case it builds a disposable shell copy
(the tree given by --source, plus the passive probe fixture from THIS tree's
Scripts/dev/fixtures/settings-regression.qml), seeds an isolated config/cache,
launches a fresh qs process with a private D-Bus session against the guest's
live niri/Wayland session, and asserts readiness, consumer values, warning
evidence, and file persistence.

Usage:
  settings-regression.py --source <tree> --output <dir> --case all|<name>[,<name>...]

Exit 0 + "SETTINGS_REGRESSION: PASS" only when every selected case passes.
The baseline (unfixed) tree is expected to fail the unknown-key cases with
the original "Cannot assign to non-existent property" exception and missing
settings readiness.
"""

import argparse
import glob
import json
import os
import queue
import re
import shutil
import subprocess
import sys
import threading
import time
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
PROBE_SRC = SCRIPT_DIR / "fixtures" / "settings-regression.qml"
PROBE_NAME = "settings-regression-probe.qml"

UNKNOWN_WARN_RE = re.compile(r"Ignoring unknown setting: ([A-Za-z0-9_.\-]+)(\x1b\[[0-9;]*m)?\s*$")
ERROR_PATTERNS = [
    "Cannot assign to non-existent property",
    "ReferenceError",
    "TypeError",
    "is not installed",
    "Component is not ready",
    "Cannot read property",
]

PROBE_DEADLINE_S = 90
SHELL_DEADLINE_S = 70
SHELL_RUN_S = 30


# ---------------------------------------------------------------- env

def discover_session_env():
    socks = sorted(glob.glob("/run/user/1000/niri.*.sock"))
    if len(socks) != 1:
        raise SystemExit(f"FATAL: expected exactly one niri socket in /run/user/1000, found {len(socks)}: {socks}")
    if not os.path.exists("/run/user/1000/wayland-1"):
        raise SystemExit("FATAL: /run/user/1000/wayland-1 missing — guest Wayland session not available")
    for tool in ("qs", "dbus-run-session"):
        if shutil.which(tool) is None:
            raise SystemExit(f"FATAL: required tool not found on PATH: {tool}")
    return {
        "XDG_RUNTIME_DIR": "/run/user/1000",
        "WAYLAND_DISPLAY": "wayland-1",
        "NIRI_SOCKET": socks[0],
    }


def case_env(session, case_dir):
    env = dict(os.environ)
    env.update(session)
    env.update({
        "ATMOSPHERA_CONFIG_DIR": str(case_dir / "config"),
        "ATMOSPHERA_CACHE_DIR": str(case_dir / "cache"),
        "ATMOSPHERA_SETTINGS_FILE": str(case_dir / "config" / "settings.json"),
        "ATMOSPHERA_DEBUG": "0",
    })
    return env


# --------------------------------------------------------------- files

def write_json_atomic(path, obj):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(obj, indent=2) + "\n")
    os.replace(tmp, path)


def read_json(path):
    return json.loads(Path(path).read_text())


def wait_for_file_json(path, predicate, timeout_s=6.0):
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        try:
            data = read_json(path)
            if predicate(data):
                return data
        except Exception:
            pass
        time.sleep(0.25)
    return None


# -------------------------------------------------------------- probe

def parse_probe_line(line):
    idx = line.find("PROBE|")
    if idx < 0:
        return None, None
    rest = line[idx:].strip()
    parts = rest.split("|", 2)
    if len(parts) != 3:
        return None, None
    try:
        return parts[1], json.loads(parts[2])
    except json.JSONDecodeError:
        return parts[1], None


def run_probe_leg(case_dir, env, log_name, on_marker=None):
    """Launch the probe; stream output to a log; dispatch marker callbacks.

    The probe self-exits by design (Qt.exit). If it exceeds the deadline we
    terminate only our own child process — never a name-wide kill.
    """
    shell_dir = case_dir / "shell"
    log_path = case_dir / log_name
    cmd = ["dbus-run-session", "--", "qs", "-p", str(shell_dir / PROBE_NAME)]
    proc = subprocess.Popen(cmd, env=env, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True, bufsize=1)
    lines = []
    q = queue.Queue()

    def reader():
        for line in proc.stdout:
            lines.append(line)
            q.put(line)

    t = threading.Thread(target=reader, daemon=True)
    t.start()
    deadline = time.time() + PROBE_DEADLINE_S
    timed_out = False
    while True:
        if time.time() > deadline:
            timed_out = True
            proc.terminate()  # our own child only
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
            break
        try:
            line = q.get(timeout=0.25)
        except queue.Empty:
            if proc.poll() is not None:
                break
            continue
        if on_marker:
            tag, payload = parse_probe_line(line)
            if tag:
                on_marker(tag, payload)
        if proc.poll() is not None and q.empty():
            break
    proc.wait(timeout=10)
    log_path.write_text("".join(lines))
    return log_path, proc.returncode, timed_out


def run_shell_leg(case_dir, env, log_name):
    """Cold-load leg: launch the actual shell.qml entry of the disposable copy.

    A clean load stays alive until `timeout` terminates our own child after
    SHELL_RUN_S seconds (exit 124). Any earlier exit or QML error pattern is
    a load failure.
    """
    shell_dir = case_dir / "shell"
    log_path = case_dir / log_name
    inner = f'timeout --signal=TERM {SHELL_RUN_S} qs -p "{shell_dir}/shell.qml" 2>&1; echo "SHELL_QS_EXIT=$?"'
    cmd = ["dbus-run-session", "--", "sh", "-c", inner]
    proc = subprocess.Popen(cmd, env=env, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True)
    try:
        out, _ = proc.communicate(timeout=SHELL_DEADLINE_S)
    except subprocess.TimeoutExpired:
        proc.terminate()
        out, _ = proc.communicate(timeout=10)
    log_path.write_text(out)
    m = re.search(r"SHELL_QS_EXIT=(\d+)", out)
    return log_path, (int(m.group(1)) if m else None), out


# ---------------------------------------------------------- assertions

def collect_probe_events(log_path):
    events = []
    for line in Path(log_path).read_text(errors="replace").splitlines():
        tag, payload = parse_probe_line(line)
        if tag:
            events.append((tag, payload))
    return events


def last_values(events, tags=("DONE", "RELOADED", "SAVED", "READY")):
    for tag, payload in reversed(events):
        if tag in tags and isinstance(payload, dict):
            return tag, payload
    return None, {}


def unknown_warnings(log_path):
    paths = []
    leaks = []
    for line in Path(log_path).read_text(errors="replace").splitlines():
        if "Ignoring unknown setting:" in line:
            m = UNKNOWN_WARN_RE.search(line)
            if m:
                paths.append(m.group(1))
            else:
                leaks.append(line.strip())
    return paths, leaks


def error_lines(log_path):
    hits = []
    for line in Path(log_path).read_text(errors="replace").splitlines():
        for pat in ERROR_PATTERNS:
            if pat in line:
                hits.append(line.strip())
                break
    return hits


class Case:
    def __init__(self, name):
        self.name = name
        self.failures = []

    def check(self, cond, msg):
        if not cond:
            self.failures.append(msg)

    def check_probe_done(self, log_path, expect_values=None, allow_stages=("DONE",)):
        events = collect_probe_events(log_path)
        tags = [t for t, _ in events]
        self.check("FAIL" not in tags, f"probe reported FAIL: {[p for t, p in events if t == 'FAIL']}")
        self.check("READY" in tags, "probe never observed settings readiness")
        tag, values = last_values(events, allow_stages)
        if expect_values:
            for path, expected in expect_values.items():
                actual = values.get(path)
                self.check(actual == expected,
                           f"consumer value {path}: expected {expected!r}, got {actual!r} (last {tag})")
        return events

    def check_warnings(self, log_path, required=(), forbidden=(), none=False):
        paths, leaks = unknown_warnings(log_path)
        self.check(not leaks, f"unknown-setting warnings leaked values: {leaks}")
        if none:
            self.check(paths == [], f"unexpected unknown-setting warnings: {paths}")
        for req in required:
            self.check(req in paths, f"missing warning for unknown path: {req} (got {paths})")
        for forb in forbidden:
            self.check(forb not in paths, f"unexpected warning for path: {forb}")

    def check_no_errors(self, log_path):
        hits = error_lines(log_path)
        self.check(not hits, f"QML error patterns in {Path(log_path).name}: {hits[:5]}")


# -------------------------------------------------------------- cases

def case_clean_start(runner, case_dir, case):
    env = runner.env_for(case_dir, {
        "PROBE_CASE": "observe",
        "PROBE_VALUES": "bar.position",
    })
    log, rc, to = run_probe_leg(case_dir, env, "run.log")
    case.check(not to, "probe leg timed out")
    case.check(rc == 0, f"probe leg exit code {rc}")
    case.check_probe_done(log, {"bar.position": "top"})
    case.check_warnings(log, none=True)
    case.check_no_errors(log)

    # Cold-load leg: the actual shell.qml entry of the disposable copy.
    slog, qs_exit, _ = run_shell_leg(case_dir, runner.env_for(case_dir, {}), "shell-run.log")
    case.check(qs_exit == 124, f"shell.qml cold-load exit {qs_exit} (expected 124 = alive until timeout)")
    case.check_warnings(slog, none=True)
    case.check_no_errors(slog)

    # No automatic override creation
    overrides = list((case_dir / "config" / "settings").glob("*.json"))
    case.check(overrides == [], f"unexpected auto-created override files: {overrides}")
    case.check(not (case_dir / "config" / "settings.json").exists(),
               "unexpected auto-created legacy settings.json")


def _simple_seed_case(seed_section, seed_obj, values, expected, required_warnings,
                      forbidden_warnings=(), none_warnings=False):
    def fn(runner, case_dir, case):
        write_json_atomic(case_dir / "config" / "settings" / f"{seed_section}.json", seed_obj)
        env = runner.env_for(case_dir, {"PROBE_CASE": "observe", "PROBE_VALUES": ",".join(values)})
        log, rc, to = run_probe_leg(case_dir, env, "run.log")
        case.check(not to, "probe leg timed out")
        case.check(rc == 0, f"probe leg exit code {rc}")
        case.check_probe_done(log, expected)
        case.check_warnings(log, required=required_warnings,
                            forbidden=forbidden_warnings, none=none_warnings)
        case.check_no_errors(log)
    return fn


def case_legacy_initial(runner, case_dir, case):
    legacy = case_dir / "config" / "settings.json"
    write_json_atomic(legacy, {
        "settingsVersion": 60,
        "general": {"avatarImage": "/tmp/probe-legacy.png", "lockScreenMode": "legacy-x"},
        "unknownLegacySection": {"x": 1},
    })
    seed_bytes = legacy.read_bytes()
    env = runner.env_for(case_dir, {
        "PROBE_CASE": "observe",
        "PROBE_VALUES": "general.avatarImage",
    })
    log, rc, to = run_probe_leg(case_dir, env, "run.log")
    case.check(not to, "probe leg timed out")
    case.check_probe_done(log, {"general.avatarImage": "/tmp/probe-legacy.png"})
    case.check_warnings(log, required=["general.lockScreenMode", "unknownLegacySection"])
    case.check_no_errors(log)
    case.check(legacy.read_bytes() == seed_bytes, "legacy settings.json bytes changed during startup")


def case_section_external_mixed(runner, case_dir, case):
    target = case_dir / "config" / "settings" / "general.json"
    write_json_atomic(target, {"dimmerOpacity": 0.5})

    def on_marker(tag, _payload):
        if tag == "READY":
            write_json_atomic(target, {"dimmerOpacity": 0.77, "lockScreenMode": "y"})

    env = runner.env_for(case_dir, {
        "PROBE_CASE": "external-edit",
        "PROBE_VALUES": "general.dimmerOpacity",
    })
    log, rc, to = run_probe_leg(case_dir, env, "run.log", on_marker=on_marker)
    case.check(not to, "probe leg timed out")
    events = case.check_probe_done(log, {"general.dimmerOpacity": 0.77}, allow_stages=("RELOADED",))
    case.check(any(t == "RELOADED" for t, _ in events), "settingsReloaded never observed")
    case.check_warnings(log, required=["general.lockScreenMode"])
    case.check_no_errors(log)


def case_legacy_external_unknown(runner, case_dir, case):
    legacy = case_dir / "config" / "settings.json"
    write_json_atomic(legacy, {"settingsVersion": 60, "general": {"scaleRatio": 1.0}})
    write_json_atomic(case_dir / "config" / "settings" / "bar.json", {"position": "bottom"})

    def on_marker(tag, _payload):
        if tag == "READY":
            write_json_atomic(legacy, {
                "settingsVersion": 60,
                "general": {"scaleRatio": 1.5, "lockScreenMode": "q"},
                "bar": {"position": "left"},
            })

    env = runner.env_for(case_dir, {
        "PROBE_CASE": "external-edit",
        "PROBE_VALUES": "general.scaleRatio,bar.position",
    })
    log, rc, to = run_probe_leg(case_dir, env, "run.log", on_marker=on_marker)
    case.check(not to, "probe leg timed out")
    events = case.check_probe_done(log, {"general.scaleRatio": 1.5, "bar.position": "bottom"},
                                   allow_stages=("RELOADED",))
    case.check(any(t == "RELOADED" for t, _ in events), "settingsReloaded never observed")
    case.check_warnings(log, required=["general.lockScreenMode"])
    case.check_no_errors(log)


def case_section_byte_identical(runner, case_dir, case):
    ui = case_dir / "config" / "settings" / "ui.json"
    bar = case_dir / "config" / "settings" / "bar.json"
    write_json_atomic(ui, {"fontDefaultScale": 1.25})
    write_json_atomic(bar, {"position": "bottom"})
    ui_bytes, bar_bytes = ui.read_bytes(), bar.read_bytes()
    env = runner.env_for(case_dir, {
        "PROBE_CASE": "observe",
        "PROBE_VALUES": "ui.fontDefaultScale",
    })
    log, rc, to = run_probe_leg(case_dir, env, "run.log")
    case.check(not to, "probe leg timed out")
    case.check_probe_done(log, {"ui.fontDefaultScale": 1.25})
    case.check_warnings(log, none=True)
    case.check_no_errors(log)
    case.check(ui.read_bytes() == ui_bytes, "ui.json changed during startup")
    case.check(bar.read_bytes() == bar_bytes, "bar.json changed during startup")


def case_save_restart(runner, case_dir, case):
    target = case_dir / "config" / "settings" / "general.json"
    write_json_atomic(target, {"lockScreenMode": "old", "dimmerOpacity": 0.44})

    # Phase 1: known-setting save through the tracked-set write path
    env = runner.env_for(case_dir, {
        "PROBE_CASE": "save",
        "PROBE_EDIT_PATH": "general.dimmerOpacity",
        "PROBE_EDIT_VALUE": "0.66",
        "PROBE_VALUES": "general.dimmerOpacity",
    })
    log, rc, to = run_probe_leg(case_dir, env, "run-save.log")
    case.check(not to, "save leg timed out")
    events = case.check_probe_done(log, {"general.dimmerOpacity": 0.66}, allow_stages=("SAVED", "DONE"))
    case.check(any(t == "SAVED" for t, _ in events), "settingsSaved never observed")
    case.check_warnings(log, required=["general.lockScreenMode"])
    case.check_no_errors(log)

    persisted = wait_for_file_json(
        target,
        lambda d: d.get("dimmerOpacity") == 0.66 and d.get("lockScreenMode") == "old")
    case.check(persisted is not None,
               f"persisted general.json missing unknown entry or new value: {persisted}")

    # Phase 2: fresh process — value reaches the restarted consumer
    env2 = runner.env_for(case_dir, {
        "PROBE_CASE": "verify",
        "PROBE_VALUES": "general.dimmerOpacity",
    })
    log2, rc2, to2 = run_probe_leg(case_dir, env2, "run-verify.log")
    case.check(not to2, "verify leg timed out")
    case.check_probe_done(log2, {"general.dimmerOpacity": 0.66})
    case.check_no_errors(log2)


def case_unknown_only_reload_pending_edit(runner, case_dir, case):
    target = case_dir / "config" / "settings" / "ui.json"
    write_json_atomic(target, {"fontDefaultScale": 1.1})

    def on_marker(tag, _payload):
        if tag == "READY":
            # Unknown-only external edit while the probe's edit is still pending
            write_json_atomic(target, {"fontDefaultScale": 1.1, "totallyUnknown": True})

    env = runner.env_for(case_dir, {
        "PROBE_CASE": "pending-edit-save",
        "PROBE_EDIT_PATH": "ui.fontDefaultScale",
        "PROBE_EDIT_VALUE": "1.61",
        "PROBE_VALUES": "ui.fontDefaultScale",
    })
    log, rc, to = run_probe_leg(case_dir, env, "run.log", on_marker=on_marker)
    case.check(not to, "probe leg timed out")
    events = case.check_probe_done(log, {"ui.fontDefaultScale": 1.61}, allow_stages=("SAVED", "DONE"))
    case.check(any(t == "SAVED" for t, _ in events), "settingsSaved never observed")
    case.check_warnings(log, required=["ui.totallyUnknown"])
    case.check_no_errors(log)

    persisted = wait_for_file_json(
        target,
        lambda d: d.get("fontDefaultScale") == 1.61 and d.get("totallyUnknown") is True)
    case.check(persisted is not None,
               f"persisted ui.json lost the pending user change or raw unknown entry: {persisted}")


def case_explicit_reset(runner, case_dir, case):
    bar = case_dir / "config" / "settings" / "bar.json"
    ui = case_dir / "config" / "settings" / "ui.json"
    write_json_atomic(bar, {"position": "bottom"})
    write_json_atomic(ui, {"fontDefaultScale": 1.3})
    env = runner.env_for(case_dir, {
        "PROBE_CASE": "reset",
        "PROBE_RESET_SECTION": "bar",
        "PROBE_VALUES": "bar.position,ui.fontDefaultScale",
    })
    log, rc, to = run_probe_leg(case_dir, env, "run.log")
    case.check(not to, "probe leg timed out")
    events = case.check_probe_done(log, {"bar.position": "top", "ui.fontDefaultScale": 1.3},
                                   allow_stages=("DONE",))
    case.check(any(t == "SAVED" for t, _ in events), "settingsSaved never observed")
    case.check_no_errors(log)

    deadline = time.time() + 6
    while bar.exists() and time.time() < deadline:
        time.sleep(0.25)
    case.check(not bar.exists(), "bar.json still present after resetSection('bar')")
    try:
        ui_data = read_json(ui)
    except Exception as e:
        ui_data = None
        case.check(False, f"ui.json unreadable after reset: {e}")
    if ui_data is not None:
        case.check(ui_data.get("fontDefaultScale") == 1.3,
                   f"ui.json content changed by reset of another section: {ui_data}")


CASES = {
    "clean-start": case_clean_start,
    "unknown-leaf-before-valid": _simple_seed_case(
        "general",
        {"lockScreenMode": "x", "avatarImage": "/tmp/probe-before.png"},
        ["general.avatarImage"],
        {"general.avatarImage": "/tmp/probe-before.png"},
        ["general.lockScreenMode"],
    ),
    "unknown-leaf-after-valid": _simple_seed_case(
        "general",
        {"avatarImage": "/tmp/probe-after.png", "lockScreenMode": "x"},
        ["general.avatarImage"],
        {"general.avatarImage": "/tmp/probe-after.png"},
        ["general.lockScreenMode"],
    ),
    "nested-unknown-beside-known": _simple_seed_case(
        "general",
        {"keybinds": {"futureKey": ["X"], "keyUp": ["W"]}},
        ["general.keybinds.keyUp"],
        {"general.keybinds.keyUp": ["W"]},
        ["general.keybinds.futureKey"],
    ),
    "unknown-object-array-values": _simple_seed_case(
        "general",
        {"unknownObject": {"a": 1}, "unknownArray": [1, 2], "avatarImage": "/tmp/probe-oa.png"},
        ["general.avatarImage"],
        {"general.avatarImage": "/tmp/probe-oa.png"},
        ["general.unknownObject", "general.unknownArray"],
        forbidden_warnings=("general.unknownObject.a",),
    ),
    "qobject-prototype-names": _simple_seed_case(
        "general",
        {"objectName": "evil", "constructor": 1, "hasOwnProperty": True,
         "avatarImage": "/tmp/probe-proto.png"},
        ["general.avatarImage", "general.objectName"],
        {"general.avatarImage": "/tmp/probe-proto.png", "general.objectName": ""},
        ["general.objectName", "general.constructor", "general.hasOwnProperty"],
    ),
    "widget-array-arbitrary-fields": _simple_seed_case(
        "bar",
        {"widgets": {"left": [{"id": "Clock", "customField": 123}]}},
        ["bar.widgets.left"],
        {"bar.widgets.left": [{"id": "Clock", "customField": 123}]},
        [],
        none_warnings=True,
    ),
    "legacy-initial-unknown": case_legacy_initial,
    "section-external-edit-mixed": case_section_external_mixed,
    "legacy-external-edit-unknown": case_legacy_external_unknown,
    "section-read-byte-identical": case_section_byte_identical,
    "save-restart-persistence": case_save_restart,
    "unknown-only-reload-pending-edit": case_unknown_only_reload_pending_edit,
    "explicit-section-reset": case_explicit_reset,
}

CASE_ORDER = list(CASES.keys())


# ------------------------------------------------------------- runner

class Runner:
    def __init__(self, source, output):
        self.source = Path(source)
        self.output = Path(output)
        self.session = discover_session_env()

    def env_for(self, case_dir, extra):
        env = case_env(self.session, case_dir)
        env.update(extra)
        return env

    def prepare_case_dir(self, name):
        case_dir = self.output / name
        if case_dir.exists():
            shutil.rmtree(case_dir)
        shell_dir = case_dir / "shell"
        shell_dir.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(self.source, shell_dir,
                        ignore=shutil.ignore_patterns(".git"),
                        ignore_dangling_symlinks=True)
        shutil.copy(PROBE_SRC, shell_dir / PROBE_NAME)
        (case_dir / "config" / "settings").mkdir(parents=True, exist_ok=True)
        (case_dir / "cache").mkdir(parents=True, exist_ok=True)
        return case_dir

    def run_case(self, name):
        case = Case(name)
        case_dir = self.prepare_case_dir(name)
        try:
            CASES[name](self, case_dir, case)
        except Exception as e:
            case.failures.append(f"runner exception: {e!r}")
        result = {
            "case": name,
            "ok": not case.failures,
            "failures": case.failures,
            "dir": str(case_dir),
        }
        (case_dir / "case.json").write_text(json.dumps(result, indent=2) + "\n")
        return result


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--source", required=True, help="shell tree under test")
    ap.add_argument("--output", required=True, help="results directory")
    ap.add_argument("--case", default="all",
                    help="case name, comma-separated list, or 'all'")
    args = ap.parse_args()

    if not PROBE_SRC.exists():
        raise SystemExit(f"FATAL: probe fixture missing: {PROBE_SRC}")
    if not (Path(args.source) / "Commons" / "Settings.qml").exists():
        raise SystemExit(f"FATAL: --source does not look like a shell tree: {args.source}")

    if args.case == "all":
        selected = CASE_ORDER
    else:
        selected = [c.strip() for c in args.case.split(",") if c.strip()]
        unknown = [c for c in selected if c not in CASES]
        if unknown:
            raise SystemExit(f"FATAL: unknown case(s): {unknown} (known: {CASE_ORDER})")

    runner = Runner(args.source, args.output)
    runner.output.mkdir(parents=True, exist_ok=True)

    results = []
    for name in selected:
        res = runner.run_case(name)
        results.append(res)
        status = "PASS" if res["ok"] else "FAIL"
        print(f"[{status}] {name}", flush=True)
        for f in res["failures"]:
            print(f"    - {f}", flush=True)

    failed = [r for r in results if not r["ok"]]
    summary = {
        "source": str(runner.source),
        "output": str(runner.output),
        "cases": results,
        "failed": len(failed),
        "total": len(results),
    }
    (runner.output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")

    if failed:
        print(f"SETTINGS_REGRESSION: FAIL ({len(failed)}/{len(results)} cases failed)")
        sys.exit(1)
    print("SETTINGS_REGRESSION: PASS")
    sys.exit(0)


if __name__ == "__main__":
    main()
