#!/usr/bin/env python3
"""Plugin registry reactivity regression (M09). Guest only.

A disposable copy of --source runs Scripts/dev/fixtures/plugin-registry-reactivity.qml
as its qs entry in a niri session. The fixture binds each registry's public lookup
for the test id "plugin:test:x" and drives the real register/unregister functions
through four phases: cold, registered, unregistered, registered again.

Asserted, per phase, against the lookup the registry reports directly:
  * every registry binding equals its direct lookup (a mismatch there means the
    register/unregister call itself is wrong, reported as direct_mismatch);
  * every registry binding is false in cold and unregistered, true in registered
    and registered-again. A binding that stays on its earlier value is the
    reactivity bug (in-place map changes that QML bindings cannot observe).
Bar loader (the real BarWidgetLoader for the same id), phases registered and
registered-again: not unavailable, and the real widget is loaded.
Control-center loader (the real ControlCenterWidgetLoader for the same id),
after the four phases: the widget loads when test:x registers; registering and
unregistering an unrelated id (test:other) leaves that same widget instance
loaded (no reload, no second creation); unregistering test:x unloads it; and
registering it again loads a new instance.
The widget component file is generated here, into the runtime copy only.

Writes result.json and the qs log into --output (must not exist). Everything
the shell writes (config, cache, the copied shell tree) stays under
<ROOT>/runtime/<output name>, never in evidence.

Exit: 0 all pass; 1 at least one assertion failed (red); 2 the probe did not
complete (no rows for every phase, timeout, or crash), so nothing is judged.
"""

import argparse
import glob
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
PROBE_SRC = SCRIPT_DIR / "fixtures" / "plugin-registry-reactivity.qml"
PROBE_NAME = "plugin-registry-reactivity-probe.qml"
WIDGET_NAME = "plugin-registry-reactivity-widget.qml"
ROOT = Path("/home/tester/Projects/qt612-atmocolor/081-integrity")
WATCHDOG = 90
PREFIX = "PLUGIN_REGISTRY_REACTIVITY|"
PHASES = ["cold", "registered", "unregistered", "registered-again"]
EXPECTED = {"cold": False, "registered": True, "unregistered": False, "registered-again": True}
REGISTRIES = ["bar", "control-center", "desktop", "launcher", "icon"]
LOADER_CHECK_PHASES = ["registered", "registered-again"]
# Control-center loader steps (fixture phase "cc-loader"). sameAsRecorded is
# true only when the loaded item is the very instance recorded at "record".
CC_STEPS = {
    "record": {"loaded": True},
    "other-registered": {"loaded": True, "sameAsRecorded": True},
    "other-unregistered": {"loaded": True, "sameAsRecorded": True},
    "test-unregistered": {"loaded": False},
    "test-reregistered": {"loaded": True, "sameAsRecorded": False},
}
ERRORS = re.compile(r"TypeError|ReferenceError|Cannot assign to non-existent property|Binding loop detected")

# Generated into the runtime copy only; never committed. It declares the
# standard bar widget properties BarWidgetLoader passes at load time.
WIDGET_SRC = """import QtQuick

Item {
  property var pluginApi: null
  property var screen: null
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: 0
  property int sectionWidgetsCount: 0
  objectName: "m09-real-widget"
  implicitWidth: 24
  implicitHeight: 24
}
"""


class Blocked(Exception):
    pass


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def guest_checks():
    for tool in ("qs", "dbus-run-session", "niri", "timeout"):
        if shutil.which(tool) is None:
            raise Blocked(f"missing tool: {tool}")
    if Path.home() != Path("/home/tester") or os.getuid() != 1000:
        raise Blocked("guest identity: expected uid 1000 with HOME /home/tester")
    socks = sorted(glob.glob("/run/user/1000/niri.*.sock"))
    if len(socks) != 1:
        raise Blocked(f"expected exactly one niri socket, found {socks}")
    if not Path("/run/user/1000/wayland-1").exists():
        raise Blocked("wayland-1 socket missing")
    return socks[0]


def qs_env(config_dir, niri_sock):
    return dict(
        os.environ,
        XDG_RUNTIME_DIR="/run/user/1000",
        WAYLAND_DISPLAY="wayland-1",
        NIRI_SOCKET=niri_sock,
        QT_FORCE_STDERR_LOGGING="1",
        ATMOSPHERA_CONFIG_DIR=str(config_dir / "config") + "/",
        ATMOSPHERA_CACHE_DIR=str(config_dir / "cache") + "/",
        ATMOSPHERA_SETTINGS_FILE=str(config_dir / "config" / "settings.json"),
        ATMOSPHERA_DEBUG="0",
        ATMOSPHERA_UPGRADELOG_URL="http://127.0.0.1:9",
    )


def parse_rows(log):
    rows = []
    for line in log.splitlines():
        i = line.find(PREFIX)
        if i >= 0:
            rows.append(json.loads(line[i + len(PREFIX):]))
    return rows


