#!/usr/bin/env python3
"""Icon startup diagnostic runner (plan: post-071-settings-icons-release-notes, Phase B).

Runs INSIDE the test guest. Each run deploys a disposable copy of --source,
applies bounded ICON_DIAG instrumentation patches to guest copies of
Widgets/AtmoIcon.qml, Services/UI/IconRegistry.qml and
Services/Plugins/Service.qml (production tracked files are never modified),
launches the actual shell.qml against the live niri session with an isolated
config/cache/private D-Bus session, captures a steady-state screenshot with
grim, and correlates per-instance traces across the five plan boundaries:

  1. bar/widget input      — exact string entering each AtmoIcon
  2. plugin icon payload   — enabled sets, order, map source, timing, named entry
  3. registry -> AtmoIcon  — rebuild sequence, lookup, _resolved evaluations
  4. AtmoIcon -> rendering — resolved source, Image status, visibility
  5. final consumer        — timestamped steady-state screenshot per run

Tracked instance: KeepAwake's stable "keep-awake-off" input (seeded as the
rightmost bar widget; bar moved to the bottom so the fixture bar never
overlaps the existing guest bar). Network is the second observed widget.

Disposition per the plan's evidence gate:
  ICON_STARTUP: REPRODUCED      — a failing endpoint with correlated evidence
  ICON_STARTUP: NOT_REPRODUCED  — all runs healthy
  ICON_STARTUP: INCONCLUSIVE    — missing registration/screenshots/fixtures
"""

import argparse
import glob
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

# steady-state screenshot delay (s) / shell run length (s) / hard deadline (s)
SHOT_AT_S = 20
RUN_S = 26
DEADLINE_S = 60

RIGHT_WIDGETS = [{"id": w} for w in
                 ("Tray", "NotificationHistory", "Battery", "Volume",
                  "Brightness", "ControlCenter", "Network", "KeepAwake")]

# ------------------------------------------------------------ instrumentation
# Bounded logging applied to the DISPOSABLE GUEST COPIES only. Each patch is
# an exact-match anchored replacement; a missing or ambiguous anchor aborts
# the run as INCONCLUSIVE rather than silently running uninstrumented.

ATMOICON_HELPERS = '''  // DIAG-BEGIN (icon-startup-check; guest copies only)
  // Dependency-free one-shot id: a counter binding would re-evaluate (and
  // re-increment) on every other instance's creation, shifting ids mid-run.
  readonly property string diagId: "ai" + Math.random().toString(36).slice(2, 8)
  function diagLog(event, extra) {
    var e = extra || {};
    e.t = Date.now();
    e.id = diagId;
    e.ev = event;
    e.icon = (typeof icon === "string") ? icon : "<object>";
    console.log("ICON_DIAG|" + JSON.stringify(e));
  }
  Component.onCompleted: diagLog("create", {})
  onIconChanged: diagLog("input", {})
  // DIAG-END
  property var icon: Icon.close'''

ATMOICON_RESOLVED_OLD = '''  readonly property var _resolved: {
    if (typeof icon === "string") {
      var entry = IconRegistry.resolved[icon];
      if (entry === undefined) {
        Logger.w("AtmoIcon", "\\"" + icon + "\\" not found in icons, falling back to \\"" + Icons.defaultIcon + "\\"");
        return IconRegistry.resolved[Icons.defaultIcon];
      }
      return entry;
    }
    return icon;
  }'''

ATMOICON_RESOLVED_NEW = '''  readonly property var _resolved: {
    if (typeof icon === "string") {
      var _n = Object.keys(IconRegistry.resolved).length;
      var entry = IconRegistry.resolved[icon];
      if (entry === undefined) {
        var _fb = IconRegistry.resolved[Icons.defaultIcon];
        diagLog("eval", {"n": _n, "has": false, "fb": _fb !== undefined});
        Logger.w("AtmoIcon", "\\"" + icon + "\\" not found in icons, falling back to \\"" + Icons.defaultIcon + "\\"");
        return _fb;
      }
      diagLog("eval", {"n": _n, "has": true, "type": entry.type || "?", "src": entry.source ? entry.source.split("/").pop() : ""});
      return entry;
    }
    return icon;
  }'''

