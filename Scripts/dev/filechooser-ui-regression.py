#!/usr/bin/env python3
"""Real-key chooser regressions; reuses the dev harness and keyboard driver.

Runs the complete keyboard/preview/save driver, then checks two independent
app folders, cross-app recent locations, and actual places navigation.
"""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
from urllib.parse import unquote, urlsplit

from filechooser_regression import SCRIPTS, guest
from filechooser_profile import current_profile, exact_source, profile_argument
from filechooser_isolation import enter, input_command
from filechooser_icons import exercise as exercise_icons
from filechooser_selection import exercise as exercise_selection
from filechooser_overwrite import exercise as exercise_overwrite
from filechooser_extensions import exercise as exercise_extensions
from filechooser_navigation import exercise as exercise_navigation
from filechooser_paths import exercise as exercise_paths


def layout_fits(s):
    g = s["layoutGeometry"]
    def inside(rect, width, height):
        return (rect["width"] >= 0 and rect["height"] >= 0 and rect["x"] >= -.5 and rect["y"] >= -.5
                and rect["x"] + rect["width"] <= width + .5 and rect["y"] + rect["height"] <= height + .5)
    controls = [*g["header"], g["listing"], g["rail"], *g["footer"], *g.get("band", [])]
    viewport = g["entries"]["viewport"]
    return (all(inside(rect, g["width"], g["height"]) for rect in controls)
            and inside(viewport, g["listing"]["width"], g["listing"]["height"])
            # Vertical clipping while scrolling is intentional. A tile may
            # never be horizontally clipped by its viewport.
            and all(t["x"] >= viewport["x"] - .5 and t["x"] + t["width"] <= viewport["x"] + viewport["width"] + .5
                    for t in g["entries"]["tiles"]))


