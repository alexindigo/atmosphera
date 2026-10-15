#!/usr/bin/env python3
"""Guest-only unit regression: plugin contract table and root-declaration scanner.

Run with --source TREE --output FRESH_DIRECTORY in the named Qt612 niri VM.
The four files under test are copied into a private runtime tree inside the
output directory, the fixture runs there with `qs -p`, and every printed case
is compared with the expectations written below. Exit 0 only if every case is
present exactly once and matches. The docs cases compare the contract table in
docs/plugins/index.md with the contextNames printed for every entry point, so
drift between the docs and PluginContract.js fails the run.
"""
import argparse
import glob
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time

DOMAIN = "arch-niri-atmosphera-qt612-color"
ROOT = Path("/home/tester/Projects/qt612-atmocolor/081-integrity")
FILES = [
    "Services/Plugins/PluginContract.js",
    "Helpers/QmlRootDeclarations.js",
    "Scripts/dev/fixtures/plugin-contract.qml",
    "Scripts/dev/fixtures/plugin-contract-sample.qml",
]
FIXTURE = "Scripts/dev/fixtures/plugin-contract.qml"
SAMPLE = "Scripts/dev/fixtures/plugin-contract-sample.qml"
DOCS = "docs/plugins/index.md"
DOCS_HEADER = "| Entry point | Context names (besides `pluginApi`) |"
DOCS_SEPARATOR = "|---|---|"
DOCS_ROW = re.compile(r"^\| `(\w+)` \| (none|(?:`\w+`)(?:, `\w+`)*) \|$")
PREFIX = "PLUGIN_CONTRACT|"
DONE = "PLUGIN_CONTRACT_DONE"
ERRORS = re.compile(r"ReferenceError|TypeError|Cannot assign to non-existent property|Component is not ready|is not a function|Failed to load|module .* is not installed|PLUGIN_CONTRACT_ERROR")

ENTRY_POINTS = ["main", "barWidget", "controlCenterWidget", "desktopWidget", "panel", "settings",
                "desktopWidgetSettings", "launcherProvider"]
CONTRACT = {
    "main": [],
    "barWidget": ["screen", "widgetId", "section", "sectionWidgetIndex", "sectionWidgetsCount"],
    "controlCenterWidget": ["screen", "widgetId", "section", "sectionWidgetIndex", "sectionWidgetsCount", "widgetSettings"],
    "desktopWidget": ["screen", "widgetData", "widgetIndex"],
    "panel": ["screen"],
    "settings": [],
    "desktopWidgetSettings": ["widgetSettings"],
    "launcherProvider": [],
}

# Root-object names, written independently of the scanner's implementation.
ROOT_EXPECTED = {
    "root:simple": ["a", "b"],
    "root:modifiers": ["kids", "req", "ro", "combo", "plain", "sized"],
    "root:typed": ["items", "proc", "screen", "grid"],
    "root:alias": ["label", "inner"],
    "root:nested-child": ["outer"],
    "root:strings-comments": ["s1", "s2", "s3", "s4", "s5", "n1"],
    "root:function-body": ["a", "b"],
    "root:multiline-value": ["cfg", "after"],
    "root:regex-literal": ["rx", "after2", "tail"],
    "root:dotted-root": ["screen"],
    "root:empty": [],
    "root:real-file": ["activateOnLeftClick", "active", "mainInstance", "pluginApi", "remainingText", "scope",
                       "screen", "section", "sectionWidgetIndex", "sectionWidgetsCount", "showText", "widgetId"],
}


def docs_table(text):
    """{entry point: [context names]} from the one contract table in the plugin docs."""
    lines = text.splitlines()
    starts = [i for i, line in enumerate(lines) if line == DOCS_HEADER]
    if len(starts) != 1:
        raise ValueError(f"expected one contract table in {DOCS}, found {len(starts)}")
    start = starts[0]
    if lines[start + 1] != DOCS_SEPARATOR:
        raise ValueError("contract table separator row is not |---|---|")
    table = {}
    for line in lines[start + 2:]:
        if not line.startswith("|"):
            break
        match = DOCS_ROW.match(line)
        if not match:
            raise ValueError(f"unparsable contract row: {line!r}")
        entry, names = match.group(1), match.group(2)
        if entry in table:
            raise ValueError(f"duplicate entry point in docs: {entry}")
        table[entry] = [] if names == "none" else re.findall(r"`(\w+)`", names)
    return table


def docs_checks(cases, doc_text):
    """Compare the docs table with PluginContract.contextNames, as the fixture printed it."""
    def single(name):
        got = [c["output"] for c in cases if c["case"] == name]
        return got[0] if len(got) == 1 else None

    try:
        table = docs_table(doc_text)
    except ValueError as error:
        return [{"case": "docs:table", "expected": "one parsable contract table", "output": str(error), "ok": False}]
    entries = single("entryPoints")
    rows = [{"case": "docs:entryPoints", "expected": entries, "output": list(table),
             "ok": entries is not None and list(table) == entries}]
    for entry in entries or []:
        want = single(f"contract:{entry}")
        got = table.get(entry)
        rows.append({"case": f"docs:{entry}", "expected": want, "output": got,
                     "ok": want is not None and got == want})
    return rows