def judge(rows, failures):
    """Return per-registry and loader verdicts, appending failure strings."""
    by_phase = {}
    for row in rows:
        by_phase.setdefault(row.get("phase"), {}).setdefault(row.get("registry"), row)
    for phase in PHASES:
        if phase not in by_phase:
            raise Blocked(f"no rows for phase {phase}")
    verdict = {}
    for reg in REGISTRIES:
        phases = {}
        reasons = []
        for phase in PHASES:
            row = by_phase[phase].get(reg)
            if row is None:
                raise Blocked(f"no {reg} row for phase {phase}")
            phases[phase] = {"binding": row["binding"], "direct": row["direct"]}
            if row["direct"] != EXPECTED[phase]:
                reasons.append(f"{phase}: direct lookup is {row['direct']}, expected {EXPECTED[phase]} (register/unregister call wrong)")
            elif row["binding"] != EXPECTED[phase]:
                reasons.append(f"{phase}: binding is {row['binding']}, expected {EXPECTED[phase]} (stale binding)")
        verdict[reg] = {"pass": not reasons, "phases": phases, "failures": reasons}
        failures.extend(f"{reg} {r}" for r in reasons)
    loader = {}
    loader_reasons = []
    for phase in PHASES:
        row = by_phase[phase].get("bar-loader")
        if row is None:
            raise Blocked(f"no bar-loader row for phase {phase}")
        loader[phase] = {"unavailable": row["unavailable"], "realWidget": row["realWidget"]}
        if phase in LOADER_CHECK_PHASES:
            if row["unavailable"] is not False:
                loader_reasons.append(f"{phase}: unavailable is {row['unavailable']}, expected False (placeholder stuck)")
            if row["realWidget"] is not True:
                loader_reasons.append(f"{phase}: realWidget is {row['realWidget']}, expected True")
    verdict["bar-loader"] = {"pass": not loader_reasons, "phases": loader, "failures": loader_reasons}
    failures.extend(f"bar-loader {r}" for r in loader_reasons)
    return verdict


def judge_cc(rows, failures):
    """Judge the control-center loader steps; return the verdict, appending failures."""
    steps = {}
    for row in rows:
        if row.get("phase") == "cc-loader":
            steps.setdefault(row.get("step"), row)
    reasons = []
    verdict = {}
    for step, expected in CC_STEPS.items():
        row = steps.get(step)
        if row is None:
            raise Blocked(f"no cc-loader row for step {step}")
        verdict[step] = {key: row.get(key) for key in expected}
        for key, want in expected.items():
            if row.get(key) != want:
                reasons.append(f"{step}: {key} is {row.get(key)}, expected {want}")
    failures.extend(f"control-center-loader {r}" for r in reasons)
    return {"pass": not reasons, "steps": verdict, "failures": reasons}


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--source", required=True, type=Path, help="shell tree to copy (guest path)")
    p.add_argument("--output", required=True, type=Path, help="new evidence directory (must not exist)")
    a = p.parse_args()
    source = a.source.resolve()
    output = a.output.resolve()
    runtime = ROOT / "runtime" / output.name
    shell_dir = runtime / "shell"
    profile = runtime / "profile"
    if output.exists():
        print(f"output exists: {output}", file=sys.stderr)
        return 2
    if runtime.exists():
        print(f"runtime exists: {runtime}", file=sys.stderr)
        return 2
    try:
        niri_sock = guest_checks()
    except Blocked as exc:
        print(f"BLOCKED: {exc}", file=sys.stderr)
        return 2

    output.mkdir(parents=True)
    (profile / "config").mkdir(parents=True)
    (profile / "cache").mkdir()
    shutil.copytree(source, shell_dir, ignore=shutil.ignore_patterns(".git"), symlinks=True, ignore_dangling_symlinks=True)
    probe = shell_dir / PROBE_NAME
    shutil.copyfile(PROBE_SRC, probe)
    (shell_dir / WIDGET_NAME).write_text(WIDGET_SRC)
    settings = json.loads((source / "Configs/defaults.json").read_text())
    settings["general"]["showChangelogOnStartup"] = False
    (profile / "config/settings.json").write_text(json.dumps(settings))

    failures = []
    hashes = {
        "fixture_source": sha256(PROBE_SRC),
        "fixture_copy": sha256(probe),
        "widget_generated_sha256": hashlib.sha256(WIDGET_SRC.encode()).hexdigest(),
    }
    if hashes["fixture_source"] != hashes["fixture_copy"]:
        failures.append("copied fixture differs from source")

    proc = subprocess.run(
        ["timeout", "--kill-after=5s", f"{WATCHDOG}s", "dbus-run-session", "--", "qs", "-p", str(probe)],
        cwd=shell_dir, env=qs_env(profile, niri_sock), capture_output=True, text=True, timeout=WATCHDOG + 30)
    log = proc.stdout + proc.stderr
    (output / "run.log").write_text(log)

    rows = parse_rows(log)
    result = {
        "exit": proc.returncode,
        "source": str(source),
        "runtime": str(shell_dir),
        "hashes": hashes,
        "rows": rows,
    }
    error_lines = [line for line in log.splitlines() if ERRORS.search(line)]
    result["error_lines"] = error_lines[:50]
    if error_lines:
        failures.append(f"{len(error_lines)} TypeError/ReferenceError/non-existent-property line(s) in the run log")

    if proc.returncode != 0:
        result.update(status="blocked", reason=f"probe exit {proc.returncode}")
        (output / "result.json").write_text(json.dumps(result, indent=2) + "\n")
        print(json.dumps(result, indent=2))
        return 2
    try:
        verdict = judge(rows, failures)
        verdict["control-center-loader"] = judge_cc(rows, failures)
    except Blocked as exc:
        result.update(status="blocked", reason=str(exc))
        (output / "result.json").write_text(json.dumps(result, indent=2) + "\n")
        print(json.dumps(result, indent=2))
        return 2

    result["registries"] = verdict
    result["failures"] = failures
    result["status"] = "green" if not failures else "red"
    (output / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))
    return 0 if not failures else 1


if __name__ == "__main__":
    sys.exit(main())
