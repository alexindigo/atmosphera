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

from filechooser_regression import ROOT, SCRIPTS, guest


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--source", type=Path, required=True)
    p.add_argument("--label", required=True)
    a = p.parse_args()
    guest()
    source = a.source.resolve()
    assert source.is_relative_to(ROOT / "sources") and source.is_dir()
    assert re.fullmatch(r"[a-z0-9][a-z0-9.-]*", a.label)
    runtime, evidence = ROOT / "runtime" / a.label, ROOT / "evidence" / a.label
    assert not runtime.exists() and not evidence.exists()
    # filechooser-harness owns preparation, media fixtures and the qs child.
    env = dict(os.environ, TMPDIR=str(ROOT / "tmp"), XDG_RUNTIME_DIR="/run/user/1000", WAYLAND_DISPLAY="wayland-1",
               YDOTOOL_SOCKET=str(ROOT / "runtime" / (a.label + ".input.sock")))
    input_log = (ROOT / "evidence" / (a.label + "-input.log")).open("w")
    inputd = subprocess.Popen(["sudo", "-n", "env", "TMPDIR=" + env["TMPDIR"], "timeout", "840", "ydotoold",
                              "--socket-path=" + env["YDOTOOL_SOCKET"], "--socket-perm=0666"], env=env, stdout=input_log, stderr=subprocess.STDOUT)
    harness = subprocess.Popen(["timeout", "860", "python3", "-B", str(SCRIPTS / "filechooser-harness.py"), "--source", str(source), "--label", a.label], env=env)
    probe = runtime / "shell/filechooser-harness.qml"
    cases = []
    complete = False
    failure = ""
    def command(argv):
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
    try:
        wait(lambda s: s["ready"], 30)
        keyboard_output = ROOT / "evidence" / (a.label + "-keyboard")
        subprocess.run(["timeout", "360", "python3", "-B", str(SCRIPTS / "filechooser-harness-drive.py"),
                        "--runtime", str(runtime), "--output", str(keyboard_output), "--input-socket", env["YDOTOOL_SOCKET"]], env=env, check=True, timeout=370)
        keyboard = json.loads((keyboard_output / "result.json").read_text())
        cases.extend(keyboard["cases"])
        assert keyboard["complete"] and keyboard["status"] == "green"
        ipc("open", "open")
        wait(lambda s: s["ready"] and not s["settled"])
        command(["ydotool", "type", "Unknown"]); key(57)
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
        ipc("focusListing"); command(["ydotool", "type", "Only"])
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
        focus("Field notes.md"); key(28)
        wait(lambda s: s["ready"] and s["path"] == str(base))
        check("recent-file-place-to-listing", lambda s: "Field notes.md" in s["names"] and not s["settled"])
        ipc("focusListing")
        command(["ydotool", "type", "Field"])
        wait(lambda s: s["selected"] == [str(base / "Field notes.md")])
        key(28)
        wait(lambda s: s["settled"])
        check("recent-file-consumer", lambda s: s["replies"][0]["response"] == 0 and s["replies"][0]["results"]["uris"] == [(base / "Field notes.md").as_uri()])
        # Keep these outside Fieldwork so the existing exact listing/count
        # fixtures remain stable. Navigate with real listing keys; ASCII
        # type-ahead selects résumé without relying on ydotool Unicode typing.
        paths = runtime / "Escaped paths"
        paths.mkdir()
        for name in ("With space", "résumé", "hash#name"):
            (paths / name).mkdir()
            (paths / name / "Picked.txt").write_text("consumer in " + name + "\n")
        for case, name, prefix in (("space-folder", "With space", "With"), ("unicode-folder", "résumé", "r")):
            open_request("open", "dev.filechooser.paths", str(paths))
            command(["ydotool", "type", prefix])
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
        open_request("open", "dev.filechooser.paths", str(paths))
        before = state()
        command(["ydotool", "type", "hash"])
        wait(lambda s: s["name"] == "hash#name")
        key(28)
        wait(lambda s: s["status"] == "error")
        check("hash-folder-exact-limitation-error", lambda s: s["error"] == "Can't open hash#name: folder names with #, ? or % aren't supported yet.")
        check("hash-folder-keeps-path-and-listing", lambda s: s["path"] == before["path"] and s["names"] == before["names"])
        check("hash-folder-no-stuck-load-or-settlement", lambda s: s["status"] == "error" and not s["settled"] and s["replies"] == [])
        key(38, 29)
        command(["ydotool", "type", str(paths / "With space")]); key(28)
        wait(lambda s: s["ready"] and s["path"] == str(paths / "With space"))
        check("hash-folder-valid-navigation-recovers", lambda s: not s["error"] and s["names"] == ["Picked.txt"])
        key(1); wait(lambda s: s["settled"])
        def layout_fits(s):
            g = s["layoutGeometry"]
            def inside(rect, width, height):
                return (rect["width"] >= 0 and rect["height"] >= 0 and rect["x"] >= -.5 and rect["y"] >= -.5
                        and rect["x"] + rect["width"] <= width + .5 and rect["y"] + rect["height"] <= height + .5)
            controls = [*g["header"], g["listing"], g["rail"], *g["footer"], *g.get("band", [])]
            viewport = g["entries"]["viewport"]
            return (all(inside(rect, g["width"], g["height"]) for rect in controls)
                    and inside(viewport, g["listing"]["width"], g["listing"]["height"])
                    # Vertical clipping while scrolling is intentional. A tile
                    # may never be horizontally clipped by its viewport.
                    and all(t["x"] >= viewport["x"] - .5 and t["x"] + t["width"] <= viewport["x"] + viewport["width"] + .5
                            for t in g["entries"]["tiles"]))
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
                check(prefix + "-refuses-subminimum-size", lambda s: s["layoutGeometry"]["minimumWidth"] > 0
                      and s["layoutGeometry"]["minimumHeight"] > 0)
                command(["grim", evidence / ("layout-" + prefix + "-minimum.png")])
                (evidence / ("layout-" + prefix + "-minimum.json")).write_text(json.dumps(state(), indent=2))
                key(1); wait(lambda s: s["settled"])
        ipc("quit"); harness.wait(timeout=15)
        log = (evidence / "harness.log").read_text()
        errors = [l for l in log.splitlines() if re.search(r"TypeError|ReferenceError|Cannot assign|Binding loop|Failed to load configuration|Unable to assign", l)]
        cases.append({"case": "UI-runtime-errors", "pass": harness.returncode == 0 and not errors, "errors": errors})
        assert cases[-1]["pass"]
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
        inputd.terminate()
        inputd.wait(timeout=8)
        input_log.close()
        if evidence.exists():
            (evidence / "result.json").write_text(json.dumps({"passed": complete and all(c["pass"] for c in cases), "complete": complete, "cases": cases, "failure": failure, "harness_exit": harness.poll()}, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
