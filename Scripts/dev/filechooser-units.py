#!/usr/bin/env python3
"""Run real file chooser QML services in an isolated shell in the assigned VM."""

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import wave

from filechooser_regression import desktop_fixture
from filechooser_isolation import enter, guest, profile_env

ROOT = Path("/home/tester/Projects/atmosphera-filechooser")
PREFIX = "FILECHOOSER_UNITS|"
ERRORS = re.compile(r"TypeError|ReferenceError|Cannot assign|Binding loop|Failed to load configuration|is not a type|Unable to assign|Error:")


def main():
    enter()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--mascot-scheme", type=Path)
    args = parser.parse_args()
    guest()
    source, output = args.source.resolve(), args.output.resolve()
    runtime = ROOT / "runtime" / output.name
    if not source.is_relative_to(ROOT / "sources") or not output.is_relative_to(ROOT / "evidence"):
        parser.error("source/output must be inside the assigned guest workspace")
    if output.exists() or runtime.exists():
        parser.error("new output/runtime label required")
    output.mkdir(parents=True)
    runtime.mkdir(parents=True)
    shell = runtime / "shell"
    shutil.copytree(source, shell, symlinks=True)
    probe = shell / "filechooser-units.qml"
    probe.write_text((source / "Scripts/dev/fixtures/filechooser-units.qml").read_text().replace('"../../../Helpers/', '"Helpers/').replace('"filechooser-icon-cases.js"', '"Scripts/dev/fixtures/filechooser-icon-cases.js"'))
    fixtures = runtime / "fixtures"
    fixtures.mkdir()
    (fixtures / "folder").mkdir()
    (fixtures / "empty").mkdir()
    for name, size, stamp in [("item2.txt", 30, 1000000000), ("item10.png", 10, 1200000000), ("Alpha.txt", 20, 1100000000), (".hidden.txt", 1, 900000000)]:
        path = fixtures / name
        path.write_bytes(b"x" * size)
        os.utime(path, (stamp, stamp))
    aux = runtime / "aux"
    aux.mkdir()
    for name in ["documents", "bookmark", "removed", "vanish", "denied", "unreadable", "no-search"] + [f"memory{i}" for i in range(12)]:
        (aux / name).mkdir()
    for name in ["With space", "hash#name", "percent%20literal", "question?mark", "résumé", "a b/c d"]:
        folder = aux / "escaped" / name
        folder.mkdir(parents=True)
        (folder / "fixture.txt").write_text(name, encoding="utf-8")
    (aux / "vanish/selected.txt").write_text("selected")
    (aux / "unreadable/selected.txt").write_text("unreadable")
    (aux / "unreadable/selected.txt").chmod(0)
    (aux / "denied").chmod(0)
    (aux / "no-search").chmod(0o400)
    previews = aux / "previews"
    previews.mkdir()
    with wave.open(str(previews / "unit.wav"), "wb") as audio:
        audio.setnchannels(1); audio.setsampwidth(2); audio.setframerate(8000)
        audio.writeframes(b"\0\0" * 8000 * 8)
    for name, content in {
        "small.txt": "Hello, 世界\n".encode(),
        "large.txt": b"a" * 262_145,
        "limit.txt": b"b" * 262_144,
        "cut.txt": b"c" * 262_143 + "界".encode(),
        "invalid.txt": b"hello\xffworld",
        "nul.txt": b"hello\x00world",
        "invalid-cut.txt": b"x\xff" + b"x" * 262_144,
        "unreadable.txt": b"private",
    }.items():
        (previews / name).write_bytes(content)
    (previews / "unreadable.txt").chmod(0)
    os.mkfifo(previews / "stale.txt")
    profile = runtime / "profile"
    for directory in ("config", "cache", "state", "tmp", "data"):
        (profile / directory).mkdir(parents=True)
    (profile / "config/user-dirs.dirs").write_text(f'XDG_DOCUMENTS_DIR="{aux}/documents"\n')
    (profile / "config/gtk-3.0").mkdir()
    (profile / "config/gtk-3.0/bookmarks").write_text(f'{(aux / "bookmark").as_uri()} Test bookmark\n')
    (profile / "data/recently-used.xbel").write_text(f'<xbel><bookmark href="{(fixtures / "Alpha.txt").as_uri()}" modified="2026-10-18T00:00:00Z"/></xbel>')
    desktop_fixture(profile / "data")
    schemes = []
    for name in ("MacOS", "Catppuccin", "Gruvbox", "Ayu"):
        for mode, colors in json.loads((source / f"Assets/ColorScheme/{name}/{name}.json").read_text()).items():
            if mode in ("dark", "light"):
                schemes.append({"name": name + "-" + mode, "colors": colors})
    mascot = args.mascot_scheme or source / "Scripts/dev/fixtures/filechooser-mascot-scheme.json"
    for mode, colors in json.loads(mascot.read_text())["schemes"].items():
        schemes.append({"name": "mascot-" + mode, "colors": colors})
    env = dict(profile_env(profile), FILECHOOSER_ICON_SCHEMES=json.dumps(schemes),
               QT_FORCE_STDERR_LOGGING="1", FILECHOOSER_UNIT_ROOT=str(fixtures), FILECHOOSER_UNIT_AUX=str(aux),
               ATMOSPHERA_DEBUG="0")
    runs = []
    for mode in ("main", "reload"):
        process = subprocess.run(["timeout", "--kill-after=5s", "90", "qs", "-p", str(probe)],
                                 cwd=shell, env=dict(env, FILECHOOSER_UNIT_RELOAD="1" if mode == "reload" else "0"),
                                 capture_output=True, text=True, timeout=100)
        text = process.stdout + process.stderr
        (output / f"{mode}.log").write_text(text)
        runs.append(dict(mode=mode, exit=process.returncode, log=text))
        if process.returncode != 0:
            break
    log = "".join(run["log"] for run in runs)
    (output / "run.log").write_text(log)
    rows = [json.loads(line.split(PREFIX, 1)[1]) for line in log.splitlines() if PREFIX in line]
    errors = [line for line in log.splitlines() if ERRORS.search(line)]
    cases = [row for row in rows if "case" in row]
    complete = sum(row.get("complete") is True for row in rows) == 2
    failures = [row for row in cases if not row["pass"]]
    required = {"browser.navigate", "browser.failure-keeps-folder", "browser.failure-keeps-listing", "browser.natural-name",
                "browser.missing-copy", "browser.permission-copy", "browser.search-permission-copy", "browser.not-folder-copy",
                "browser.descending-folders-first", "browser.size", "browser.type", "browser.modified", "browser.mime-filter",
                "browser.glob-filter-keeps-folders", "browser.show-hidden", "browser.removed-parent-fallback",
                "selection.range", "selection.type-ahead", "selection.filter-revalidation", "selection.sort-remaps-cursor",
                "selection.all-files", "selection.all-folders", "request.no-disk-before-accept", "request.cancel-once",
                "request.success-once", "request.replace-confirmed", "request.saveFiles-order", "request.choices",
                 "request.current-filter", "request.cancel-inflight", "request.remembered-folder-drives-listing", "request.missing-app-folder-fallback",
                 "request.app-entry", "request.app-empty", "request.app-unknown", "request.choices-order", "request.choices-defaults",
                "memory.per-app-a", "memory.shared-fallback", "memory.top-ten", "memory.newest-first-dedupe",
                 "memory.missing-hidden", "memory.reload-app", "memory.reload-preferences",
                 "preview.small", "preview.large", "preview.exact-limit", "preview.multibyte-cut",
                 "preview.invalid-utf8", "preview.missing", "preview.kind-switch", "preview.stale-reply", "preview.pdf-detection",
                 "types.bytes-small", "types.size-scaled", "types.size-german", "types.date-us", "types.date-british", "types.date-german", "types.date-system"}
    for name in ["With space", "résumé", "a b/c d"]:
        required.update(f"paths.{name}.{case}" for case in ("ready", "listing", "breadcrumbs", "request-ready", "request-result"))
    for name in ["hash#name", "percent%20literal", "question?mark"]:
        required.update(f"paths.{name}.{case}" for case in ("error", "keeps-folder", "keeps-listing", "not-loading", "recovers"))
    required.update(f"paths.helper.{name}" for name in ("With space", "hash#name", "percent%20literal", "question?mark", "résumé", "a b/c d", "strict-portal-spaces", "invalid-urls"))
    missing = sorted(required - {case["case"] for case in cases})
    required_media = {"playback." + name for name in ("initial", "inactive-intents", "volume-low", "volume-high", "volume-step", "invalid-volume", "times", "autoplay", "seek-low", "seek-high", "close-stops", "close-destroys-engine")}
    required_labels = {"labels." + name for name in ("extension-attached", "dots", "long-word", "cjk", "extension-only", "two-lines-only")}
    missing += sorted((required_media | required_labels) - {case["case"] for case in cases})
    required_icons = {"icons.network-mount", "icons.xdg-settings", "icons.hidden", "icons.directory-precedence"}
    required_icons.update("icons.type." + t for t in ("image", "video", "audio", "text", "markdown", "pdf", "document", "spreadsheet", "presentation", "ebook", "web", "code", "data", "zip", "tar", "gzip", "xz", "bzip", "zstd", "sevenzip", "rar", "archive", "executable", "disk", "font", "unknown"))
    required_icons.update("icons." + kind + "." + scheme["name"] + "." + group for kind in ("tones", "ink") for scheme in schemes for group in ("media", "text", "rest", "archives"))
    missing += sorted(required_icons - {case["case"] for case in cases})
    files_untouched = all(not (fixtures / name).exists() for name in ("draft.txt", "new # résumé.txt", "brand-new.txt", "stale.txt", "folder/child.txt"))
    files_untouched = files_untouched and (fixtures / "item2.txt").read_bytes() == b"x" * 30 and (fixtures / "item10.png").read_bytes() == b"x" * 10
    cases.append(dict(case="request.no-target-file-writes", **{"pass": files_untouched}))
    if not files_untouched:
        failures.append(cases[-1])
    result = dict(exit=process.returncode, runs=[{k: v for k, v in run.items() if k != "log"} for run in runs], cases=cases, failures=failures, missing_cases=missing, error_lines=errors,
                  complete=complete, source=str(source), runtime=str(runtime))
    result["status"] = "green" if process.returncode == 0 and complete and cases and not failures and not errors and not missing else "red"
    (output / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({**{key: value for key, value in result.items() if key != "cases"}, "case_count": len(cases)}, indent=2))
    return 0 if result["status"] == "green" else 1


if __name__ == "__main__":
    sys.exit(main())
