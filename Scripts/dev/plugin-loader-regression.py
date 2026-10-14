#!/usr/bin/env python3
"""Shared plugin loader regression runner (shared-loader design, L03).

--case core (guest only, fresh --output directory):
  A disposable copy of --source runs Scripts/dev/fixtures/plugin-loader-core.qml
  as its qs entry. That probe loads three fixture panel entry files through
  PluginView with context {screen: <first ShellScreen>} and one broken entry
  file (generated here, never committed, so no .qml syntax error reaches the
  pre-commit hook). Asserted:
    * fx-declares declares `screen`: it sees screen in `completed`;
    * fx-inherits inherits `screen` from a local base: it gets it via
      `changed:screen` (late assignment), exactly one `completed` line;
    * fx-bare declares no screen: no `screen` in any FX line, no warning;
    * the broken entry shows the placeholder and records one plugin error;
    * creation/missing-source failures in PluginView and createObject record
      exactly once, preserve Qt's error text where exposed, and unload cleanly;
    * no `Cannot assign to non-existent property` / TypeError / ReferenceError
      anywhere in the log outside the broken fixture's own lines.

--case sites (guest only, fresh --output directory):
  A disposable copy of --source gets the fixture plugins from this script's
  own tree (Scripts/dev/fixtures/plugin-loader/plugins, placements.json next to
  it), preinstalled and enabled in a private profile, then runs the real shell
  (shell.qml). Placements: bar right section, control-center left shortcuts,
  desktop widgets on the first niri output. The control center is opened over
  IPC, then closed. Asserted:
    * every completed line of fx-declares has its contract names non-null;
    * fx-declares sees the screen name; fx-bare receives no contract name;
    * fx-inherits gets `screen` via `changed:screen`;
    * the last fixture context matches its placement's section/index/count
      and screen, including values that changed during asynchronous creation;
    * every placed fixture reaches `completed` on every surface it is placed on;
    * panels (fx-declares, fx-bare, fx-inherits) and settings pages (fx-declares,
      fx-bare) are opened over IPC and reach `completed`; the Main and launcher
      fixtures (fx-declares, fx-bare) log `completed` at startup;
    * no `Cannot assign to non-existent property` line anywhere in the log
      (Qt names the delivering file, not the plugin: DesktopWidgets.qml or
      <Unknown File>), and no other ERRORS line that names a fixture
      (fx-declares / fx-bare / fx-inherits).
    * a generated creation-failure fixture records exactly one useful error at
      each placed site; no TypeError/ReferenceError from the shell's own files.
    Other ERRORS lines are reported in sites.json (other_error_lines), not failed.
"""

import argparse
import glob
import hashlib
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
PROBE_SRC = SCRIPT_DIR / "fixtures" / "plugin-loader-core.qml"
PROBE_NAME = "plugin-loader-core-probe.qml"
FIXTURE_DIR = "Scripts/dev/fixtures/plugin-loader"
ROOT = Path("/home/tester/Projects/qt612-atmocolor/081-integrity")
PANELS = ["fx-declares", "fx-bare", "fx-inherits", "fx-broken"]
ERRORS = re.compile(r"Cannot assign to non-existent property|TypeError|ReferenceError|"
                    r"is not a function|Component is not ready|Binding loop detected")
NON_EXISTENT = re.compile(r"Cannot assign to non-existent property")

