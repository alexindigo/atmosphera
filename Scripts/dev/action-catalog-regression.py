#!/usr/bin/env python3
"""Guest-only regression of the action schema, commands and live plugin registry.

Run with --source SHELL_TREE --workspace FRESH_DIRECTORY in the assigned VM.
Every consumer assertion is recorded once; each private shell is PID-namespace
contained by presentation_harness. No console shell/profile is used.
"""
import argparse
import glob
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sys

import action_catalog
from presentation_harness import add_execution_arguments, check_execution_paths, run_harness
from qml_probe import inject_probe, probe_owner_path

PREFIX = "ACTION_CASE "
ERRORS = re.compile(r"Failed to load configuration|TypeError:|ReferenceError:|SyntaxError:|is not a type|is unavailable")
REGISTRY_PROBE = r'''
  property int actionProbeStep: 0
  property int actionProbeRevision: 0
  Timer {
    interval: 100
    running: true
    repeat: true
    onTriggered: {
      if (!ActionRegistry.ready || !Service.initialized || Service._pendingPluginLoads > 0) return;
      if (shellRoot.actionProbeStep === 0) {
        if (!Service.loadedPlugins["fx-actions"] || !Service.loadedPlugins["fx-bad"] || !Service.loadedPlugins["niri-windows-map"]) return;
        console.log("ACTION_CASE " + JSON.stringify({name: "registry:merge", output: ActionRegistry.actions}));
        shellRoot.actionProbeRevision = ActionRegistry.revision;
        shellRoot.actionProbeStep = 1;
        Service.disablePlugin("fx-actions");
      } else if (shellRoot.actionProbeStep === 1) {
        if (Service.loadedPlugins["fx-actions"] || ActionRegistry.revision <= shellRoot.actionProbeRevision) return;
        console.log("ACTION_CASE " + JSON.stringify({name: "registry:unload", output: {
          actions: ActionRegistry.actions, revisionBumped: ActionRegistry.revision > shellRoot.actionProbeRevision}}));
        shellRoot.actionProbeRevision = ActionRegistry.revision;
        shellRoot.actionProbeStep = 2;
        Service.disablePlugin("niri-windows-map");
      } else {
        if (Service.loadedPlugins["niri-windows-map"] || ActionRegistry.revision <= shellRoot.actionProbeRevision) return;
        console.log("ACTION_CASE " + JSON.stringify({name: "registry:required-unload", output: ActionRegistry.actions}));
        console.log("ACTION_DONE");
        stop();
        Qt.quit();
      }
    }
  }
'''


def private_env(work):
    env = dict(os.environ, QT_QPA_PLATFORM="wayland", QT_QUICK_BACKEND="software",
               XDG_RUNTIME_DIR="/run/user/1000", WAYLAND_DISPLAY="wayland-1",
               ATMOSPHERA_DEBUG="0", ATMOSPHERA_UPGRADELOG_URL="http://127.0.0.1:9")
    for key, leaf in (("HOME", "home"), ("XDG_CONFIG_HOME", "config"),
                      ("XDG_DATA_HOME", "data"), ("XDG_CACHE_HOME", "cache"), ("XDG_STATE_HOME", "state")):
        (work / leaf).mkdir()
        env[key] = str(work / leaf)
    config = work / "config/atmosphera"
    config.mkdir()
    env["ATMOSPHERA_CONFIG_DIR"] = str(config) + "/"
    env["ATMOSPHERA_SETTINGS_FILE"] = str(config / "settings.json")
    return env, config