ATMOICON_IMG_OLD = '''          source: root._resolved?.source ?? ""'''
ATMOICON_IMG_NEW = '''          source: root._resolved?.source ?? ""
          onStatusChanged: root.diagLog("img", {"st": status, "src": ("" + source).split("/").pop()})'''

REGISTRY_PROPS_OLD = '''  property var resolved: ({})'''
REGISTRY_PROPS_NEW = '''  property var resolved: ({})
  // DIAG-BEGIN (icon-startup-check; guest copies only)
  property int diagRebuildSeq: 0
  // DIAG-END'''

REGISTRY_REGISTER_OLD = '''    root.iconSets[pluginId] = entry;
    root._rebuildOrder();
    root.rebuildResolved();
    Logger.i("IconRegistry", "Registered icon set:", pluginId);'''
REGISTRY_REGISTER_NEW = '''    root.iconSets[pluginId] = entry;
    root._rebuildOrder();
    root.rebuildResolved();
    console.log("ICON_DIAG|" + JSON.stringify({"ev": "register", "t": Date.now(), "plugin": pluginId, "sets": Object.keys(root.iconSets), "order": root.activeOrder, "nIcons": (manifestData && manifestData.icons) ? Object.keys(manifestData.icons).length : 0, "hasKAO": (manifestData && manifestData.icons && manifestData.icons["keep-awake-off"] !== undefined)}));
    Logger.i("IconRegistry", "Registered icon set:", pluginId);'''

REGISTRY_REBUILD_OLD = '''    root.resolved = newResolved;
    root.resolvedChanged();'''
REGISTRY_REBUILD_NEW = '''    root.resolved = newResolved;
    console.log("ICON_DIAG|" + JSON.stringify({"ev": "rebuild", "t": Date.now(), "seq": ++root.diagRebuildSeq, "n": Object.keys(newResolved).length, "order": root.activeOrder, "kao": newResolved["keep-awake-off"] !== undefined}));
    root.resolvedChanged();'''

SERVICE_PAYLOAD_OLD = '''        readProc.exited.connect(function () {
          var iconText = readProc.stdout.text;'''
SERVICE_PAYLOAD_NEW = '''        readProc.exited.connect(function () {
          var iconText = readProc.stdout.text;
          console.log("ICON_DIAG|" + JSON.stringify({"ev": "payload", "t": Date.now(), "plugin": pluginId, "path": iconsPath, "bytes": iconText.length}));'''

PATCHES = [
    ("Widgets/AtmoIcon.qml", [
        ("  property var icon: Icon.close", ATMOICON_HELPERS),
        (ATMOICON_RESOLVED_OLD, ATMOICON_RESOLVED_NEW),
        (ATMOICON_IMG_OLD, ATMOICON_IMG_NEW),
    ]),
    ("Services/UI/IconRegistry.qml", [
        (REGISTRY_PROPS_OLD, REGISTRY_PROPS_NEW),
        (REGISTRY_REGISTER_OLD, REGISTRY_REGISTER_NEW),
        (REGISTRY_REBUILD_OLD, REGISTRY_REBUILD_NEW),
    ]),
    ("Services/Plugins/Service.qml", [
        (SERVICE_PAYLOAD_OLD, SERVICE_PAYLOAD_NEW),
    ]),
]


class PatchError(Exception):
    pass


def apply_patches(shell_dir):
    for rel, subs in PATCHES:
        path = shell_dir / rel
        text = path.read_text()
        for old, new in subs:
            count = text.count(old)
            if count != 1:
                raise PatchError(f"{rel}: anchor matched {count} times (expected 1): {old[:60]!r}")
            text = text.replace(old, new)
        path.write_text(text)


# ------------------------------------------------------------------ guest env

def discover_session_env():
    socks = sorted(glob.glob("/run/user/1000/niri.*.sock"))
    if len(socks) != 1:
        raise SystemExit(f"FATAL: expected exactly one niri socket, found {len(socks)}: {socks}")
    if not os.path.exists("/run/user/1000/wayland-1"):
        raise SystemExit("FATAL: /run/user/1000/wayland-1 missing")
    for tool in ("qs", "dbus-run-session", "grim"):
        if shutil.which(tool) is None:
            raise SystemExit(f"FATAL: required tool not found on PATH: {tool}")
    return {
        "XDG_RUNTIME_DIR": "/run/user/1000",
        "WAYLAND_DISPLAY": "wayland-1",
        "NIRI_SOCKET": socks[0],
    }


