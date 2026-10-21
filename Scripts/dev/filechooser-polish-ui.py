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
    def open_folder(folder):
        ipc("openRequest", "open", "dev.filechooser.polish", json.dumps({"current_folder": list(os.fsencode(folder) + b"\0")}))
        return wait(lambda s: s["ready"] and s["nativeActive"] and s["path"] == str(folder))
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
