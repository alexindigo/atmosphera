#!/usr/bin/env python3
"""Real-key visible-tile, latency and second-open shared-cache regression."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

from filechooser_regression import ROOT, guest
from filechooser_isolation import enter, input_command


def main():
    enter()
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--source", type=Path, required=True)
    p.add_argument("--label", required=True)
    a = p.parse_args()
    guest()
    source = a.source.resolve()
    assert source.is_relative_to(ROOT / "sources")
    assert re.fullmatch(r"[a-z0-9][a-z0-9.-]*", a.label)
    runtime, evidence = ROOT / "runtime" / a.label, ROOT / "evidence" / a.label
    assert not runtime.exists() and not evidence.exists()
    # The regular harness owns its runtime and qs lifetime. An adjacent private
    # fixture directory keeps existing keyboard fixtures/counts unchanged.
    fixtures = ROOT / "runtime" / (a.label + "-videos")
    fixtures.mkdir()
    videos = fixtures / "Coast surveys"
    videos.mkdir()
    for index in range(30):
        subprocess.run(["timeout", "12", "ffmpeg", "-nostdin", "-v", "error", "-f", "lavfi", "-i",
                        f"testsrc2=size=320x180:rate=8:duration=1,hue=h={index * 11}",
                        "-c:v", "libx264", "-threads", "1", "-pix_fmt", "yuv420p", str(videos / f"Coast {index + 1:02}.mp4")], check=True, timeout=15)
    (videos / "00 Corrupt.mp4").write_bytes(b"corrupt video")
    for path in videos.iterdir():
        os.utime(path, (1792260000, 1792260000))
    shim = fixtures / "bin"
    shim.mkdir()
    decoder_log = fixtures / "ffmpeg.jsonl"
    (shim / "ffmpeg").write_text('#!/usr/bin/python3\nimport os,sys,json,time\n'
                                f'with open({str(decoder_log)!r}, "a") as f: f.write(json.dumps({{"time":time.monotonic(),"pid":os.getpid(),"argv":sys.argv}})+"\\n")\n'
                                'os.execv("/usr/bin/ffmpeg", ["ffmpeg", *sys.argv[1:]])\n')
    (shim / "ffmpeg").chmod(0o755)
    cache = runtime / "profile/cache"
    env = dict(os.environ, PATH=str(shim) + ":" + os.environ["PATH"])
    harness = subprocess.Popen(["timeout", "620", "python3", "-B", str(source / "Scripts/dev/filechooser-harness.py"),
                               "--source", str(source), "--label", a.label], env=env)
    probe = runtime / "shell/filechooser-harness.qml"
    cases, latencies = [], []
    complete, failure = False, ""
    def command(argv):
        if argv[0] == "ydotool":
            argv = input_command(argv)
        return subprocess.run(["timeout", "10", *map(str, argv)], env=env, capture_output=True, text=True, check=True, timeout=15).stdout.strip()
    def ipc(member, *args):
        return command(["qs", "-p", probe, "ipc", "call", "filechooserHarness", member, *args])
    def state():
        return json.loads(ipc("state"))
    def wait(predicate, seconds=20):
        deadline = time.monotonic() + seconds
        last = None
        while time.monotonic() < deadline:
            try:
                last = state()
                if predicate(last):
                    return last
            except (subprocess.CalledProcessError, json.JSONDecodeError):
                pass
            time.sleep(.025)
        raise AssertionError("Timed out: " + json.dumps(last))
    def check(name, condition, detail=None):
        cases.append({"case": name, "pass": bool(condition), "detail": detail})
        print(name, "PASS" if condition else "FAIL", flush=True)
        assert condition, name
    def key(code):
        command(["ydotool", "key", f"{code}:1", f"{code}:0"])
    def open_videos():
        ipc("openRequest", "open", "dev.filechooser.video", json.dumps({"current_folder": list(os.fsencode(videos) + b"\0"), "multiple": True, "title": "Choose a coast survey"}))
        return wait(lambda s: s["ready"] and s["nativeActive"] and s["focus"] == "listing")
    def visible_ready(s):
        tiles = s["thumbnails"]["tiles"]
        return bool(tiles) and all(tile["ready"] and tile["opacity"] == 1 if not tile["path"].endswith("00 Corrupt.mp4") else not tile["ready"] for tile in tiles)
    def capture(name):
        command(["grim", evidence / (name + ".png")])
        (evidence / (name + ".json")).write_text(json.dumps(state(), indent=2))
    def launches():
        return [json.loads(line) for line in decoder_log.read_text().splitlines()] if decoder_log.exists() else []
    try:
        wait(lambda s: s["ready"], 30)
        baseline = len(launches())
        s = open_videos()
        check("31-files-listed-before-decoding-finishes", s["count"] == 31 and any(not t["ready"] for t in s["thumbnails"]["tiles"]))
        capture("F7-icons")
        key(102)
        wait(lambda s: any(t["ready"] for t in s["thumbnails"]["tiles"]) and any(not t["ready"] and not t["path"].endswith("00 Corrupt.mp4") for t in s["thumbnails"]["tiles"]))
        capture("F7-filling")
        # Native key -> selection -> GridView scroll; measured end to end while
        # the worker is active, not just time spent writing an evdev event.
        for code in (106, 106, 106, 108, 108, 108, 108, 105):
            before = state()
            started = time.monotonic()
            key(code)
            after = wait(lambda s: s["cursor"] != before["cursor"])
            latencies.append(time.monotonic() - started)
        check("keyboard-and-scroll-latency-under-500ms", max(latencies) < .5, latencies)
        check("input-during-thumbnail-generation", len(launches()) > baseline and after["thumbnails"]["statistics"]["ffmpeg"] > 0)
        # Walk every viewport and wait for consumer Image.Ready, including the
        # last row. Offscreen files are not generated eagerly.
        key(102)
        wait(visible_ready)
        capture("F7-filled")
        first_visible = state()
        check("play-badges-inside-painted-frames", all(abs(t["playGeometry"]["right"] - t["playGeometry"]["frameWidth"]) < .5
              and abs(t["playGeometry"]["bottom"] - t["playGeometry"]["frameHeight"]) < .5 for t in first_visible["thumbnails"]["tiles"] if t["ready"]))
        check("corrupt-file-keeps-icon", any(t["path"].endswith("00 Corrupt.mp4") and not t["ready"] and not t["source"] for t in first_visible["thumbnails"]["tiles"]))
        check("only-visible-work", first_visible["thumbnails"]["statistics"]["generated"] < 30)
        for _ in range(12):
            key(108)
            wait(visible_ready)
        key(107)
        wait(visible_ready)
        cache_entries = list((cache / "thumbnails/large").glob("*.png")) + list((cache / "thumbnails/normal").glob("*.png"))
        check("all-30-video-frames-cached", len(cache_entries) == 30, len(cache_entries))
        key(1)
        wait(lambda s: s["settled"])
        before_reopen = len(launches())
        open_videos()
        key(102)
        wait(visible_ready)
        for _ in range(12):
            key(108)
            wait(visible_ready)
        key(107)
        wait(visible_ready)
        check("second-open-zero-ffmpeg-launches", len(launches()) == before_reopen, launches()[before_reopen:])
        check("second-open-consumer-cache-hits", state()["thumbnails"]["statistics"]["hit"] >= 30 and state()["thumbnails"]["statistics"]["ffmpeg"] == 0)
        ipc("list")
        wait(lambda s: s["view"] == "list")
        check("list-view-no-thumbnail-interests", not state()["thumbnails"]["tiles"])
        ipc("reducedMotion", "true")
        ipc("grid")
        key(102)
        s = wait(visible_ready)
        check("reduced-motion-instant", all(t["duration"] == 0 for t in s["thumbnails"]["tiles"]))
        capture("F7-reduced-motion")
        ipc("quit")
        harness.wait(timeout=15)
        log = (evidence / "harness.log").read_text()
        errors = [line for line in log.splitlines() if re.search(r"TypeError|ReferenceError|Cannot assign|Binding loop|Failed to load configuration|Unable to assign", line)]
        check("UI-runtime-errors", harness.returncode == 0 and not errors, errors)
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
            (evidence / "result.json").write_text(json.dumps({"passed": complete and all(c["pass"] for c in cases), "complete": complete,
                "cases": cases, "failure": failure, "latencies": latencies, "ffmpeg_launches": launches()}, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
