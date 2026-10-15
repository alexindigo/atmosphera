#!/usr/bin/env python3
"""Guest-only unit check: plugins.json v5 migration planner (M11).

Run with --source TREE in the Qt612 niri VM. Helpers/PluginProfileMigration.js
and Scripts/dev/fixtures/plugin-profile-migration.qml are copied into a private
runtime tree under ROOT/runtime/<unique name>, the fixture runs there with
`qs -p`, and every printed case is compared with the expectations written below
(output equality, plus the order of the states keys). Exit 0 only if every case
is present exactly once and matches. Nothing is written into --source.
--output is optional: when given it must not exist and receives a copy of
result.json.
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

ROOT = Path("/home/tester/Projects/qt612-atmocolor/081-integrity")
FILES = [
    "Helpers/PluginProfileMigration.js",
    "Scripts/dev/fixtures/plugin-profile-migration.qml",
]
FIXTURE = "Scripts/dev/fixtures/plugin-profile-migration.qml"
PREFIX = "PLUGIN_PROFILE_MIGRATION|"
DONE = "PLUGIN_PROFILE_MIGRATION_DONE"
ERRORS = re.compile(r"ReferenceError|TypeError|Cannot assign to non-existent property|Component is not ready|is not a function|Failed to load|module .* is not installed|PLUGIN_PROFILE_MIGRATION_ERROR")

BUILTIN = "file:///etc/xdg/quickshell/atmosphera/builtin/plugins"
OLD_BUILTIN = "file:///etc/xdg/quickshell/atmosphera/Plugins"
REGISTRY = "https://github.com/alexindigo/atmosphera-plugins"
WALLPAPERS = "https://github.com/atmosphera/atmosphera-wallpapers"
SHIPPED = ["noctalia-icons", "clock", "launcher"]
REGISTRY_IDS = [("pomodoro", True), ("weather", False), ("todo", True), ("calendar", True),
                ("notes", False), ("timer", True), ("music", True), ("wifi-menu", False),
                ("emoji", True), ("unit-converter", False), ("rss", True)]
BUILTIN_SOURCE = {"name": "Built-in", "url": BUILTIN, "enabled": True}
REGISTRY_SOURCE = {"name": "Atmosphera Plugins", "url": REGISTRY, "enabled": True}
WALLPAPERS_SOURCE = {"name": "Atmosphera Wallpapers", "url": WALLPAPERS, "enabled": False}


def source_hash(url):
    """First six hex digits of sha256(url), the same key prefix the shell writes."""
    return hashlib.sha256(url.encode()).hexdigest()[:6]


def registry_states(hash_):
    return {f"{hash_}:{name}": {"enabled": enabled, "sourceUrl": REGISTRY} for name, enabled in REGISTRY_IDS}


def expected_cases(hashes):
    cur, old, reg = hashes["current"], hashes["old"], hashes["registry"]
    user_expected = {
        "states": {
            f"{cur}:noctalia-icons": {"enabled": True, "sourceUrl": BUILTIN},
            f"{cur}:clock": {"enabled": False, "sourceUrl": BUILTIN},
            f"{cur}:launcher": {"enabled": True, "sourceUrl": BUILTIN},
            **registry_states(reg),
            "digest-watcher": {"enabled": True, "sourceUrl": None},
        },
        "sources": [BUILTIN_SOURCE, REGISTRY_SOURCE, WALLPAPERS_SOURCE],
        "rekeys": [
            {"from": "builtin:noctalia-icons", "to": f"{cur}:noctalia-icons", "id": "noctalia-icons"},
            {"from": "builtin:clock", "to": f"{cur}:clock", "id": "clock"},
            {"from": "builtin:launcher", "to": f"{cur}:launcher", "id": "launcher"},
        ],
        "removals": ["builtin:noctalia-icons-legacy"],
        "dropped": [],
        "unsourced": ["digest-watcher"],
        "settingsFileMoves": [
            {"from": "builtin:clock.json", "to": f"{cur}:clock.json"},
            {"from": "builtin:clock.config.json", "to": f"{cur}:clock.config.json"},
        ],
    }
    empty = {"rekeys": [], "removals": [], "dropped": [], "unsourced": [], "settingsFileMoves": []}
    cases = {
        "user-shaped": user_expected,
        "pre-0.6-hashed": {
            "states": {
                f"{cur}:clock": {"enabled": True, "sourceUrl": BUILTIN},
                f"{reg}:weather": {"enabled": False, "sourceUrl": REGISTRY},
            },
            "sources": [BUILTIN_SOURCE, REGISTRY_SOURCE, WALLPAPERS_SOURCE],
            "rekeys": [{"from": f"{old}:clock", "to": f"{cur}:clock", "id": "clock"}],
            "removals": [f"{old}:retired-thing"],
            "dropped": [],
            "unsourced": [],
            "settingsFileMoves": [],
        },
        "old-and-current": {
            "states": {f"{cur}:clock": {"enabled": False, "sourceUrl": BUILTIN}},
            "sources": [BUILTIN_SOURCE, REGISTRY_SOURCE, WALLPAPERS_SOURCE],
            "rekeys": [],
            "removals": [],
            "dropped": [f"{old}:clock"],
            "unsourced": [],
            "settingsFileMoves": [],
        },
        "old-key-settings": {
            "states": {f"{cur}:clock": {"enabled": True, "sourceUrl": BUILTIN}},
            "sources": [BUILTIN_SOURCE, REGISTRY_SOURCE, WALLPAPERS_SOURCE],
            "rekeys": [{"from": "builtin:clock", "to": f"{cur}:clock", "id": "clock"}],
            "removals": [],
            "dropped": [],
            "unsourced": [],
            # The .config override is not moved: its target already exists.
            "settingsFileMoves": [{"from": "builtin:clock.json", "to": f"{cur}:clock.json"}],
        },
        "fresh-seed": {
            "states": {
                f"{cur}:noctalia-icons": {"enabled": True, "sourceUrl": BUILTIN},
                f"{cur}:clock": {"enabled": True, "sourceUrl": BUILTIN},
                f"{cur}:launcher": {"enabled": True, "sourceUrl": BUILTIN},
                f"{reg}:pomodoro": {"enabled": False, "sourceUrl": REGISTRY},
            },
            "sources": [BUILTIN_SOURCE, REGISTRY_SOURCE, WALLPAPERS_SOURCE],
            **empty,
        },
        # Second run on the user-shaped output: states and sources are unchanged;
        # the unsourced list is informational and is reported again.
        "already-migrated": {
            "states": user_expected["states"],
            "sources": user_expected["sources"],
            "rekeys": [],
            "removals": [],
            "dropped": [],
            "unsourced": ["digest-watcher"],
            "settingsFileMoves": [],
        },
        # Settings references: rekeyed, dropped and removed keys; a registry
        # plugin and a core widget stay; instanceSettings survive every rewrite.
        "settings-references": {
            "states": {
                f"{cur}:noctalia-icons": {"enabled": True, "sourceUrl": BUILTIN},
                f"{cur}:clock": {"enabled": False, "sourceUrl": BUILTIN},
                f"{cur}:launcher": {"enabled": True, "sourceUrl": BUILTIN},
                f"{reg}:weather": {"enabled": False, "sourceUrl": REGISTRY},
            },
            "sources": [BUILTIN_SOURCE, REGISTRY_SOURCE, WALLPAPERS_SOURCE],
            "rekeys": [
                {"from": "builtin:clock", "to": f"{cur}:clock", "id": "clock"},
                {"from": "builtin:launcher", "to": f"{cur}:launcher", "id": "launcher"},
            ],
            "removals": ["builtin:noctalia-icons-legacy"],
            "dropped": ["builtin:noctalia-icons"],
            "unsourced": [],
            "settingsFileMoves": [],
            "settings": {
                "barWidgets": {
                    "left": [
                        {"id": f"plugin:{cur}:clock", "instanceSettings": {"format": "24h", "tint": {"r": 1}}, "size": "large"},
                        {"id": "workspaces"},
                    ],
                    "center": [{"id": f"plugin:{cur}:launcher", "instanceSettings": {"pinned": ["a"]}}],
                    "right": [
                        {"id": "plugin:builtin:noctalia-icons-legacy", "instanceSettings": {"keep": True}},
                        {"id": f"plugin:{cur}:noctalia-icons", "instanceSettings": {"variant": "dark"}, "order": 2},
                        {"id": f"plugin:{reg}:weather", "instanceSettings": {"units": "c"}},
                    ],
                },
                "screenOverrides": [
                    {
                        "name": "DP-1",
                        "position": "top",
                        "widgets": {
                            "left": [{"id": f"plugin:{cur}:clock", "instanceSettings": {"format": "12h"}}],
                            "center": [],
                            "right": [{"id": "plugin:builtin:noctalia-icons-legacy"}],
                        },
                    },
                    {"name": "HDMI-1", "enabled": False},
                ],
                "controlCenterShortcuts": {
                    "left": [{"id": f"plugin:{cur}:clock", "instanceSettings": {"face": "round"}}],
                    "right": [{"id": f"plugin:{reg}:todo", "instanceSettings": {"sort": "due"}}],
                },
                "monitorWidgets": [
                    {
                        "name": "DP-1",
                        "widgets": [
                            {"id": f"plugin:{cur}:clock", "x": 40, "y": 60, "instanceSettings": {"format": "24h"}},
                            {"id": f"plugin:{reg}:pomodoro", "x": 0, "y": 0},
                        ],
                    },
                    {"name": "HDMI-1", "widgets": []},
                ],
                "lockScreenPlugin": f"{cur}:clock",
                "touched": {
                    "barWidgets": True,
                    "screenOverrides": True,
                    "controlCenterShortcuts": True,
                    "monitorWidgets": True,
                    "lockScreenPlugin": True,
                },
            },
        },
    }
    # Case 8 feeds the same references held in QML list<var> properties and
    # must produce case 7's output exactly.
    cases["settings-references-qml-lists"] = cases["settings-references"]
    return cases


def command(argv, env=None, seconds=40):
    return subprocess.run(["timeout", "--kill-after=5s", str(seconds), *map(str, argv)],
                          env=env, capture_output=True, text=True, timeout=seconds + 10)


def guest_env(config):
    assert os.getuid() == 1000 and Path.home() == Path("/home/tester")
    macs = [p.read_text().strip().lower() for p in Path("/sys/class/net").glob("*/address")]
    assert "52:54:00:4c:05:2c" in macs, macs
    socks = glob.glob("/run/user/1000/niri.*.sock")
    assert len(socks) == 1 and Path("/run/user/1000/wayland-1").exists()
    return dict(os.environ, XDG_RUNTIME_DIR="/run/user/1000", WAYLAND_DISPLAY="wayland-1", NIRI_SOCKET=socks[0],
                ATMOSPHERA_CONFIG_DIR=str(config / "config") + "/", ATMOSPHERA_CACHE_DIR=str(config / "cache") + "/",
                ATMOSPHERA_SETTINGS_FILE=str(config / "config/settings.json"), ATMOSPHERA_DEBUG="0",
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
    parser.add_argument("--output")
    args = parser.parse_args()
    source = Path(args.source).resolve()
    assert source.is_relative_to(ROOT), "--source must be under the guest root"
    output = Path(args.output).resolve() if args.output else None
    if output is not None:
        assert not output.exists(), "Preserve earlier evidence; use a fresh output path"

    stamp = time.strftime("%Y%m%dT%H%M%S")
    run = ROOT / "runtime" / f"plugin-profile-migration-{stamp}-{os.getpid()}"
    assert not run.exists(), run
    tree = run / "tree"
    config = run / "profile"
    for part in ("config", "cache"):
        (config / part).mkdir(parents=True)
    hashes = {"current": source_hash(BUILTIN), "old": source_hash(OLD_BUILTIN), "registry": source_hash(REGISTRY)}

    hashes_src = {}
    for rel in FILES:
        target = tree / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source / rel, target)
        hashes_src[rel] = sha256(target)
    # Quickshell confines relative imports to its config root, so the fixture
    # keeps its repository path and is loaded through a root entry.
    (tree / "shell.qml").write_text('import QtQuick\nItem { Loader { source: "%s" } }\n' % FIXTURE)

    env = guest_env(config)
    env["PLUGIN_PROFILE_MIGRATION_HASHES"] = json.dumps(hashes)
    result = command(["dbus-run-session", "--", "qs", "-p", tree / "shell.qml"], env, 40)
    log = result.stdout + result.stderr
    (run / "probe.log").write_text(log)

    cases = parse(log)
    expected = expected_cases(hashes)
    seen = {}
    for case in cases:
        seen[case["case"]] = seen.get(case["case"], 0) + 1
    failures = []
    rows = []
    for name, want in expected.items():
        got = [c["output"] for c in cases if c["case"] == name]
        if len(got) != 1:
            ok = False
            detail = f"{len(got)} output lines"
        else:
            out = got[0]
            fields = {k: out.get(k) == v for k, v in want.items()}
            order_ok = list(out.get("states", {})) == list(want.get("states", {}))
            ok = all(fields.values()) and order_ok
            detail = {"fields": fields, "states_order": order_ok}
        rows.append({"case": name, "ok": ok, "detail": detail, "output": got[0] if len(got) == 1 else got})
        if not ok:
            failures.append(name)
        print(f"[{'PASS' if ok else 'FAIL'}] {name}", flush=True)
    unexpected = sorted(set(seen) - set(expected))
    if unexpected:
        failures.append(f"unexpected cases: {unexpected}")
    if result.returncode != 0 or DONE not in log:
        failures.append(f"fixture exit {result.returncode}, done marker {DONE in log}")
    if ERRORS.search(log):
        failures.append("error line in fixture log")

    summary = {"source": str(source), "run": str(run), "source_sha256": hashes_src, "hashes": hashes,
               "fixture_exit": result.returncode, "cases": rows, "unexpected": unexpected,
               "failures": failures, "at": time.time()}
    text = json.dumps(summary, indent=2) + "\n"
    (run / "result.json").write_text(text)
    if output is not None:
        output.mkdir(parents=True)
        (output / "result.json").write_text(text)
    print("PLUGIN_PROFILE_MIGRATION_UNIT: " + ("FAIL" if failures else "PASS") + f" ({len(rows)} cases)", flush=True)
    return int(bool(failures))


if __name__ == "__main__":
    raise SystemExit(main())