# --case sites: fixture plugins from Scripts/dev/fixtures/plugin-loader/plugins
# (registry.json + fx-* directories), placed by placements.json.
SITE_FIXTURES = ["fx-declares", "fx-bare", "fx-inherits"]
FIXTURE_TOKEN = re.compile(r"fx-(declares|bare|inherits)")
SITES_WATCHDOG = 600
PLUGINS_JSON_VERSION = 4  # Registry.qml currentVersion
# Surface (entry point of the FX lines) -> fixtures that must reach `completed` on it.
# Placed surfaces (bar, control center, desktop) are driven by placements.json; the
# others are opened over IPC (panel, settings) or started with the shell (main,
# launcherProvider).
SURFACES = {
    "barWidget": ["fx-declares", "fx-bare", "fx-inherits"],
    "controlCenterWidget": ["fx-declares", "fx-bare"],
    "desktopWidget": ["fx-declares", "fx-bare", "fx-inherits"],
    "panel": ["fx-declares", "fx-bare", "fx-inherits"],
    "settings": ["fx-declares", "fx-bare"],
    "main": ["fx-declares", "fx-bare"],
    "launcherProvider": ["fx-declares", "fx-bare"],
}
# Context names fx-declares declares and must see non-null in every completed line.
# Entries not listed here receive no contract names.
SURFACE_CONTEXT = {
    "barWidget": ["screen", "widgetId", "section", "sectionWidgetIndex", "sectionWidgetsCount"],
    "controlCenterWidget": ["screen", "widgetId", "section", "sectionWidgetIndex", "sectionWidgetsCount", "widgetSettings"],
    "desktopWidget": ["screen", "widgetData", "widgetIndex"],
    "panel": ["screen"],
}
CONTRACT_NAMES = ["screen", "widgetId", "section", "sectionWidgetIndex", "sectionWidgetsCount",
                  "widgetSettings", "widgetData", "widgetIndex"]

# Deliberate syntax error (unclosed parameter list). Written only into the
# disposable copy.
BROKEN_PANEL = """import QtQuick

Item {
  property var pluginApi: null
  property var screen: null

  function broken( {
  }
}
"""

# Compiles successfully, but Qt cannot create an item without this required
# property. Generated only in the disposable copy, never in the fixture tree.
CREATION_FAILURE = """import QtQuick
Item {
  property var pluginApi: null
  required property bool charged
}
"""
FAILURE_FIXTURE = "fx-creation-failure"
FAILURE_SITES = ["barWidget", "controlCenterWidget", "desktopWidget"]


class Blocked(Exception):
    pass


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def parse_prefixed(log, prefix):
    for line in log.splitlines():
        i = line.find(prefix)
        if i >= 0:
            return line[i + len(prefix):].strip()
    return None


def parse_fx(log):
    rows = []
    for line in log.splitlines():
        i = line.find("FX {")
        if i >= 0:
            try:
                rows.append(json.loads(line[i + 3:]))
            except json.JSONDecodeError:
                pass
    return rows


def guest_checks():
    for tool in ("qs", "dbus-run-session", "niri"):
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


def qs_env(case_dir, niri_sock):
    env = dict(os.environ)
    env.update({
        "XDG_RUNTIME_DIR": "/run/user/1000",
        "WAYLAND_DISPLAY": "wayland-1",
        "NIRI_SOCKET": niri_sock,
        "ATMOSPHERA_CONFIG_DIR": str(case_dir / "config") + "/",
        "ATMOSPHERA_CACHE_DIR": str(case_dir / "cache") + "/",
        "ATMOSPHERA_SETTINGS_FILE": str(case_dir / "config" / "settings.json"),
        "ATMOSPHERA_DEBUG": "0",
        "QT_FORCE_STDERR_LOGGING": "1",
        "ATMOSPHERA_UPGRADELOG_URL": "http://127.0.0.1:9",
    })
    return env