def run_env(session, case_dir):
    env = dict(os.environ)
    env.update(session)
    env.update({
        "ATMOSPHERA_CONFIG_DIR": str(case_dir / "config"),
        "ATMOSPHERA_CACHE_DIR": str(case_dir / "cache"),
        "ATMOSPHERA_SETTINGS_FILE": str(case_dir / "config" / "settings.json"),
        "ATMOSPHERA_DEBUG": "0",
    })
    return env


# -------------------------------------------------------------------- run leg

def launch_run(case_dir, env):
    shell_dir = case_dir / "shell"
    log_path = case_dir / "run.log"
    inner = (
        f'( sleep {SHOT_AT_S}; grim "{case_dir}/screen.png" 2>"{case_dir}/grim.log" ) & '
        f'timeout --signal=TERM {RUN_S} qs -p "{shell_dir}/shell.qml" 2>&1; '
        f'echo "QS_EXIT=$?"'
    )
    cmd = ["dbus-run-session", "--", "sh", "-c", inner]
    proc = subprocess.Popen(cmd, env=env, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True)
    try:
        out, _ = proc.communicate(timeout=DEADLINE_S)
    except subprocess.TimeoutExpired:
        proc.terminate()
        out, _ = proc.communicate(timeout=10)
    log_path.write_text(out)
    m = re.search(r"QS_EXIT=(\d+)", out)
    return log_path, (int(m.group(1)) if m else None)


# -------------------------------------------------------------------- parsing

def parse_diag(log_path):
    events = []
    for line in Path(log_path).read_text(errors="replace").splitlines():
        i = line.find("ICON_DIAG|")
        if i < 0:
            continue
        try:
            events.append(json.loads(line[i + 10:].strip()))
        except json.JSONDecodeError:
            pass
    events.sort(key=lambda e: e.get("t", 0))
    return events


def analyze_run(events, screenshot_ok):
    """Return (status, notes) for one run.

    status: "healthy" | "reproduced" | "inconclusive"
    """
    notes = []
    payloads = [e for e in events if e.get("ev") == "payload"]
    registers = [e for e in events if e.get("ev") == "register"]
    rebuilds = [e for e in events if e.get("ev") == "rebuild"]

    if not payloads or not registers or not rebuilds:
        return "inconclusive", [f"missing pipeline events: payloads={len(payloads)} registers={len(registers)} rebuilds={len(rebuilds)}"]
    if not screenshot_ok:
        return "inconclusive", ["missing steady-state screenshot"]

    kao_rebuilds = [r for r in rebuilds if r.get("kao")]
    if not kao_rebuilds:
        return "inconclusive", ["no rebuild ever contained keep-awake-off"]
    first_kao_t = kao_rebuilds[0].get("t", 0)
    notes.append(f"registration: sets={registers[0].get('sets')} order={registers[0].get('order')} "
                 f"nIcons={registers[0].get('nIcons')} first-kao-rebuild-seq={kao_rebuilds[0].get('seq')}")

    # Tracked instances: every AtmoIcon that ever requested keep-awake-off
    by_instance = {}
    for e in events:
        if e.get("icon") == "keep-awake-off" and e.get("ev") in ("create", "input", "eval", "img"):
            by_instance.setdefault(e.get("id"), []).append(e)
    if not by_instance:
        return "inconclusive", ["no AtmoIcon instance ever requested keep-awake-off"]

    reproduced_notes = []
    for iid, evs in sorted(by_instance.items()):
        evals = [e for e in evs if e.get("ev") == "eval"]
        imgs = [e for e in evs if e.get("ev") == "img"]
        if not evals:
            reproduced_notes.append(f"{iid}: never evaluated")
            continue
        last = evals[-1]
        # Stale binding: a fallback evaluation AFTER the registry already has the entry
        stale = [e for e in evals if not e.get("has") and e.get("t", 0) > first_kao_t]
        if stale:
            reproduced_notes.append(f"{iid}: stale _resolved after registration ({len(stale)} evals)")
        if not last.get("has"):
            # Persistent fallback at steady state; visible iff the fallback entry exists
            reproduced_notes.append(f"{iid}: persistent fallback at steady state (fb={'visible' if last.get('fb') else 'hidden'})")
        else:
            bad_img = [e for e in imgs if e.get("st") not in (0, 1)]
            if bad_img:
                reproduced_notes.append(f"{iid}: image error statuses: {[e.get('st') for e in bad_img]}")
        notes.append(f"{iid}: evals={len(evals)} first_has={evals[0].get('has')} last_has={last.get('has')} "
                     f"last_n={last.get('n')} imgs={[(e.get('src'), e.get('st')) for e in imgs]}")

    if reproduced_notes:
        return "reproduced", notes + ["FAILING ENDPOINTS:"] + reproduced_notes
    return "healthy", notes


