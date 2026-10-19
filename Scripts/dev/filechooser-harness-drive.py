#!/usr/bin/env python3
"""Exercise F2's dev harness with real evdev keys and retain full captures."""

import argparse
import json
import os
from pathlib import Path
import subprocess
import time

ROOT = Path("/home/tester/Projects/atmosphera-filechooser")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--input-socket", type=Path, required=True)
    args = parser.parse_args()
    runtime, output = args.runtime.resolve(), args.output.resolve()
    assert os.getuid() == 1000 and Path.home() == Path("/home/tester")
    assert "52:54:00:50:b3:8b" in [f.read_text().strip() for f in Path("/sys/class/net").glob("*/address")]
    assert runtime.is_relative_to(ROOT / "runtime") and output.is_relative_to(ROOT / "evidence") and not output.exists()
    output.mkdir()
    captures = runtime / "captures"
    captures.mkdir()
    assert args.input_socket.resolve().is_relative_to(ROOT / "runtime")
    env = dict(os.environ, XDG_RUNTIME_DIR="/run/user/1000", WAYLAND_DISPLAY="wayland-1", LC_ALL="en_US.UTF-8", TMPDIR=str(runtime / "profile/tmp"), YDOTOOL_SOCKET=str(args.input_socket.resolve()))
    probe = runtime / "shell/filechooser-harness.qml"
    cases = []
    images = []
    completed = False
    failure = ""

    def run(command):
        return subprocess.run(["timeout", "10", *map(str, command)], env=env, capture_output=True, text=True, check=True, timeout=15).stdout.strip()

    def ipc(method, *values):
        return run(["qs", "-p", probe, "ipc", "call", "filechooserHarness", method, *values])

    def state():
        return json.loads(ipc("state"))

    def wait(predicate, seconds=8):
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            s = state()
            if predicate(s):
                return s
            time.sleep(0.1)
        raise AssertionError(f"Timed out: {state()}")

    def check(name, predicate):
        s = state()
        ok = bool(predicate(s))
        cases.append({"case": name, "pass": ok, "state": s})
        print(name, "PASS" if ok else "FAIL", flush=True)
        if not ok:
            raise AssertionError(name)
        return s

    def key(name, modifier=None):
        code = {"Home": 102, "End": 107, "Left": 105, "Right": 106, "Up": 103, "Down": 108, "Return": 28, "space": 57, "Escape": 1, "BackSpace": 14, "Tab": 15, "a": 30, "h": 35, "l": 38}[name]
        mod = {"shift": 42, "ctrl": 29, "alt": 56}.get(modifier)
        run(["ydotool", "key", *([f"{mod}:1"] if mod else []), f"{code}:1", f"{code}:0", *([f"{mod}:0"] if mod else [])])
        time.sleep(0.15)

    def text(value):
        run(["ydotool", "type", "--", value])
        time.sleep(0.15)

    def capture(name):
        time.sleep(0.4)
        path = captures / (name + ".png")
        run(["grim", path])
        images.append({"scene": name, "path": str(path), "state": state()})

    def open_mode(mode="open"):
        ipc("open", mode)
        return wait(lambda s: s["ready"] and not s["settled"])

    def choose(prefix):
        ipc("focusListing")
        time.sleep(1.05)  # type-ahead prefix timeout is part of FileSelection.
        text(prefix)

    def focus(name):
        for _ in range(45):
            if state()["focusedControl"] == name:
                return
            key("Tab")
        raise AssertionError(f"Control not reachable: {name}")

    try:
        open_mode()
        check("initial-open-focus", lambda s: s["focus"] == "listing")
        check("presentation-locale", lambda s: s["localeName"] == "en_US")
        check("empty-selection-count-hidden", lambda s: not s["selectionCountVisible"])
        check("breadcrumb-gaps", lambda s: len(s["breadcrumbGaps"]) == 3 and all(abs(g["before"]-g["after"]) < 0.5 and 0 < g["before"] < 5 for g in s["breadcrumbGaps"]))
        check("breadcrumb-labels-fit", lambda s: all(not g["clipped"] for g in s["breadcrumbGaps"]))
        check("choice-centerline", lambda s: len(s["choiceCenters"]) == 2 and abs(s["choiceCenters"][0] - s["choiceCenters"][1]) < 0.5)
        key("Home")
        check("home-from-unset", lambda s: s["cursor"] == 0)
        key("End")
        check("end", lambda s: s["cursor"] == s["count"] - 1)
        key("Left")
        left = check("left", lambda s: s["cursor"] == s["count"] - 2)["cursor"]
        key("Right")
        check("right", lambda s: s["cursor"] == left + 1)
        key("Up")
        up = state()["cursor"]
        key("Down")
        check("up-down-grid", lambda s: up < s["cursor"])
        choose("co")
        check("type-ahead", lambda s: s["name"] == "Coast.png")
        check("open-selection-count-shown", lambda s: s["selectionCountVisible"])
        key("Right", "shift")
        check("shift-extend", lambda s: len(s["selected"]) == 2)
        key("a", "ctrl")
        check("ctrl-a", lambda s: len(s["selected"]) == 8)
        key("h", "ctrl")
        wait(lambda s: s["hidden"] and s["count"] == 12)
        check("ctrl-h-show", lambda s: s["hidden"] and s["count"] == 12)
        key("h", "ctrl")
        wait(lambda s: not s["hidden"] and s["count"] == 11)
        check("ctrl-h-hide", lambda s: not s["hidden"])
        choose("co")
        capture("open")
        for prefix, kind, scene in [("co", "image", "quick-look-image"), ("mo", "animatedImage", "quick-look-webp"), ("ti", "video", "quick-look-video"), ("fi", "text", "quick-look-text"), ("pl", "pdf", "quick-look-pdf"), ("wa", "audio", "quick-look-audio")]:
            choose(prefix)
            key("space")
            wait(lambda s: s["preview"] and s["kind"] == kind and s["rendered"] in ("ready", "info"))
            check(scene, lambda s: s["rendered"] == "ready" or kind == "pdf" and not s["pdfAvailable"] and s["rendered"] == "info")
            if kind == "animatedImage":
                frames = set()
                for _ in range(6):
                    frames.add(state()["frame"])
                    time.sleep(0.2)
                cases.append({"case": "webp-frames-advance", "pass": len(frames) > 1, "frames": sorted(frames)})
                assert len(frames) > 1
            if kind in ("video", "audio"):
                before = state()["position"]
                time.sleep(0.3)
                check(scene + "-advances", lambda s: s["position"] > before)
            capture(scene)
            key("Escape")
            check(scene + "-escape", lambda s: not s["preview"] and not s["settled"] and s["focus"] == "listing")
        choose("co")
        key("space")
        wait(lambda s: s["rendered"] == "ready")
        key("Right")
        wait(lambda s: s["preview"] and s["name"] == "Field notes.md" and s["rendered"] == "ready")
        check("preview-arrows", lambda s: s["kind"] == "text")
        key("space")
        check("space-closes-preview", lambda s: not s["preview"] and not s["settled"])
        base = state()["path"]
        key("l", "ctrl")
        check("ctrl-l", lambda s: s["pathEditing"])
        text(base + "/References")
        key("Return")
        wait(lambda s: s["ready"] and s["path"] == base + "/References")
        check("path-enter", lambda s: s["focus"] == "listing")
        key("BackSpace")
        wait(lambda s: s["ready"] and s["path"] == base)
        check("backspace-parent", lambda s: s["path"] == base)
        key("Left", "alt")
        wait(lambda s: s["ready"] and s["path"] == base + "/References")
        check("alt-left", lambda s: s["path"].endswith("/References"))
        key("Right", "alt")
        wait(lambda s: s["ready"] and s["path"] == base)
        check("alt-right", lambda s: s["path"] == base)
        choose("ref")
        key("Return")
        wait(lambda s: s["ready"] and s["path"] == base + "/References")
        check("enter-folder", lambda s: s["path"].endswith("/References"))
        key("Up", "alt")
        wait(lambda s: s["ready"] and s["path"] == base)
        check("alt-up", lambda s: s["path"] == base)
        text("/")
        check("slash-path", lambda s: s["pathEditing"])
        key("Escape")
        check("escape-path", lambda s: not s["pathEditing"] and not s["settled"])
        text("~")
        check("tilde-path", lambda s: s["pathEditing"])
        key("Escape")
        ipc("list")
        time.sleep(0.3)
        check("modified-sort", lambda s: s["view"] == "list" and s["sort"] == "modified" and s["descending"])
        check("column-alignment", lambda s: len(s["columnGeometry"]["row"]) == 5 and all(abs(a-b) < 0.5 for a, b in zip(s["columnGeometry"]["header"], s["columnGeometry"]["row"])))
        capture("list-modified")
        key("Down")
        before = state()["cursor"]
        key("Down")
        check("list-down-one", lambda s: s["cursor"] == before + 1)
        key("Up")
        check("list-up-one", lambda s: s["cursor"] == before)
        focus("Name")
        key("Return")
        check("name-header-sorts", lambda s: s["sort"] == "name")
        focus("Modified")
        key("Return")
        check("modified-header-sorts", lambda s: s["sort"] == "modified" and not s["descending"])
        key("Return")
        check("modified-header-reverses", lambda s: s["descending"])
        before = state()["cursor"]
        key("Home")
        check("header-focus-isolated", lambda s: s["focus"] == "control" and s["cursor"] == before)
        ipc("failFolder")
        wait(lambda s: bool(s["error"]))
        check("inline-error-keeps-list", lambda s: s["path"] == base and s["count"] == 11 and not s["settled"])
        capture("error")
        open_mode("empty")
        wait(lambda s: s["count"] == 0)
        capture("empty")
        key("h", "ctrl")
        wait(lambda s: s["count"] == 1)
        check("empty-show-hidden", lambda s: s["hidden"])
        open_mode("save")
        check("initial-save-focus", lambda s: s["focus"] == "name" and s["nameSelection"] == [0, 11])
        check("save-count-hidden", lambda s: not s["selectionCountVisible"])
        capture("save")
        choose("fi")
        check("save-selected-count-hidden", lambda s: len(s["selected"]) == 1 and not s["selectionCountVisible"])
        focus("File name")
        key("a", "ctrl")
        text("A h.txt")
        key("Left")
        key("BackSpace")
        check("name-editing-isolated", lambda s: s["path"] == base and not s["hidden"] and s["saveName"] == "A h.tt")
        key("a", "ctrl")
        text("Field notes.md")
        key("Return")
        wait(lambda s: bool(s["replace"]))
        check("replace-focus", lambda s: s["focusedControl"] == "Replace")
        capture("save-replace")
        key("Return")
        wait(lambda s: s["settled"])
        check("replace-enter", lambda s: len(s["replies"]) == 1 and s["replies"][0]["response"] == 0)
        open_mode()
        choose("fi")
        key("Return")
        wait(lambda s: s["settled"])
        check("enter-file-accept", lambda s: s["replies"][0]["response"] == 0 and s["replies"][0]["results"]["uris"][0].endswith("Field%20notes.md"))
        open_mode()
        controls = []
        for _ in range(30):
            key("Tab")
            s = state()
            controls.append({"focus": s["focus"], "name": s["focusedControl"]})
        cases.append({"case": "tab-traversal", "pass": all(any(c["name"] == label for c in controls) for label in ["Cancel", "Upload", "File type", "Sort by", "Quality", "Keep metadata", "Grid view", "List view"]), "controls": controls})
        assert cases[-1]["pass"]
        focus("File type")
        key("space")
        key("Down")
        key("Return")
        wait(lambda s: s["filter"] == "Images" and s["count"] == 5)
        check("filter-menu", lambda s: s["filter"] == "Images")
        focus("Quality")
        key("space")
        key("Down")
        key("Return")
        check("choice-menu", lambda s: s["choices"]["quality"] == "compact")
        focus("Keep metadata")
        key("space")
        check("choice-checkbox", lambda s: s["choices"]["metadata"] == "false")
        choose("co")
        key("Return")
        wait(lambda s: s["settled"])
        check("choices-at-consumer", lambda s: s["replies"][0]["results"]["choices"] == [["quality", "compact"], ["metadata", "false"]] and s["replies"][0]["results"]["current_filter"][0] == "Images")
        open_mode()
        ipc("focusListing")
        key("Tab", "shift")
        check("shift-tab-leaves", lambda s: s["focus"] == "control")
        ipc("reducedMotion", "true")
        choose("co")
        key("space")
        wait(lambda s: s["rendered"] == "ready")
        check("reduced-motion", lambda s: s["motion"]["duration"] == 0 and not s["motion"]["running"] and s["motion"]["geometry"]["x"] == 18)
        key("Escape")
        ipc("reducedMotion", "false")
        key("Escape")
        wait(lambda s: s["settled"])
        check("escape-cancel", lambda s: s["replies"] == [{"response": 1, "results": {}}])
        completed = True
    except Exception as error:
        failure = str(error)
        raise
    finally:
        receipt = {"cases": cases, "captures": images, "complete": completed, "failure": failure, "status": "green" if completed and cases and all(c["pass"] for c in cases) and len(images) >= 10 else "red"}
        (output / "result.json").write_text(json.dumps(receipt, indent=2))


if __name__ == "__main__":
    main()