def case_core(source, output, runtime, failures):
    niri_sock = guest_checks()

    case_dir = output / "core"
    case_dir.mkdir()
    profile_dir = runtime / "core"
    shell_dir = profile_dir / "shell"
    shutil.copytree(source, shell_dir, ignore=shutil.ignore_patterns(".git"), ignore_dangling_symlinks=True)
    shutil.copy(PROBE_SRC, shell_dir / PROBE_NAME)
    broken = shell_dir / FIXTURE_DIR / "fx-broken" / "Panel.qml"
    broken.parent.mkdir(parents=True)
    broken.write_text(BROKEN_PANEL)
    creation = shell_dir / FIXTURE_DIR / "fx-creation-failure" / "Panel.qml"
    creation.parent.mkdir(parents=True)
    creation.write_text(CREATION_FAILURE)
    (profile_dir / "config").mkdir(parents=True)
    (profile_dir / "cache").mkdir(parents=True)

    hashes = {}
    for name in PANELS[:3]:
        rel = f"{FIXTURE_DIR}/{name}/Panel.qml"
        hashes[rel] = {"source": sha256(source / rel), "copy": sha256(shell_dir / rel)}
        if hashes[rel]["source"] != hashes[rel]["copy"]:
            failures.append(f"copied fixture differs from source: {rel}")
    hashes["broken"] = sha256(broken)

    env = qs_env(profile_dir, niri_sock)
    proc = subprocess.run(
        ["timeout", "--kill-after=5s", "90", "dbus-run-session", "--", "qs", "-p", str(shell_dir / PROBE_NAME)],
        env=env, capture_output=True, text=True, timeout=110)
    log = proc.stdout + proc.stderr
    (case_dir / "run.log").write_text(log)
    if proc.returncode != 0:
        failures.append(f"probe exit {proc.returncode}")

    done = parse_prefixed(log, "PLUGIN_LOADER|DONE|")
    if done != "settled":
        failures.append(f"probe did not settle: {done}")
    screen = parse_prefixed(log, "PLUGIN_LOADER|SCREEN|")
    screen = json.loads(screen) if screen is not None else None
    if not screen:
        failures.append(f"no ShellScreen available to the probe: {screen}")
    views_raw = parse_prefixed(log, "PLUGIN_LOADER|VIEWS|")
    errors_raw = parse_prefixed(log, "PLUGIN_LOADER|ERRORS|")
    views = {row["key"]: row for row in json.loads(views_raw)} if views_raw else {}
    errors = json.loads(errors_raw) if errors_raw else None

    want = {
        "fx-declares": {"loaded": True, "failed": False, "screen": screen, "pluginApi": True, "placeholder": False},
        "fx-bare": {"loaded": True, "failed": False, "screen": None, "pluginApi": True, "placeholder": False},
        "fx-inherits": {"loaded": True, "failed": False, "screen": screen, "pluginApi": True, "placeholder": False},
        "fx-broken": {"loaded": False, "failed": True, "placeholder": True},
    }
    for key, expect in want.items():
        row = views.get(key)
        if row is None:
            failures.append(f"{key}: no view row in probe output")
            continue
        for field, value in expect.items():
            if row.get(field) != value:
                failures.append(f"{key}: {field} is {row.get(field)!r}, expected {value!r}")

    if errors != [["fx-broken", "panel"]]:
        failures.append(f"recorded plugin errors are {errors}, expected exactly [['fx-broken', 'panel']]")

    matrix_raw = parse_prefixed(log, "PLUGIN_LOADER|FAILURES|")
    matrix = json.loads(matrix_raw) if matrix_raw else {}
    for field in ("creationFailed", "missingFailed", "cleared"):
        if matrix.get(field) is not True:
            failures.append(f"failure matrix: {field} is not true: {matrix}")
    if matrix.get("direct") != {"creation": True, "compile": True, "missing": True}:
        failures.append(f"failure matrix: direct creation results are {matrix.get('direct')}")
    expected_errors = {
        "s3-view-create": ("panel", "Failed to instantiate "),
        "s3-view-missing": ("panel", "No such file"),
        "s3-view-cleared": ("panel", "Failed to instantiate "),
        "s3-direct-create": ("main", "Required property charged"),
        "s3-direct-compile": ("main", "Expected token"),
        "s3-direct-null": ("main", "no source"),
        "s3-empty-report": ("panel", "no source"),
    }
    for key, (entry, text) in expected_errors.items():
        error = matrix.get("errors", {}).get(key, {})
        if error.get("entryPoint") != entry or text not in error.get("error", ""):
            failures.append(f"{key}: missing expected {entry}/{text!r} record: {error}")
        count = sum("Plugin load error [" + key + "/" + entry + "]:" in line for line in log.splitlines())
        if count != 1:
            failures.append(f"{key}: expected exactly one recorded failure, got {count}")

    fx = parse_fx(log)
    by_id = {}
    for row in fx:
        by_id.setdefault(row.get("id"), []).append(row)
    for name in ("fx-declares", "fx-bare", "fx-inherits"):
        completed = [r for r in by_id.get(name, []) if r.get("phase") == "completed"]
        if len(completed) != 1:
            failures.append(f"{name}: expected exactly one completed line, got {len(completed)}")
    declared = [r for r in by_id.get("fx-declares", []) if r.get("phase") == "completed"]
    if declared and declared[0].get("ctx", {}).get("screen") != screen:
        failures.append(f"fx-declares did not see screen in completed: {declared[0].get('ctx')}")
    inherits = [r for r in by_id.get("fx-inherits", []) if r.get("phase") == "changed:screen"]
    if not inherits or inherits[-1].get("ctx", {}).get("screen") != screen:
        failures.append(f"fx-inherits did not get screen via changed:screen: {inherits}")
    for row in by_id.get("fx-bare", []):
        if "screen" in row.get("ctx", {}):
            failures.append(f"fx-bare received a screen value it does not declare: {row}")

    bad = []
    for line in log.splitlines():
        if ERRORS.search(line) and "fx-broken" not in line:
            bad.append(line)
    if bad:
        failures.append(f"error lines outside the broken fixture: {bad[:5]}")

    (case_dir / "views.json").write_text(json.dumps(
        {"screen": screen, "views": views, "errors": errors, "fx": fx, "failure_matrix": matrix}, indent=2) + "\n")
    (case_dir / "hashes.json").write_text(json.dumps(hashes, indent=2) + "\n")
    return {"probe_exit": proc.returncode, "done": done, "errors": errors}