# ----------------------------------------------------------------------- main

def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--source", required=True)
    ap.add_argument("--runs", type=int, default=10)
    ap.add_argument("--output", required=True)
    args = ap.parse_args()

    source = Path(args.source)
    if not (source / "Widgets" / "AtmoIcon.qml").exists():
        raise SystemExit(f"FATAL: --source does not look like a shell tree: {source}")
    output = Path(args.output)
    output.mkdir(parents=True, exist_ok=True)
    session = discover_session_env()

    # Runtime identity record (plan B.1)
    identity = subprocess.run(["pacman", "-Q", "quickshell", "qt6-base", "qt6-declarative", "niri"],
                              capture_output=True, text=True)
    (output / "runtime-identity.txt").write_text(identity.stdout + identity.stderr)

    run_results = []
    for idx in range(1, args.runs + 1):
        name = f"run-{idx:02d}"
        case_dir = output / name
        if case_dir.exists():
            shutil.rmtree(case_dir)
        shell_dir = case_dir / "shell"
        case_dir.mkdir(parents=True)
        shutil.copytree(source, shell_dir, ignore=shutil.ignore_patterns(".git"),
                        ignore_dangling_symlinks=True)
        try:
            apply_patches(shell_dir)
        except PatchError as e:
            print(f"[INCONCLUSIVE] {name}: instrumentation anchor failure: {e}")
            run_results.append({"run": name, "status": "inconclusive", "notes": [str(e)]})
            continue
        (case_dir / "config" / "settings").mkdir(parents=True)
        (case_dir / "cache").mkdir(parents=True)
        (case_dir / "config" / "settings" / "bar.json").write_text(json.dumps({
            "position": "bottom",
            "widgets": {"right": RIGHT_WIDGETS},
        }, indent=2) + "\n")

        log_path, qs_exit = launch_run(case_dir, run_env(session, case_dir))
        events = parse_diag(log_path)
        (case_dir / "trace.json").write_text(json.dumps(events, indent=1) + "\n")
        screenshot_ok = (case_dir / "screen.png").exists() and (case_dir / "screen.png").stat().st_size > 0
        status, notes = analyze_run(events, screenshot_ok)
        if qs_exit != 124:
            notes.append(f"shell exited early: QS_EXIT={qs_exit}")
            if status == "healthy":
                status = "inconclusive"
        run_results.append({"run": name, "status": status, "notes": notes,
                            "log": str(log_path), "screenshot": str(case_dir / "screen.png")})
        print(f"[{status.upper()}] {name}")
        for n in notes:
            print(f"    {n}")

    statuses = [r["status"] for r in run_results]
    if "reproduced" in statuses:
        disposition = "REPRODUCED"
    elif all(s == "healthy" for s in statuses) and statuses:
        disposition = "NOT_REPRODUCED"
    else:
        disposition = "INCONCLUSIVE"

    summary = {"disposition": disposition, "runs": run_results}
    (output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(f"ICON_STARTUP: {disposition}")
    print(f"evidence: {output}")
    sys.exit(0 if disposition != "INCONCLUSIVE" else 2)


if __name__ == "__main__":
    main()
