#!/usr/bin/env python3
"""Trial-fix consumer geometry/text in the isolated file chooser."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time

from filechooser_isolation import ROOT, enter, input_command


def main():
    enter()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--label", required=True)
    parser.add_argument("--media", action="store_true")
    args = parser.parse_args()
    source = args.source.resolve()
    runtime, output = ROOT / "runtime" / args.label, ROOT / "evidence" / args.label
    probe = runtime / "shell/filechooser-harness.qml"
    scripts = Path(__file__).resolve().parent
    harness = subprocess.Popen(["timeout", "180", "python3", "-B", str(scripts / "filechooser-harness.py"),
                                "--source", str(source), "--label", args.label])
    cases = []
    def command(argv):
        if argv[0] == "ydotool": argv = input_command(argv)
        return subprocess.run(["timeout", "10", *map(str, argv)], capture_output=True, text=True, check=True, timeout=15).stdout.strip()
    def ipc(member, *values):
        return command(["qs", "-p", probe, "ipc", "call", "filechooserHarness", member, *values])
    def state(): return json.loads(ipc("state"))
    def wait(fn, seconds=20):
        deadline = time.monotonic() + seconds
        while True:
            try:
                value = state()
                if fn(value): return value
            except (subprocess.CalledProcessError, json.JSONDecodeError): pass
            assert harness.poll() is None and time.monotonic() < deadline, "polish consumer timeout"
            time.sleep(.1)
    def check(name, condition, detail=None):
        cases.append({"case": name, "pass": bool(condition), "detail": detail})
        print(name, "PASS" if condition else "FAIL", flush=True)
        assert condition, name
    def capture(name):
        time.sleep(.25)
        command(["grim", output / (name + ".png")])
        (output / (name + ".json")).write_text(json.dumps(state(), indent=2))
        # Review-only regions stay beside the full guest capture, not in the
        # user's screenshot folder. Each region gets its own spatial pass.
        for region, geometry in {"title": "1100x57+90+30", "rail": "190x624+90+87", "toolbar": "900x55+280+87", "content": "900x570+280+142", "footer": "1100x59+90+711"}.items():
            command(["magick", output / (name + ".png"), "-crop", geometry, "+repage", output / (name + "-" + region + ".png")])
    def open_folder(folder):
        ipc("openRequest", "open", "dev.filechooser.polish", json.dumps({"current_folder": list(os.fsencode(folder) + b"\0")}))
        return wait(lambda s: s["ready"] and s["nativeActive"] and s["path"] == str(folder))
    def key(code, modifier=None):
        command(["ydotool", "key", *([f"{modifier}:1"] if modifier else []), f"{code}:1", f"{code}:0", *([f"{modifier}:0"] if modifier else [])])
        time.sleep(.15)
    def focus(name):
        for _ in range(70):
            if state()["focusedControl"] == name: return
            key(15)
        raise AssertionError("control unreachable by Tab: " + name)
    complete, failure = False, ""
    try:
        wait(lambda s: s["ready"] and s["nativeActive"], 35)
        folder = runtime / "Labels"
        folder.mkdir()
        for name in ("Short.txt", "Weekend travel itinerary.pdf", "Preferences.yaml", "Averylongunbrokenfilenamethatcannotfit.txt", "週末旅行計画書.pdf", ".extension"):
            (folder / name).write_text("Label policy fixture\n")
        open_folder(folder)
        labels = wait(lambda s: len(s["icons"]) >= 5)["icons"]
        check("labels-mixed-one-two-line-fixture", {len(x["label"]["lines"]) for x in labels} == {1, 2}, labels)
        check("labels-top-aligned", max(x["label"]["top"] for x in labels) - min(x["label"]["top"] for x in labels) < .5, labels)
        check("labels-directly-below-artwork", all(0 <= x["label"]["top"] - x["label"]["artworkBottom"] <= 10 for x in labels), labels)
        check("labels-no-token-splitting", all(all(part in x["name"] for part in x["label"]["lines"]) for x in labels), labels)
        capture("mixed-labels")
        home_folder = Path.home() / "Documents"
        home_folder.mkdir()
        open_folder(home_folder)
        check("path-inside-home", state()["breadcrumbText"] == ["Home", "Documents"], state()["breadcrumbText"])
        capture("home-path")
        open_folder(folder)
        check("path-outside-home", state()["breadcrumbText"][-1] == "Labels" and state()["breadcrumbText"][0] != "Home", state()["breadcrumbText"])
        (runtime / "profile/data/recently-used.xbel").write_text("<xbel/>")
        ipc("refreshPlaces")
        wait(lambda s: not s["recentFiles"])
        check("empty-recent-heading-hidden", "Recent" not in json.loads(ipc("visibleText")))
        capture("empty-recent-and-toolbar")
        if args.media:
            open_folder(runtime / "Fieldwork")
            for prefix, kind in (("Tide", "video"), ("Field", "text"), ("Waves", "audio"), ("Tide", "video"), ("Waves", "audio")):
                ipc("focusListing")
                time.sleep(1.05)
                command(["ydotool", "type", prefix]); key(57)
                wait(lambda s: s["preview"] and s["kind"] == kind and s["rendered"] == "ready")
                if kind in ("audio", "video"):
                    wait(lambda s: s["playback"]["playing"] and s["playback"]["position"] > 100)
                    check(kind + "-reused-request-starts", state()["playback"]["playing"])
                key(1); wait(lambda s: not s["preview"])
            for filename, kind in (("Waves", "audio"), ("Tide", "video")):
                open_folder(runtime / "Fieldwork")
                command(["ydotool", "type", filename]); key(57)
                s = wait(lambda s: s["preview"] and s["kind"] == kind and s["rendered"] == "ready" and s["playback"]["duration"] > 17000)
                check(kind + "-autoplay", s["playback"]["playing"], s["playback"])
                key(25, 29)
                paused = wait(lambda s: not s["playback"]["playing"])["playback"]["position"]
                time.sleep(.35)
                check(kind + "-pause-freezes-position", state()["playback"]["position"] == paused)
                focus("Play"); key(28)
                wait(lambda s: s["playback"]["playing"])
                check(kind + "-button-plays", state()["playback"]["playing"])
                key(25, 29); wait(lambda s: not s["playback"]["playing"])
                focus("Playback position")
                before = state()["playback"]["position"]
                key(106)
                wait(lambda s: s["playback"]["position"] > before + 500)
                check(kind + "-slider-seeks-not-next-file", state()["kind"] == kind and state()["preview"])
                before = state()["playback"]["position"]
                key(106, 29)
                wait(lambda s: s["playback"]["position"] > before + 4000)
                check(kind + "-shortcut-seeks", state()["kind"] == kind)
                focus("Volume")
                before = state()["playback"]["volume"]
                key(105)
                wait(lambda s: s["playback"]["volume"] < before - .04)
                check(kind + "-volume-slider", state()["kind"] == kind)
                before = state()["playback"]["volume"]
                key(108, 29)
                wait(lambda s: s["playback"]["volume"] < before - .04)
                check(kind + "-volume-shortcut", state()["kind"] == kind)
                rows = state()["transportGeometry"]
                # Qt rounds the15px icon beside the24px slider to a pixel;
                # their structural centers may differ by exactly half a pixel.
                check(kind + "-control-row-centerlines", len(rows) == 2 and all(max(c["center"] for c in row) - min(c["center"] for c in row) <= .5 for row in rows), rows)
                if kind == "audio":
                    p = state()["playback"]
                    check("audio-tags", [p["title"], p["artist"], p["album"]] == ["Coastal evening", "Fieldwork", "Tide studies"], p)
                    check("audio-content-sized", state()["motion"]["geometry"]["height"] < 350 and state()["motion"]["geometry"]["width"] <= 620, state()["motion"])
                    check("audio-filename-once-in-sheet", json.loads(ipc("visibleText")).count("Waves.wav") == 2)
                capture(kind + "-quick-look")
                key(57)
                wait(lambda s: not s["preview"])
                check(kind + "-Space-closes-and-stops", not state()["playback"]["playing"] and state()["playback"]["status"] == "idle" and not state()["playback"]["engineActive"])
        ipc("quit"); harness.wait(timeout=15)
        check("runtime-exit", harness.returncode == 0)
        complete = True
    except Exception as error:
        failure = repr(error)
        raise
    finally:
        if harness.poll() is None:
            ipc("quit"); harness.wait(timeout=15)
        (output / "result.json").write_text(json.dumps({"complete": complete, "cases": cases, "failure": failure}, indent=2))


if __name__ == "__main__":
    main()