def parse(log):
    return [json.loads(line.split(PREFIX, 1)[1]) for line in log.splitlines() if PREFIX in line]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--workspace", required=True, type=Path)
    add_execution_arguments(parser)
    args = parser.parse_args()
    source, work = args.source.resolve(), args.workspace.resolve()
    check_execution_paths(parser, work, source=source)
    if Path.home() != Path("/home/tester") or not Path("/run/user/1000/wayland-1").exists():
        parser.error("run only inside the assigned Wayland test VM")
    work.mkdir(parents=True)
    rows, executions, failures = [], {}, []

    def check(name, output, expected):
        ok = output == expected
        rows.append(dict(name=name, output=output, expected=expected, passed=ok))
        if not ok:
            failures.append(name)
        print(f"[{'PASS' if ok else 'FAIL'}] {name}", flush=True)

    check("core:source-contract", action_catalog.check_core(source), [])
    catalog = action_catalog.read_core(source)
    tab = next(a for a in catalog if a["id"] == "settings-tab")
    ipc = (source / "Services/Control/IPCService.qml").read_text()
    tab_map = re.search(r"_settingsTabMap\s*:\s*\(?\s*\{(.*?)\}", ipc, re.S).group(1)
    accepted = re.findall(r"[\"']?([a-z]+)[\"']?\s*:", tab_map)
    check("core:tabs", sorted(c["value"] for c in tab["arguments"][0]["choices"]), sorted(set(accepted) - {"systemmonitor"}))
    schema = json.loads((source / "Scripts/dev/fixtures/action-schema-cases.json").read_text())
    expected = {}
    for case in schema["cases"]:
        action = case["action"] if "action" in case else {**schema["base"], **case["patch"]}
        check("python:schema:" + case["name"], action_catalog.validate_action(action, case["origin"])["valid"], case["valid"])
        expected["schema:" + case["name"]] = case["valid"]
    expected.update({
        "tab": {"command": "atmosphera ipc settings openTab plugins", "values": {"tab": "plugins"}, "label": "Open settings tab: Plugins"},
        "number": {"command": "atmosphera ipc idleInhibitor enableFor 1200", "values": {"seconds": 1200}, "label": "Keep awake for: 1200 seconds"},
        "safe-edits": ["atmosphera ipc plugin:example number 900", "atmosphera ipc plugin:example number 9007199254740991", "", ""],
        "space": {"command": "atmosphera ipc plugin:example show 'hello world'", "values": {"message": "hello world"}, "label": "Message: hello world"},
        "apostrophe": {"command": "atmosphera ipc plugin:example show 'it'\\''s here'", "values": {"message": "it's here"}, "label": "Message: it's here"},
        "availability": [True, False, True, False],
        **{f"reject:{i}": True for i in range(5)}})

    unit = work / "unit"
    unit.mkdir()
    env, _ = private_env(unit)
    runtime = unit / "shell"
    for rel in ("Services/Actions/ActionCommand.js", "Scripts/dev/fixtures/action-catalog.qml"):
        target = runtime / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source / rel, target)
    (runtime / "shell.qml").write_text('import QtQuick\nItem { Loader { source: "Scripts/dev/fixtures/action-catalog.qml" } }\n')
    env.update(ACTION_SCHEMA=str(source / "Scripts/dev/fixtures/action-schema-cases.json"),
               ACTION_CORE=str(source / "Assets/Actions/core.json"))
    execution = run_harness(["dbus-run-session", "--", "qs", "-p", runtime, "--no-color"], unit, env, min(args.budget, 45))
    executions["unit"] = execution
    log = (unit / "shell.log").read_text(errors="replace")
    cases = parse(log)
    for name, want in expected.items():
        outputs = [row["output"] for row in cases if row["name"] == name]
        check("js:" + name, outputs, [want])
    check("unit:unexpected", sorted(set(row["name"] for row in cases) - set(expected)), [])
    check("unit:completed", "ACTION_DONE" in log and execution["exit_code"] == 0 and execution["cleanup_complete"] and not ERRORS.search(log), True)

    full = work / "registry"
    full.mkdir()
    env, config = private_env(full)
    sockets = glob.glob("/run/user/1000/niri.*.sock")
    if len(sockets) != 1:
        parser.error("expected exactly one niri socket in the assigned VM")
    env["NIRI_SOCKET"] = sockets[0]
    runtime = full / "shell"
    shutil.copytree(source, runtime, ignore=shutil.ignore_patterns(".git", ".envrc", "__pycache__", "*.bak"))
    defaults = json.loads((runtime / "Configs/defaults.json").read_text())
    (config / "settings.json").write_text(json.dumps(defaults))
    shutil.copytree(source / "Scripts/dev/fixtures/action-catalog", config / "plugins")
    shutil.copytree(source / "builtin/plugins/atmosphera-icons", config / "plugins/atmosphera-icons")
    states = {name: {"enabled": name != "fx-off"} for name in ("fx-actions", "fx-bad", "fx-off", "niri-windows-map", "atmosphera-icons")}
    (config / "plugins.json").write_text(json.dumps({"version": 5, "sources": [], "states": states}))
    owner = probe_owner_path(runtime)
    owner.write_text(inject_probe("import qs.Services.Actions\n" + owner.read_text(), REGISTRY_PROBE))
    execution = run_harness(["dbus-run-session", "--", "qs", "-p", runtime, "--no-color"], full, env, min(args.budget, 150))
    executions["registry"] = execution
    log = (full / "shell.log").read_text(errors="replace")
    cases = parse(log)
    wanted = {"registry:merge", "registry:unload", "registry:required-unload"}
    for name in wanted:
        check(name + ":count", sum(row["name"] == name for row in cases), 1)
    check("registry:unexpected", sorted(set(row["name"] for row in cases) - wanted), [])
    observed = {row["name"]: row["output"] for row in cases}
    merged = observed.get("registry:merge", [])
    lookup = {row["key"]: row for row in merged}
    check("registry:core-rows", [row["key"] for row in merged if row["section"] == "Atmosphera"],
          ["core/" + action["id"] for action in catalog if "group" in action])
    check("registry:plugin-groups", [(row["key"], row["group"]) for row in merged if row["section"] == "Plugins"],
          [("fx-actions/show", "Fixture Actions"), ("fx-bad/show", "Mixed Fixture"), ("core/windows-map", "Niri Windows Map")])
    check("registry:overview", lookup.get("core/overview", {}).get("group"), "Compositor")
    check("registry:invalid-warning", "ActionRegistry" in log and "fx-bad: unknown action key" in log, True)
    unload = observed.get("registry:unload", {})
    check("registry:revision", unload.get("revisionBumped"), True)
    check("registry:removed", [row["key"] for row in unload.get("actions", [])], [row["key"] for row in merged if not row["key"].startswith("fx-actions/")])
    check("registry:required-removed", [row["key"] for row in observed.get("registry:required-unload", [])],
          [row["key"] for row in merged if not row["key"].startswith("fx-actions/") and row["key"] != "core/windows-map"])
    check("registry:completed", "ACTION_DONE" in log and execution["exit_code"] == 0 and execution["cleanup_complete"] and not ERRORS.search(log), True)
    check("registry:core-errors", bool(re.search(r"ERROR\s+qml:.*ActionRegistry", log)), False)
    hashes = {str(p.relative_to(source)): hashlib.sha256(p.read_bytes()).hexdigest()
              for p in [source / "Assets/Actions/core.json", *sorted((source / "Services/Actions").glob("*"))]}
    receipt = dict(passed=not failures, failures=failures, cases=rows, source_sha256=hashes, execution=executions)
    (work / "result.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(json.dumps({"passed": receipt["passed"], "failures": failures, "cases": len(rows)}))
    return int(bool(failures))


if __name__ == "__main__":
    sys.exit(main())
