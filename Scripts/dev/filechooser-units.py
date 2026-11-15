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
from filechooser_profile import current_profile, workspace, exact_source, profile_argument
PREFIX = "FILECHOOSER_UNITS|"
ERRORS = re.compile(r"TypeError|ReferenceError|Cannot assign|Binding loop|Failed to load configuration|is not a type|Unable to assign|Error:")


def main():
    enter()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--mascot-scheme", type=Path)
    profile_argument(parser)
    args = parser.parse_args()
    guest()
    source, output = args.source.resolve(), args.output.resolve()
    runtime = current_profile().runtime / output.name
    if not exact_source(source) or not output.is_relative_to(current_profile().evidence):
        parser.error("source/output must be inside the assigned guest workspace")
    if output.exists() or runtime.exists():
        parser.error("new output/runtime label required")
    output.mkdir(parents=True)
    runtime.mkdir(parents=True)
    shell = runtime / "shell"
    shutil.copytree(source, shell, symlinks=True)
    probe = shell / "filechooser-units.qml"
    probe_text = (source / "Scripts/dev/fixtures/filechooser-units.qml").read_text().replace('"../../../Helpers/', '"Helpers/')
    for name in ("filechooser-icon-cases.js", "filechooser-extensions.js", "filechooser-navigation.js", "filechooser-paths.js", "filechooser-operations.js", "filechooser-views.js", "filechooser-places.js"):
        probe_text = probe_text.replace('"' + name + '"', '"Scripts/dev/fixtures/' + name + '"')
    probe.write_text(probe_text)
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
    for name in ["documents", "bookmark", "removed", "vanish", "denied", "unreadable", "no-search", "creation", "write-denied"] + [f"memory{i}" for i in range(12)]:
        (aux / name).mkdir()
    (aux / "creation/Taken").mkdir()
    (aux / "creation/Existing.txt").write_text("existing fixture\n")
    operations = aux / "operations"
    (operations / "directory").mkdir(parents=True)
    (operations / "directory/child.txt").write_text("recursive delete fixture\n")
    (operations / "first.txt").write_text("rename then trash bytes\n")
    (operations / "taken.txt").write_text("never overwritten\n")
    overwrite = aux / "overwrite"
    overwrite.mkdir(); (overwrite / "child").mkdir(); (overwrite / "directory").mkdir()
    extensions = aux / "extensions"
    extensions.mkdir(); (extensions / "directory").mkdir()
    (extensions / "protected.png").write_text("protected extension target\n")
    (extensions / "raw").write_text("raw existing target\n")
    (overwrite / "protected.txt").write_text("ORIGINAL protected\n")
    (overwrite / "other.txt").write_text("ORIGINAL other\n")
    (overwrite / "a.txt").write_text("case-sensitive\n")
    (overwrite / "unwritable.txt").write_text("read only\n")
    (overwrite / "unwritable.txt").chmod(0o444)
    os.mkfifo(overwrite / "fifo")
    (overwrite / "regular-link").symlink_to(overwrite / "protected.txt")
    (overwrite / "directory-link").symlink_to(overwrite / "directory", target_is_directory=True)
    (overwrite / "dangling").symlink_to(overwrite / "missing")
    (aux / "write-denied").chmod(0o555)
    for i in range(7):
        (aux / f"recent{i}").mkdir()
    readonly = current_profile().workspace / "fixtures/read-only"
    assert readonly.is_dir() and os.statvfs(readonly).f_flag & os.ST_RDONLY, "provision the owned guest's read-only fixture first"
    (aux / "readonly").symlink_to(readonly, target_is_directory=True)
    for name in ["With space", "hash#name", "percent%20literal", "question?mark", "résumé", "a b/c d"]:
        folder = aux / "escaped" / name
        folder.mkdir(parents=True)
        (folder / "fixture.txt").write_text(name, encoding="utf-8")
    for i in range(6): (aux / ("model%watch" + str(i))).mkdir()
    links = aux / "path-links"
    (links / "target/sub").mkdir(parents=True)
    (links / "link").symlink_to(links / "target/sub", target_is_directory=True)
    (links / "Report.txt").write_text("wrong lexical target\n")
    (links / "target/Report.txt").write_text("physical parent target\n")
    uri_names = aux / "completion-uris"
    uri_names.mkdir()
    for name in ("report%20draft.txt", "report draft.txt", "report#draft.txt", "report?draft.txt", "report-résumé.txt"):
        (uri_names / name).write_text(name)
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
    (profile / "config/gtk-3.0/bookmarks").write_text(f'{(aux / "bookmark").as_uri()}/ Test bookmark\n')
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
    operation_tests = subprocess.run([sys.executable, "-B", str(source / "Scripts/dev/filechooser-operations-test.py"), str(runtime / "operation-files")],
                                    env=env, capture_output=True, text=True, timeout=90)
    (output / "operations-filesystem.log").write_text(operation_tests.stdout + operation_tests.stderr)
    bookmark_tests = subprocess.run([sys.executable, "-B", str(source / "Scripts/dev/filechooser-bookmarks-test.py"), str(runtime / "bookmark-files")],
                                    env=env, capture_output=True, text=True, timeout=90)
    (output / "bookmarks-filesystem.log").write_text(bookmark_tests.stdout + bookmark_tests.stderr)
    runs = []
    for mode in ("main", "reload"):
        try:
            process = subprocess.run(["timeout", "--kill-after=5s", "90", "qs", "-p", str(probe)],
                                     cwd=shell, env=dict(env, FILECHOOSER_UNIT_RELOAD="1" if mode == "reload" else "0"),
                                     capture_output=True, text=True, timeout=100)
        except subprocess.TimeoutExpired as error:
            def decoded(value):
                return value.decode(errors="replace") if isinstance(value, bytes) else value or ""
            (output / f"{mode}.log").write_text(decoded(error.stdout) + decoded(error.stderr))
            raise
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
    cases += json.loads(operation_tests.stdout) if operation_tests.returncode == 0 else [dict(case="operations.filesystem", **{"pass": False})]
    cases += json.loads(bookmark_tests.stdout) if bookmark_tests.returncode == 0 else [dict(case="bookmarks.filesystem", **{"pass": False})]
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
    for name in ["With space", "résumé", "a b/c d", "hash#name", "percent%20literal", "question?mark"]:
        required.update(f"paths.{name}.{case}" for case in ("ready", "listing", "breadcrumbs", "request-ready", "request-result"))
    required.update(f"paths.helper.{name}" for name in ("With space", "hash#name", "percent%20literal", "question?mark", "résumé", "a b/c d", "strict-portal-spaces", "invalid-urls"))
    required.update("filter." + name for name in ("substring-case", "type-intersection", "folders", "hidden-respected", "hidden-opt-in", "combined-substrings", "navigation-clears", "save-prefill", "save-name-revalidation", "save-toggle"))
    required.update("create." + name for name in ("success-model", "exists-directory", "exists-file", "permission", "readonly", "folder-selection", "save-stays-in-folder"))
    required.update("create.invalid-" + str(i) for i in range(5))
    required.add("create.error-completes-at-ready")
    required.add("tooltip.owner-lifetime")
    required.update("places.recent-folders-" + name for name in ("merge-order", "dedup", "missing", "limit", "directories"))
    required.update("selection." + name for name in ("ctrl-toggle-removes", "ctrl-toggle-adds", "anchor-stable-range", "range-shrinks-from-anchor", "folder-range-kinds", "single-range-keeps-one"))
    required.add("browser.path-index-no-prototype-keys")
    required.add("selection.revalidation-noop")
    required.update("overwrite." + name for name in ("appears-before-return", "decline-keeps-request", "decline-keeps-name", "name-invalidates", "final-target", "case-sensitive", "regular-link", "request-scope", "batch-no-partial", "batch-decline-clears-all", "batch-all-approved", "filter-clears-approval", "folder-clears-approval"))
    required.update("overwrite.refuse-" + name for name in ("directory", "unwritable.txt", "fifo", "dangling", "directory-link"))
    required.update("extensions." + name for name in ("default-on", "append-and-display", "dotfile", "compound", "suppression",
        "existing-raw-confirm", "existing-raw", "no-guess", "allowed-alternative", "type-change-compound", "type-change-result", "type-change-selected",
        "final-target-confirm", "directory-not-retargeted", "opt-out", "opt-out-remembered", "bracket-glob", "no-wildcard-invention", "mime-suffix"))
    required.update("navigation." + name for name in ("cursor-only-keeps-selection", "cursor-only-keeps-anchor", "keyboard-toggle-adds",
        "keyboard-toggle-removes", "single-Ctrl-deselects", "single-Ctrl-keeps-one", "band-symmetric", "band-idempotent", "band-retract-restores", "band-additive",
        "modified-background-keeps", "background-clears", "single-band-ignored"))
    required.update("path-entry." + name for name in ("relative-open", "location-navigates", "history-invalidates-typed-intent", "history-does-not-accept", "literal-local-name", "quoted-multiple", "local-uri", "navigation-keeps-save-name", "typed-folder-keeps-save-leaf", "save-path-extension", "type-change-only-leaf", "missing-save-parent-keeps-input", "missing-keeps-dialog", "folder-watches-bounded"))
    required.update("completion." + name for name in ("case-prefix", "directories", "explicit-hidden", "type-filter", "literal-folder", "quoted-last-name", "inactive-invalidates"))
    required.update("completion." + name for name in ("file-uri-roundtrip", "file-uri-encoded-stem"))
    required.update("path-entry." + name for name in ("band-name-intent", "all-name-intent", "restore-name-intent", "same-selection-keeps-acceptance", "location-keeps-edited-save-name",
        "symlink-parent-open", "symlink-parent-new-save", "missing-parent-not-invented", "file-dot-not-a-file", "symlink-parent-browser"))
    required.update("extensions.unknown-" + kind + suffix for kind in ("numeric", "text") for suffix in ("-suffix-preserved", "-suffix-append"))
    required.update("operations." + name for name in ("single-owner", "rename-model-selection-name", "rename-no-overwrite", "rename-invalid", "trash-reconciles", "delete-awaits-confirmation", "delete-decline-retains", "delete-reconciles", "create-shares-owner", "navigation-retires-intents"))
    required.add("operations.rename-filtered-out-finishes")
    required.update("views." + name for name in ("owner", "defaults", "per-mode-zoom", "zoom-upper-bound", "zoom-lower-bound", "partial-wheel", "accumulated-wheel", "pixel-wheel", "column-adjacent-resize", "column-minima", "no-write-before-success", "persist-success", "next-request", "cancel-no-write", "sanitize"))
    required.update(("views.reload-process-consumer", "views.reload-process-columns"))
    required.add("views.no-arbitrary-dialog-cap")
    required.update("places." + name for name in ("editable-owner", "favorite-add", "favorite-reorder", "favorite-remove", "history-selection", "history-cursor", "drop-owner", "drop-locates-file", "drop-does-not-accept", "drop-rejects-network", "drop-rejects-many", "drop-invalid-keeps-path"))
    required.update(("places.drop-pretty-QUrl", "places.drop-pretty-consumer"))
    required.add("places.favorite-edit-completes-at-consumer")
    required.update("bookmarks." + name for name in ("add", "dedup", "reorder", "preserve-foreign-labels", "remove", "external-edits", "invalid-no-write", "permission-no-write", "symlink-preserved"))
    required.update(("bookmarks.trailing-reorder", "bookmarks.trailing-remove"))
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
    files_untouched = files_untouched and (overwrite / "protected.txt").read_text() == "ORIGINAL protected\n" and (overwrite / "other.txt").read_text() == "ORIGINAL other\n"
    files_untouched = files_untouched and not (overwrite / "new target.txt").exists() and not (overwrite / "A.txt").exists()
    files_untouched = files_untouched and (extensions / "protected.png").read_text() == "protected extension target\n"
    files_untouched = files_untouched and (extensions / "raw").read_text() == "raw existing target\n"
    files_untouched = files_untouched and sorted(p.name for p in extensions.iterdir()) == ["directory", "protected.png", "raw"]
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