def main():
    enter(resource_subject=True)
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--source", type=Path, required=True)
    p.add_argument("--label", required=True)
    p.add_argument("--path-only", action="store_true", help="Run the path-entry partition; default runs every area")
    profile_argument(p)
    a = p.parse_args()
    guest()
    source = a.source.resolve()
    assert exact_source(source) and source.is_dir()
    assert re.fullmatch(r"[a-z0-9][a-z0-9.-]*", a.label)
    runtime, evidence = current_profile().runtime / a.label, current_profile().evidence / a.label
    assert not runtime.exists() and not evidence.exists()
    # filechooser-harness owns preparation, media fixtures and the qs child.
    env = dict(os.environ)
    harness = subprocess.Popen(["timeout", "860", "python3", "-B", str(SCRIPTS / "filechooser-harness.py"), "--source", str(source), "--label", a.label], env=env)
    probe = runtime / "shell/filechooser-harness.qml"
    cases = []
    complete = False
    failure = ""
    def command(argv):
        if argv[0] == "ydotool":
            argv = input_command(argv)
        return subprocess.run(["timeout", "12", *map(str, argv)], env=env, capture_output=True, text=True, check=True, timeout=18).stdout.strip()
    def ipc(member, *args):
        return command(["qs", "-p", probe, "ipc", "call", "filechooserHarness", member, *args])
    def state():
        return json.loads(ipc("state"))
    def wait(predicate, seconds=12):
        deadline = time.monotonic() + seconds
        last = None
        while time.monotonic() < deadline:
            try:
                last = state()
                if predicate(last):
                    return last
            except (subprocess.CalledProcessError, json.JSONDecodeError):
                pass
            time.sleep(.15)
        raise AssertionError("Timed out: " + json.dumps(last))
    def check(name, predicate):
        s = state()
        ok = bool(predicate(s))
        cases.append({"case": name, "pass": ok, "state": s})
        print(name, "PASS" if ok else "FAIL", flush=True)
        assert ok, name
    def key(code, mod=None):
        command(["ydotool", "key", *([f"{mod}:1"] if mod else []), f"{code}:1", f"{code}:0", *([f"{mod}:0"] if mod else [])])
        time.sleep(.2)
    def open_request(method, app, folder=None, **options):
        if folder:
            options["current_folder"] = list(os.fsencode(folder) + b"\0")
        ipc("openRequest", method, app, json.dumps(options))
        # Listing readiness can precede compositor activation of the newly
        # created window. Input requires both the native window and its initial
        # control, rather than whichever old surface is still losing focus.
        return wait(lambda s: s["ready"] and not s["settled"] and s["nativeActive"]
                    and s["focus"] == ("name" if method == "save" else "listing"))
    def focus(label):
        for _ in range(50):
            if state()["focusedControl"] == label:
                return
            key(15)
        raise AssertionError("Unreachable place: " + label)
    def choose(prefix):
        if state()["filterText"] or state()["saveFilterText"]:
            key(1)
        ipc("focusListing")
        command(["ydotool", "type", prefix])
        filtered = wait(lambda s: s["filterText"].lower() == prefix.lower() and s["count"] > 0)
        target = next(i for i, name in enumerate(filtered["names"]) if name.lower().startswith(prefix.lower()))
        ipc("focusListing"); key(102)
        for _ in range(target):
            key(106)
        key(1)
        wait(lambda s: not s["filterText"])
    def new_folder():
        command(["ydotool", "key", "29:1", "42:1", "49:1", "49:0", "42:0", "29:0"])
        return wait(lambda s: s["creatingFolder"] and s["focusedControl"] == "Folder name")
    def click_header(label):
        s = state(); g = s["layoutGeometry"]
        button = next(c for c in g["header"] if c.get("name") == label)
        x = int((1280 - g["width"]) / 2 + button["x"] + button["width"] / 2)
        y = int((800 - g["height"]) / 2 + button["y"] + button["height"] / 2)
        command(["ydotool", "click", x, y, 272, 0])
        command(["ydotool", "move", 5, 5])
    def finish():
        ipc("quit"); harness.wait(timeout=15)
        log = (evidence / "harness.log").read_text()
        errors = [l for l in log.splitlines() if re.search(r"TypeError|ReferenceError|Cannot assign|Binding loop|Failed to load configuration|Unable to assign", l)]
        cases.append({"case": "UI-runtime-errors", "pass": harness.returncode == 0 and not errors, "errors": errors})
        assert cases[-1]["pass"]
    try:
        wait(lambda s: s["ready"], 30)
        exercise_paths(runtime, evidence, command, ipc, state, wait, check, open_request, key, focus)
        if a.path_only:
            finish()
            complete = True
            return 0
        command(["grim", evidence / "header.png"])
        check("compact-toolbar-above-browser", lambda s: all(
            c["y"] + c["height"] <= s["layoutGeometry"]["rail"]["y"] + .5
            for c in s["layoutGeometry"]["header"]))
        check("toolbar-icon-slots-square", lambda s: all(not c.get("iconOnly") or abs(c["width"] - c["height"]) < .5
              for c in s["layoutGeometry"]["header"]))
        wait(lambda s: len(s["recentRows"]) > 0)
        check("one-Recent-section", lambda s: json.loads(ipc("visibleText")).count("Recent") == 1
              and "Recent locations" not in json.loads(ipc("visibleText")))
        check("recent-rail-directories-only", lambda s: all(Path(row["path"]).is_dir() for row in s["recentRows"]))
        check("recent-rail-merged-deduplicated", lambda s: len({row["path"] for row in s["recentRows"]}) == len(s["recentRows"])
              and {str(runtime / "Fieldwork"), str(runtime / "Fieldwork/References"), str(runtime / "Fieldwork/Screens")} <= {row["path"] for row in s["recentRows"]})
        command(["grim", evidence / "recent-folders.png"])
        ipc("focusListing"); key(102); key(109, 42)
        check("Shift-PageDown-extends-selection", lambda s: len(s["selected"]) > 1)
        ipc("open", "open"); wait(lambda s: s["ready"] and s["focus"] == "listing")
        exercise_overwrite(runtime, evidence, command, ipc, state, wait, check, open_request, key, focus)
        exercise_extensions(runtime, evidence, command, ipc, state, wait, check, open_request, key, focus)
        exercise_navigation(runtime, evidence, command, ipc, state, wait, check, open_request, key, focus)
        exercise_selection(runtime, evidence, command, ipc, state, wait, check, open_request, key)
        command(["ydotool", "key", "29:1", "42:1", "49:1", "49:0", "42:0", "29:0"])
        wait(lambda s: s["creatingFolder"])
        check("new-folder-shortcut-focus", lambda s: s["focusedControl"] == "Folder name")
        key(1)
        check("new-folder-Escape-cancels-only-editor", lambda s: not s["creatingFolder"] and not s["settled"])
        creation = runtime / "Creation"
        creation.mkdir(); (creation / "Taken").mkdir()
        for tag, method, options in (("open", "open", {}), ("multiple", "open", {"multiple": True}),
                                      ("folder", "open", {"directory": True}), ("save", "save", {"current_name": "draft.txt"})):
            open_request(method, "dev.filechooser.creation", str(creation), **options)
            if tag == "open":
                click_header("New folder")
                wait(lambda s: s["creatingFolder"] and s["focusedControl"] == "Folder name")
            else:
                new_folder()
            check(tag + "-new-folder-prefilled-selected", lambda s: s["folderEditor"]["name"] == "New folder" and s["folderEditor"]["selection"] == [0, 10])
            name = "Created " + tag
            command(["ydotool", "type", name]); key(28)
            wait(lambda s: s["ready"] and not s["creatingFolder"] and s["name"] == name)
            check(tag + "-new-folder-filesystem-and-cursor", lambda s: (creation / name).is_dir() and s["path"] == str(creation) and not s["settled"])
            check(tag + "-new-folder-listing-focus", lambda s: s["focus"] == "listing")
            if tag == "folder":
                check("new-folder-is-folder-selection", lambda s: s["selected"] == [str(creation / name)])
            if tag == "save":
                check("new-folder-keeps-save-name-and-does-not-enter", lambda s: s["saveName"] == "draft.txt" and s["path"] == str(creation))
        open_request("open", "dev.filechooser.creation", str(creation))
        for name, fragment in ((".", "Enter a name"), ("child/name", "Enter a name"), ("Taken", "already exists")):
            new_folder(); command(["ydotool", "type", name]); key(28)
            wait(lambda s: s["createFolderError"] != "")
            check("new-folder-error-" + name.replace("/", "-"), lambda s: fragment in s["createFolderError"] and s["creatingFolder"] and s["focusedControl"] == "Folder name")
            check("new-folder-error-controls-aligned-" + name.replace("/", "-"), lambda s: max(s["folderEditor"]["centers"]) - min(s["folderEditor"]["centers"]) < .5)
            command(["grim", evidence / ("new-folder-error-" + name.replace("/", "-") + ".png")])
            key(1)
        for i in range(80):
            (creation / f"Existing directory {i:02d}").mkdir()
        wait(lambda s: s["count"] == 85)
        new_folder(); command(["ydotool", "type", "Final folder"])
        command(["grim", evidence / "new-folder-editor.png"])
        key(28); wait(lambda s: s["ready"] and s["name"] == "Final folder" and not s["creatingFolder"])
        def cursor_contained(s):
            g = s["layoutGeometry"]["entries"]; c, v = g["cursor"], g["viewport"]
            return c["y"] >= v["y"] - .5 and c["y"] + c["height"] <= v["y"] + v["height"] + .5
        wait(cursor_contained)
        check("created-folder-scrolled-into-view", lambda s: cursor_contained(s) and s["scroll"]["y"] > 0 and s["focus"] == "listing")
        command(["grim", evidence / "new-folder-created.png"])
        denied = creation / "Read only permissions"
        denied.mkdir(); denied.chmod(0o555)
        open_request("open", "dev.filechooser.creation", str(denied))
        new_folder(); command(["ydotool", "type", "Denied"]); key(28)
        wait(lambda s: "permission" in s["createFolderError"])
        check("new-folder-permission-error-inline", lambda s: s["creatingFolder"] and not (denied / "Denied").exists() and not s["settled"])
        key(1)
        ipc("open", "open"); wait(lambda s: s["ready"] and s["focus"] == "listing")
        ipc("focusListing")
        command(["ydotool", "type", "nOtEs"])
        wait(lambda s: s["filterText"] == "nOtEs" and s["names"] == ["Field notes.md"])
        check("typing-filters-case-insensitive-substring", lambda s: s["focusedControl"] == "Filter names" and not s["settled"])
        command(["grim", evidence / "filter-substring.png"])
        key(1)
        wait(lambda s: s["filterText"] == "" and s["count"] == 11)
        check("Escape-clears-filter-before-cancel", lambda s: not s["settled"])
        key(33, 29); command(["ydotool", "type", "no-match-xyz"])
        wait(lambda s: s["count"] == 0)
        check("filter-empty-state", lambda s: 'No matches for "no-match-xyz"' in json.loads(ipc("visibleText")))
        command(["grim", evidence / "filter-no-matches.png"])
        key(1); key(33, 29); command(["ydotool", "type", "ref"])
        wait(lambda s: s["names"] == ["References"])
        check("filter-includes-only-matching-folders", lambda s: s["count"] == 1)
        key(38, 29); command(["ydotool", "type", str(runtime / "Fieldwork/References")]); key(28)
        wait(lambda s: s["ready"] and s["path"].endswith("/References"))
        check("navigation-clears-filter", lambda s: s["filterText"] == "" and not s["settled"])
        open_request("open", "dev.filechooser.filters", str(runtime / "Fieldwork"), filters=[["Images", [[0, "*.png"]]]])
        key(33, 29); command(["ydotool", "type", "notes"])
        wait(lambda s: s["filterText"] == "notes" and s["count"] == 0)
        check("name-filter-intersects-type-filter", lambda s: s["filter"] == "Images")
        ipc("open", "save")
        wait(lambda s: s["ready"] and s["focus"] == "name")
        check("save-prefill-does-not-filter", lambda s: s["count"] == 11 and s["saveFilterEnabled"] and not s["saveFilterText"])
        command(["ydotool", "type", "Unknown"])
        wait(lambda s: s["saveFilterText"] == "Unknown" and s["names"] == ["Unknown.bin"])
        check("save-edit-filters-by-stem", lambda s: s["saveName"] == "Unknown.md")
        command(["grim", evidence / "save-name-filter.png"])
        key(33, 29); command(["ydotool", "type", "notes"])
        wait(lambda s: s["count"] == 0)
        check("header-and-save-filters-intersect", lambda s: s["filterText"] == "notes" and s["saveFilterText"] == "Unknown")
        key(1); wait(lambda s: not s["filterText"] and not s["saveFilterText"])
        check("Escape-clears-filter-without-losing-save-name", lambda s: not s["settled"] and s["saveName"] == "Unknown.md")
        focus("Filter by name"); key(57)
        check("save-filter-toggle-off", lambda s: not s["saveFilterEnabled"] and s["count"] == 11)
        focus("Save"); key(28); wait(lambda s: s["settled"])
        ipc("open", "save"); wait(lambda s: s["ready"] and not s["settled"])
        check("save-filter-toggle-remembered", lambda s: not s["saveFilterEnabled"])
        focus("Filter by name"); key(57)
        focus("File name"); key(30, 29); command(["ydotool", "type", "Remember filter.md"])
        focus("Save"); key(28); wait(lambda s: s["settled"])
        ipc("open", "open")
        wait(lambda s: s["ready"] and not s["settled"])
        keyboard_output = current_profile().evidence / (a.label + "-keyboard")
        subprocess.run(["timeout", "360", "python3", "-B", str(SCRIPTS / "filechooser-harness-drive.py"),
                        "--runtime", str(runtime), "--output", str(keyboard_output)], env=env, check=True, timeout=370)
        keyboard = json.loads((keyboard_output / "result.json").read_text())
        cases.extend(keyboard["cases"])
        assert keyboard["complete"] and keyboard["status"] == "green"
        # F6: app identity, order, wrapping and the footer's independent row.
        metadata_label = "Keep original location, camera metadata and color profiles"
        band_choices = [["quality", "Image quality", [["original", "Original"], ["compact", "Compact"]], "original"],
                        ["metadata", metadata_label, [], "true"]]
        band_filters = [["All files", [[0, "*"]]]]
        def footer_row(s):
            g = s["bottomGeometry"]
            controls = g["footer"]
            return (len(controls) >= 3 and max(c["center"] for c in controls) - min(c["center"] for c in controls) < .5
                    and all(c["x"] >= 0 and c["x"] + c["width"] <= g["width"] for c in controls)
                    and all(a["x"] + a["width"] <= b["x"] + .5 for a, b in zip(controls, controls[1:])))
        def capture(name):
            command(["grim", evidence / ("F6-" + name + ".png")])
            (evidence / ("F6-" + name + ".json")).write_text(json.dumps(state(), indent=2))
        for method in ("open", "save"):
            for app in ("dev.filechooser.Fieldwork", ""):
                open_request(method, app, str(runtime / "Fieldwork"), current_name="New field notes.md",
                             choices=band_choices, filters=band_filters)
                tag = method + ("-app" if app else "-anonymous")
                check(tag + "-identity", lambda s: s["appOptionsLabel"] == ("Options from Fieldwork" if app else "Options from the app")
                      and bool(s["appIcon"]) == bool(app))
                # Include the optional count in open-mode geometry.
                ipc("focusListing")
                if method == "open":
                    choose("Field")
                    wait(lambda s: len(s["selected"]) == 1)
                key(15)
                check(tag + "-Tab-listing-to-band", lambda s: s["focusedControl"] == "Image quality")
                key(57); key(108); key(28)
                check(tag + "-selected-value-not-elided", lambda s: s["choices"]["quality"] == "compact" and s["choicesFit"])
                key(15)
                check(tag + "-Tab-band-request-order", lambda s: s["focusedControl"] == metadata_label)
                key(15)
                check(tag + "-Tab-band-to-footer", lambda s: s["focusedControl"] == "File type")
                key(15)
                check(tag + "-Tab-footer-cancel", lambda s: s["focusedControl"] == "Cancel")
                key(15)
                check(tag + "-Tab-footer-accept", lambda s: s["focusedControl"] == ("Open" if method == "open" else "Save"))
                check(tag + "-default-footer-row", footer_row)
                check(tag + "-default-all-controls-contained", layout_fits)
                default = state()["bottomGeometry"]
                capture(tag)
                narrow = max(720, state()["layoutGeometry"]["minimumWidth"])
                ipc("panelWidth", str(narrow))
                wait(lambda s: s["bottomGeometry"]["width"] == narrow and s["bottomGeometry"]["bandHeight"] > default["bandHeight"])
                check(tag + "-narrow-footer-row", footer_row)
                check(tag + "-narrow-all-controls-contained", layout_fits)
                check(tag + "-band-wraps", lambda s: max(s["choiceCenters"]) - min(s["choiceCenters"]) > .5)
                capture(tag + "-narrow")
                ipc("panelWidth", "0"); ipc("panelHeight", "0")
                wait(lambda s: s["layoutGeometry"]["width"] == s["layoutGeometry"]["minimumWidth"]
                     and s["layoutGeometry"]["height"] == s["layoutGeometry"]["minimumHeight"])
                check(tag + "-minimum-all-controls-contained", layout_fits)
                check(tag + "-minimum-footer-row", footer_row)
                check(tag + "-minimum-full-dropdown-labels", lambda s: s["dropdownsFit"])
                capture(tag + "-minimum")
        open_request("open", "dev.filechooser.Fieldwork", str(runtime / "Fieldwork"))
        check("no-choices-no-band", lambda s: s["bottomGeometry"]["bandHeight"] == 0)
        ipc("focusListing"); key(15)
        check("no-band-listing-to-footer", lambda s: s["focusedControl"] == "Cancel")
        capture("no-choices")
        ipc("open", "open")
        wait(lambda s: s["ready"] and not s["settled"])
        choose("Unknown"); key(57)
        wait(lambda s: s["preview"] and s["rendered"] == "info")
        check("unknown-kind-info-card", lambda s: s["kind"] == "none" and s["name"] == "Unknown.bin")
        key(1)
        check("unknown-kind-Escape", lambda s: not s["preview"] and not s["settled"])
        base = runtime / "Fieldwork"
        first, second = base / "References", base / "Screens"
        (first / "Only app A.txt").write_text("app A\n")
        (second / "Only app B.txt").write_text("app B\n")
        for app, folder, name in (("dev.filechooser.appA", first, "Save A.txt"), ("dev.filechooser.appB", second, "Save B.txt")):
            open_request("save", app, str(folder), current_name=name)
            key(28)
            wait(lambda s: s["settled"])
            check(app + "-save-consumer", lambda s: s["replies"] == [{"response": 0, "results": {"uris": [(folder / name).as_uri()], "writable": True, "choices": []}}])
        open_request("open", "dev.filechooser.appA")
        check("app-A-remembered-folder-and-listing", lambda s: s["path"] == str(first) and s["names"] == ["Only app A.txt"])
        open_request("open", "dev.filechooser.appB")
        check("app-B-independent-folder-and-listing", lambda s: s["path"] == str(second) and s["names"] == ["Only app B.txt"])
        check("cross-app-recent-locations", lambda s: s["recentLocations"][:2] == [str(second), str(first)])
        open_request("open", "dev.filechooser.appA", accept_label="Choose this")
        choose("Only")
        wait(lambda s: s["selected"] == [str(first / "Only app A.txt")])
        focus("Choose this")
        check("accept-label-rendered-native-control", lambda s: s["focusedControl"] == "Choose this")
        key(28); wait(lambda s: s["settled"])
        check("custom-accept-control-consumer", lambda s: s["replies"][0]["response"] == 0 and s["replies"][0]["results"]["uris"] == [(first / "Only app A.txt").as_uri()])
        # Restore B as most recent, keeping the fallback assertion independent
        # of the preceding explicit app-A acceptance.
        open_request("save", "dev.filechooser.appB", str(second), current_name="Save B again.txt")
        key(28); wait(lambda s: s["settled"])
        open_request("open", "dev.filechooser.thirdApp")
        check("new-app-shared-fallback", lambda s: s["path"] == str(second) and s["names"] == ["Only app B.txt"])
        # Both headings are in the actual places rail. Real Tab/Enter must take
        # its intent all the way to FileBrowser's visible listing.
        focus("Documents"); key(28)
        wait(lambda s: s["ready"] and s["path"] == str(first))
        check("standard-place-keyboard-to-listing", lambda s: s["names"] == ["Only app A.txt"])
        focus("Pictures"); key(28)
        wait(lambda s: s["ready"] and s["path"] == str(second))
        check("pictures-place-keyboard-to-listing", lambda s: s["names"] == ["Only app B.txt"])
        focus("References"); key(28)
        wait(lambda s: s["ready"] and s["path"] == str(first))
        check("recent-location-keyboard-to-listing", lambda s: s["names"] == ["Only app A.txt"])
        check("places-and-recent-file-data", lambda s: any(p["kind"] == "home" for p in s["places"]) and any(p["path"] == str(first) for p in s["places"]) and any(p["path"] == str(base / "Field notes.md") for p in s["recentFiles"]))
        focus("Fieldwork"); key(28)
        wait(lambda s: s["ready"] and s["path"] == str(base))
        check("recent-folder-place-to-listing", lambda s: "Field notes.md" in s["names"] and not s["settled"])
        ipc("focusListing")
        choose("Field")
        wait(lambda s: s["selected"] == [str(base / "Field notes.md")])
        key(28)
        wait(lambda s: s["settled"])
        check("recent-file-consumer", lambda s: s["replies"][0]["response"] == 0 and s["replies"][0]["results"]["uris"] == [(base / "Field notes.md").as_uri()])
        # Keep these outside Fieldwork so the existing exact listing/count
        # fixtures remain stable. Navigate with real listing keys; ASCII
        # type-ahead selects résumé without relying on ydotool Unicode typing.
        paths = runtime / "Escaped paths"
        paths.mkdir()
        for name in ("With space", "résumé", "hash#name", "percent%20literal", "question?mark"):
            (paths / name).mkdir()
            (paths / name / "Picked.txt").write_text("consumer in " + name + "\n")
        for case, name, prefix in (("space-folder", "With space", "With"), ("unicode-folder", "résumé", "r"), ("hash-folder", "hash#name", "hash"), ("percent-folder", "percent%20literal", "percent"), ("question-folder", "question?mark", "question")):
            open_request("open", "dev.filechooser.paths", str(paths))
            choose(prefix)
            wait(lambda s: s["name"] == name)
            key(28)
            wait(lambda s: s["ready"] and s["path"] == str(paths / name))
            check(case + "-navigate", lambda s: s["status"] == "ready" and not s["error"] and not s["settled"])
            check(case + "-listing", lambda s: s["names"] == ["Picked.txt"])
            key(102); key(28)
            wait(lambda s: s["settled"])
            def consumed(s):
                if len(s["replies"]) != 1 or s["replies"][0]["response"] != 0:
                    return False
                uris = s["replies"][0]["results"]["uris"]
                return (uris == [(paths / name / "Picked.txt").as_uri()]
                        and Path(unquote(urlsplit(uris[0]).path)).read_text() == "consumer in " + name + "\n")
            check(case + "-pick-consumer", consumed)
        for method in ("open", "save"):
            for view in ("grid", "list"):
                open_request(method, "dev.filechooser.layout", str(base), current_name="New layout.txt",
                             filters=[["All files", [[0, "*"]]]],
                             choices=[["quality", "Quality", [["original", "Original"], ["compact", "Compact"]], "original"],
                                      ["metadata", "Keep metadata", [], "true"]])
                ipc(view)
                wait(lambda s: s["view"] == view)
                time.sleep(.2)
                prefix = method + "-" + view
                check(prefix + "-1100-layout-contained", layout_fits)
                ipc("panelWidth", "0"); ipc("panelHeight", "0")
                wait(lambda s: s["layoutGeometry"]["width"] == s["layoutGeometry"]["minimumWidth"]
                     and s["layoutGeometry"]["height"] == s["layoutGeometry"]["minimumHeight"])
                check(prefix + "-minimum-layout-contained", layout_fits)
                check(prefix + "-minimum-full-dropdown-labels", lambda s: s["dropdownsFit"])
                check(prefix + "-refuses-subminimum-size", lambda s: s["layoutGeometry"]["minimumWidth"] > 0
                      and s["layoutGeometry"]["minimumHeight"] > 0)
                command(["grim", evidence / ("layout-" + prefix + "-minimum.png")])
                (evidence / ("layout-" + prefix + "-minimum.json")).write_text(json.dumps(state(), indent=2))
                key(1); wait(lambda s: s["settled"])
        exercise_icons(source, runtime, evidence, command, ipc, state, wait, check, open_request)
        finish()
        complete = True
    except Exception as error:
        failure = repr(error)
        raise
    finally:
        if harness.poll() is None:
            try:
                ipc("quit"); harness.wait(timeout=15)
            except Exception as error:
                failure += " graceful quit: " + repr(error)
        if evidence.exists():
            (evidence / "result.json").write_text(json.dumps({"passed": complete and all(c["pass"] for c in cases), "complete": complete, "cases": cases, "failure": failure, "harness_exit": harness.poll()}, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