def plugin_key(source_url, pid):
    # Services/Plugins/Registry.qml generateCompositeKey: first 6 hex of sha256(sourceUrl) + ':' + id
    return hashlib.sha256(source_url.encode()).hexdigest()[:6] + ":" + pid


def deep_merge(base, patch):
    if isinstance(base, dict) and isinstance(patch, dict):
        out = dict(base)
        for k, v in patch.items():
            out[k] = deep_merge(base[k], v) if k in base else v
        return out
    return patch


def niri_output_names(niri_sock):
    env = dict(os.environ, NIRI_SOCKET=niri_sock, XDG_RUNTIME_DIR="/run/user/1000")
    proc = subprocess.run(["niri", "msg", "--json", "outputs"], env=env, capture_output=True, text=True, timeout=30)
    if proc.returncode != 0:
        raise Blocked(f"niri msg outputs failed: {proc.stderr.strip()}")
    return sorted(json.loads(proc.stdout))


def fx_completed(log, entry, names):
    rows = parse_fx(log)
    return all(any(r.get("id") == n and r.get("entry") == entry and r.get("phase") == "completed" for r in rows)
               for n in names)


def case_sites(source, output, runtime, failures):
    niri_sock = guest_checks()
    fixtures = SCRIPT_DIR / "fixtures" / "plugin-loader"
    case_dir = output / "sites"
    case_dir.mkdir()
    profile_dir = runtime / "sites"
    shell_dir = profile_dir / "shell"
    shutil.copytree(source, shell_dir, ignore=shutil.ignore_patterns(".git"), ignore_dangling_symlinks=True)
    plugins_src = shell_dir / FIXTURE_DIR / "plugins"
    shutil.copytree(fixtures / "plugins", plugins_src, dirs_exist_ok=True)
    failure_dir = plugins_src / FAILURE_FIXTURE
    failure_dir.mkdir()
    manifest = json.loads((plugins_src / "fx-bare" / "manifest.json").read_text())
    manifest.update(id=FAILURE_FIXTURE, name="FX Creation Failure",
                    entryPoints={site: site + ".qml" for site in FAILURE_SITES})
    (failure_dir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    for filename in manifest["entryPoints"].values():
        (failure_dir / filename).write_text(CREATION_FAILURE)
    shell_qml = shell_dir / "shell.qml"
    if not shell_qml.is_file() or not (shell_dir / "Configs" / "defaults.json").is_file():
        raise Blocked(f"not a shell source: {source}")
    (profile_dir / "config").mkdir(parents=True)
    (profile_dir / "cache").mkdir(parents=True)

    hashes = {}
    for src in sorted((fixtures / "plugins").rglob("*")):
        if src.is_file():
            rel = src.relative_to(fixtures / "plugins").as_posix()
            hashes[rel] = {"source": sha256(src), "copy": sha256(plugins_src / rel)}
            if hashes[rel]["source"] != hashes[rel]["copy"]:
                failures.append(f"copied fixture differs from source: {rel}")

    registry_path = plugins_src / "registry.json"
    registry = json.loads(registry_path.read_text())
    registry["plugins"].append(manifest)
    registry_path.write_text(json.dumps(registry, indent=2) + "\n")

    url = "file://" + str(plugins_src.resolve())
    keys = {pid: plugin_key(url, pid) for pid in SITE_FIXTURES + [FAILURE_FIXTURE]}
    config = profile_dir / "config"
    states = {}
    for pid in SITE_FIXTURES + [FAILURE_FIXTURE]:
        shutil.copytree(plugins_src / pid, config / "plugins" / keys[pid])
        states[keys[pid]] = {"enabled": True, "sourceUrl": url}
    (config / "plugins.json").write_text(json.dumps({
        "version": PLUGINS_JSON_VERSION,
        "sources": [{"name": "Test", "url": url, "enabled": True}],
        "states": states,
    }, indent=2) + "\n")

    outputs = niri_output_names(niri_sock)
    if not outputs:
        raise Blocked("niri reports no outputs")
    screen = outputs[0]

    placements_text = re.sub(r"@KEY:([A-Za-z0-9._-]+)@", lambda m: keys[m.group(1)],
                             (fixtures / "placements.json").read_text())
    placements = json.loads(placements_text)
    failure_widget = {"id": "plugin:" + keys[FAILURE_FIXTURE]}
    # Keep the creation-failure probe in separate sections so it does not alter
    # the real fixtures' section counts from placements.json.
    placements["bar"]["widgets"].setdefault("center", []).append(dict(failure_widget))
    placements["controlCenter"]["shortcuts"].setdefault("right", []).append(dict(failure_widget))
    for monitor in placements["desktopWidgets"]["monitorWidgets"]:
        monitor["name"] = screen
        monitor["widgets"].append(dict(failure_widget, x=700, y=100))
    settings = json.loads((shell_dir / "Configs" / "defaults.json").read_text())
    settings["general"]["showChangelogOnStartup"] = False
    settings = deep_merge(settings, placements)
    (config / "settings.json").write_text(json.dumps(settings, indent=2) + "\n")

    env = qs_env(profile_dir, niri_sock)
    logf = open(case_dir / "run.log", "wb")
    proc = subprocess.Popen(
        ["timeout", "--kill-after=10s", str(SITES_WATCHDOG), "dbus-run-session", "--", "qs", "-p", str(shell_qml)],
        cwd=profile_dir, env=env, stdout=logf, stderr=subprocess.STDOUT, start_new_session=True)

    def log_text():
        return (case_dir / "run.log").read_bytes().decode("utf-8", "replace")

    def wait_for(pred, timeout):
        end = time.time() + timeout
        while time.time() < end:
            if pred(log_text()):
                return True
            if proc.poll() is not None:
                return False
            time.sleep(1)
        return False

    def ipc(*args):
        r = subprocess.run(["qs", "-p", str(shell_qml), "ipc", "call", *args], cwd=profile_dir, env=env,
                           capture_output=True, text=True, timeout=60)
        return {"rc": r.returncode, "out": (r.stdout + r.stderr).strip()}

    ipc_calls = {}
    try:
        started = wait_for(lambda t: "All plugins loaded" in t or "No plugins to load" in t, 180)
        if not started:
            failures.append("startup marker not seen within 180 s")
        else:
            if not wait_for(lambda t: fx_completed(t, "barWidget", SITE_FIXTURES)
                            and fx_completed(t, "desktopWidget", SITE_FIXTURES), 150):
                failures.append("bar or desktop widgets did not complete within 150 s")
            # A control-center shortcut is instantiated only while the control center is open.
            ipc_calls["controlCenter open"] = ipc("controlCenter", "toggle")
            wait_for(lambda t: fx_completed(t, "controlCenterWidget", SURFACES["controlCenterWidget"]), 30)
            time.sleep(2)
            ipc_calls["controlCenter close"] = ipc("controlCenter", "toggle")
            time.sleep(2)
            # Panels: the content is created when the panel opens (SmartPanel loader).
            for pid in ("fx-declares", "fx-bare", "fx-inherits"):
                ipc_calls[f"openPanel {pid}"] = ipc("plugin", "openPanel", keys[pid])
                wait_for(lambda t, pid=pid: fx_completed(t, "panel", [pid]), 30)
                time.sleep(2)
                ipc_calls[f"closePanel {pid}"] = ipc("plugin", "closePanel", keys[pid])
                time.sleep(2)
            # Settings pages (NPluginSettingsPopup); the popup stays open until the shell stops.
            for pid in ("fx-declares", "fx-bare"):
                ipc_calls[f"openSettings {pid}"] = ipc("plugin", "openSettings", keys[pid])
                wait_for(lambda t, pid=pid: fx_completed(t, "settings", [pid]), 30)
                time.sleep(2)
    finally:
        if proc.poll() is None:
            os.killpg(proc.pid, signal.SIGTERM)
            try:
                proc.wait(20)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid, signal.SIGKILL)
                proc.wait()
        logf.close()

    log = log_text()
    rows = parse_fx(log)
    for entry, names in SURFACES.items():
        for name in names:
            mine = [r for r in rows if r.get("id") == name and r.get("entry") == entry]
            completed = [r for r in mine if r.get("phase") == "completed"]
            if not completed:
                failures.append(f"{entry}: {name} never reached completed")
                continue
            if name == "fx-declares":
                for r in completed:
                    ctx = r.get("ctx", {})
                    missing = [n for n in SURFACE_CONTEXT.get(entry, []) if ctx.get(n) is None]
                    if missing:
                        failures.append(f"{entry}: fx-declares completed without {missing}: {ctx}")
                    if "screen" in SURFACE_CONTEXT.get(entry, []) and ctx.get("screen") != screen:
                        failures.append(f"{entry}: fx-declares completed with screen {ctx.get('screen')!r}")
            elif name == "fx-bare":
                for r in mine:
                    leaked = [n for n in CONTRACT_NAMES if n in r.get("ctx", {})]
                    if leaked:
                        failures.append(f"{entry}: fx-bare received undeclared {leaked}: {r}")
            elif name == "fx-inherits":
                changed = [r for r in mine if r.get("phase") == "changed:screen"]
                if not changed or changed[-1].get("ctx", {}).get("screen") != screen:
                    failures.append(f"{entry}: fx-inherits did not get screen via changed:screen: {changed[-1:]}")
                if mine[-1].get("ctx", {}).get("screen") != screen:
                    failures.append(f"{entry}: fx-inherits last context has stale screen: {mine[-1].get('ctx')}")

    def assert_last_context(entry, widget, expected):
        if widget.get("id") != "plugin:" + keys["fx-declares"]:
            return
        mine = [r for r in rows if r.get("id") == "fx-declares" and r.get("entry") == entry]
        ctx = mine[-1].get("ctx", {}) if mine else {}
        for field, value in expected.items():
            if ctx.get(field) != value:
                failures.append(f"{entry}: fx-declares last context {field} is {ctx.get(field)!r}, expected {value!r}: {ctx}")

    for entry, sections in (("barWidget", placements["bar"]["widgets"]),
                            ("controlCenterWidget", placements["controlCenter"]["shortcuts"])):
        for section, widgets in sections.items():
            for index, widget in enumerate(widgets):
                assert_last_context(entry, widget, {
                    "screen": screen,
                    # ShortcutsCard supplies the same contract section for
                    # both columns; the column still determines index/count.
                    "section": section if entry == "barWidget" else "quickSettings",
                    "sectionWidgetIndex": index,
                    "sectionWidgetsCount": len(widgets),
                })
    for monitor in placements["desktopWidgets"]["monitorWidgets"]:
        for index, widget in enumerate(monitor["widgets"]):
            assert_last_context("desktopWidget", widget, {"screen": monitor["name"], "widgetIndex": index})

    # Every non-existent-property line is a failure: the private profile holds only
    # the fixtures and the built-in shell, so the design allows none. Qt does not
    # name the plugin on these lines, so matching on fixture names is not enough.
    failing, other_errors = [], []
    for line in log.splitlines():
        shell_script_error = re.search(r"TypeError|ReferenceError", line) and "/config/plugins/" not in line
        if NON_EXISTENT.search(line) or shell_script_error or (ERRORS.search(line) and FIXTURE_TOKEN.search(line)):
            failing.append(line)
        elif ERRORS.search(line):
            other_errors.append(line)
    if failing:
        failures.append(f"error lines that must not occur ({len(failing)}): {failing[:20]}")

    recorded_failures = {}
    for site in FAILURE_SITES:
        token = "Plugin load error [" + keys[FAILURE_FIXTURE] + "/" + site + "]:"
        recorded_failures[site] = [line for line in log.splitlines() if token in line]
        if len(recorded_failures[site]) != 1:
            failures.append(f"{FAILURE_FIXTURE}/{site}: expected one recorded creation failure, got {len(recorded_failures[site])}")
        elif "Failed to instantiate " not in recorded_failures[site][0] or site + ".qml" not in recorded_failures[site][0]:
            failures.append(f"{FAILURE_FIXTURE}/{site}: creation failure lacks phase/source: {recorded_failures[site][0]}")

    (case_dir / "sites.json").write_text(json.dumps({
        "screen": screen, "keys": keys, "placements": placements, "ipc": ipc_calls,
        "fx": rows, "failing_error_lines": failing, "other_error_lines": other_errors,
        "recorded_failures": recorded_failures,
    }, indent=2) + "\n")
    (case_dir / "hashes.json").write_text(json.dumps(hashes, indent=2) + "\n")
    return {"screen": screen, "shell_exit": proc.returncode, "failing_error_lines": len(failing),
            "other_error_lines": len(other_errors), "fx_lines": len(rows)}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--source", required=True)
    ap.add_argument("--output", required=True)
    ap.add_argument("--case", required=True, choices=["core", "sites"])
    args = ap.parse_args()

    source = Path(args.source).resolve()
    output = Path(args.output).resolve()
    runtime = ROOT / "runtime" / output.name
    if not source.is_dir() or not output.is_relative_to(ROOT) or not source.is_relative_to(ROOT):
        raise SystemExit("PLUGIN_LOADER_REGRESSION: BLOCKED — source and output must be under the guest root")
    if output.exists() or runtime.exists():
        raise SystemExit("PLUGIN_LOADER_REGRESSION: BLOCKED — preserve earlier evidence/runtime; use a fresh output directory")
    output.mkdir(parents=True)

    failures, blocked, detail = [], None, None
    started = time.time()
    try:
        if args.case == "core":
            detail = case_core(source, output, runtime, failures)
        elif args.case == "sites":
            detail = case_sites(source, output, runtime, failures)
    except Blocked as b:
        blocked = str(b)

    for f in failures:
        print(f"FAIL: {f}")
    if blocked:
        print(f"BLOCKED: {blocked}")
    (output / "result.json").write_text(json.dumps(
        {"case": args.case, "source": str(source), "failures": failures, "blocked": blocked,
         "detail": detail, "seconds": round(time.time() - started, 1)}, indent=2) + "\n")
    if failures or blocked:
        print("PLUGIN_LOADER_REGRESSION: " + ("BLOCKED" if blocked and not failures else "FAIL"))
        return 1
    print(f"PLUGIN_LOADER_REGRESSION: PASS ({args.case})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