def expected_cases():
    cases = {"entryPoints": ENTRY_POINTS}
    for entry in ENTRY_POINTS:
        cases[f"contract:{entry}"] = CONTRACT[entry]
    cases["contract:unknown"] = []
    cases["contract:constructor"] = []
    for name, names in ROOT_EXPECTED.items():
        cases[name] = sorted(names)
    return cases


def command(argv, env=None, seconds=20):
    return subprocess.run(["timeout", "--kill-after=5s", str(seconds), *map(str, argv)],
                          env=env, capture_output=True, text=True, timeout=seconds + 10)


def guest_env(output):
    assert os.getuid() == 1000 and Path.home() == Path("/home/tester")
    macs = [p.read_text().strip().lower() for p in Path("/sys/class/net").glob("*/address")]
    assert "52:54:00:4c:05:2c" in macs, (DOMAIN, macs)
    socks = glob.glob("/run/user/1000/niri.*.sock")
    assert len(socks) == 1 and Path("/run/user/1000/wayland-1").exists()
    return dict(os.environ, XDG_RUNTIME_DIR="/run/user/1000", WAYLAND_DISPLAY="wayland-1", NIRI_SOCKET=socks[0],
                ATMOSPHERA_CONFIG_DIR=str(output / "config") + "/", ATMOSPHERA_CACHE_DIR=str(output / "cache") + "/",
                ATMOSPHERA_SETTINGS_FILE=str(output / "config/settings.json"), ATMOSPHERA_DEBUG="0",
                TMPDIR="/home/tester/Projects/qt612-atmocolor/tmp", QT_FORCE_STDERR_LOGGING="1",
                ATMOSPHERA_UPGRADELOG_URL="http://127.0.0.1:9")


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def parse(log):
    cases = []
    for line in log.splitlines():
        if PREFIX in line:
            cases.append(json.loads(line.split(PREFIX, 1)[1]))
    return cases


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    source, output = Path(args.source).resolve(), Path(args.output).resolve()
    assert source.is_relative_to(ROOT) and output.is_relative_to(ROOT)
    assert not output.exists(), "Preserve earlier evidence; use a fresh output directory"
    env = guest_env(output)
    output.mkdir(parents=True)
    for part in ("config", "cache"):
        (output / part).mkdir()

    runtime = output / "runtime"
    hashes = {}
    for rel in FILES:
        target = runtime / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source / rel, target)
        hashes[rel] = sha256(target)
    hashes[DOCS] = sha256(source / DOCS)

    # Quickshell confines relative imports to its config root, so the fixture
    # stays at its repository path and is loaded through a root entry, as in
    # settings-model-regression.py.
    entry = runtime / "shell.qml"
    entry.write_text('import QtQuick\nItem { Loader { source: "%s" } }\n' % FIXTURE)
    env["PLUGIN_CONTRACT_SAMPLE"] = str(runtime / SAMPLE)
    result = command(["dbus-run-session", "--", "qs", "-p", entry], env, 40)
    log = result.stdout + result.stderr
    (output / "probe.log").write_text(log)

    cases = parse(log)
    expected = expected_cases()
    seen = {}
    for case in cases:
        seen[case["case"]] = seen.get(case["case"], 0) + 1
    failures = []
    rows = []
    for name, want in expected.items():
        got = [c["output"] for c in cases if c["case"] == name]
        ok = len(got) == 1 and got[0] == want
        rows.append({"case": name, "expected": want, "output": got[0] if len(got) == 1 else got, "ok": ok})
        if not ok:
            failures.append(name)
        print(f"[{'PASS' if ok else 'FAIL'}] {name}", flush=True)
    for row in docs_checks(cases, (source / DOCS).read_text()):
        rows.append(row)
        if not row["ok"]:
            failures.append(row["case"])
        print(f"[{'PASS' if row['ok'] else 'FAIL'}] {row['case']}", flush=True)
    unexpected = sorted(set(seen) - set(expected))
    if unexpected:
        failures.append(f"unexpected cases: {unexpected}")
    if result.returncode != 0 or DONE not in log:
        failures.append(f"fixture exit {result.returncode}, done marker {DONE in log}")
    if ERRORS.search(log):
        failures.append("error line in fixture log")

    summary = {"source": str(source), "source_sha256": hashes, "fixture_exit": result.returncode,
               "cases": rows, "unexpected": unexpected, "failures": failures, "at": time.time()}
    (output / "result.json").write_text(json.dumps(summary, indent=2) + "\n")
    print("PLUGIN_CONTRACT_REGRESSION: " + ("FAIL" if failures else "PASS") + f" ({len(rows)} cases)", flush=True)
    return int(bool(failures))


if __name__ == "__main__":
    raise SystemExit(main())
