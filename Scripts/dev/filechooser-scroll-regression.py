#!/usr/bin/env python3
"""Real wheel/finger input and frame observations over 2,000 mixed files."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import socket
import statistics
import time

from filechooser_isolation import enter, input_command, checked
from filechooser_profile import current_profile, exact_source, profile_argument


def main():
    os.environ["FILECHOOSER_RENDER_TIMING"] = "1"
    enter()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--label", required=True)
    parser.add_argument("--measure-only", action="store_true")
    parser.add_argument("--native-baseline", action="store_true", help="reproduce the pre-fix wheel/reuse/model contract in the disposable harness")
    profile_argument(parser)
    args = parser.parse_args()
    assert exact_source(args.source)
    profile = current_profile()
    private = checked()
    runtime, output = profile.runtime / args.label, profile.evidence / args.label
    assert not runtime.exists() and not output.exists()
    scripts = Path(__file__).parent
    clock = profile.runtime / (args.label + "-clock")
    module = clock / "FileChooserTest"
    module.mkdir(parents=True)
    def build(argv):
        result = subprocess.run(["timeout", "45", *map(str, argv)], capture_output=True, text=True, timeout=50)
        with (clock / "build.log").open("a") as log:
            log.write(result.stdout + result.stderr)
        result.check_returncode()
        return result.stdout
    flags = build(["pkg-config", "--cflags", "--libs", "Qt6Qml"]).split()
    build(["/usr/lib/qt6/moc", *[f for f in flags if f.startswith(("-I", "-D"))],
           scripts / "fixtures/filechooser-frame-clock.cpp", "-o", clock / "filechooser-frame-clock.moc"])
    build(["c++", "-std=c++17", "-shared", "-fPIC", "-O2", "-I", clock,
           scripts / "fixtures/filechooser-frame-clock.cpp", *flags, "-o", module / "libfilechooserclock.so"])
    (module / "qmldir").write_text("module FileChooserTest\nplugin filechooserclock\n")
    os.environ["QML_IMPORT_PATH"] = str(clock)
    if args.native_baseline:
        os.environ["FILECHOOSER_NATIVE_SCROLL_BASELINE"] = "1"
    harness = subprocess.Popen(["timeout", "200", "python3", "-B", str(scripts / "filechooser-harness.py"),
                                "--source", str(args.source), "--label", args.label])
    probe = runtime / "shell/filechooser-harness.qml"
    def command(argv):
        if argv[0] == "ydotool":
            argv = input_command(argv)
        return subprocess.run(["timeout", "12", *map(str, argv)], capture_output=True, text=True,
                              check=True, timeout=18).stdout.strip()
    def ipc(method, *values):
        return command(["qs", "-p", probe, "ipc", "call", "filechooserHarness", method, *values])
    def state(): return json.loads(ipc("state"))
    def pointer(line):
        # Same checked controller and persistent input owner, without spawning
        # an interpreter for each high-frequency touchpad sample.
        with socket.socket(socket.AF_UNIX) as client:
            client.settimeout(5)
            client.connect(str(private / "run/input.sock"))
            client.sendall(("pointer " + line + "\n").encode())
            assert client.recv(256) == b"OK\n"
    def wait(predicate):
        end = time.monotonic() + 35
        while time.monotonic() < end:
            try:
                result = state()
                if predicate(result): return result
            except (subprocess.CalledProcessError, json.JSONDecodeError): pass
            time.sleep(.1)
        raise AssertionError("scroll readiness timeout")
    cases = []
    try:
        wait(lambda s: s["ready"])
        folder = runtime / "Large"
        folder.mkdir()
        for i in range(2000):
            suffix, fixture = (("png", "Coast.png"), ("mp4", "Tide.mp4"), ("txt", "Read me.txt"), ("pdf", "Plan.pdf"))[i % 4]
            os.link(runtime / "Fieldwork" / fixture, folder / f"Item {i:04d}.{suffix}")
        for view in ("grid", "list"):
            for source in ("wheel", "finger"):
                options = {"current_folder": list(os.fsencode(folder) + b"\0"), "multiple": True}
                ipc("openRequest", "open", "dev.filechooser.scroll", json.dumps(options))
                wait(lambda s: s["ready"] and s["count"] == 2000 and s["nativeActive"])
                ipc(view)
                time.sleep(.6)
                geometry = state()["layoutGeometry"]
                viewport = geometry["listing"]
                # The panel is centred in this harness's fixed1280x800 output.
                x = int((1280 - geometry["width"]) / 2 + viewport["x"] + viewport["width"] / 2)
                y = int((800 - geometry["height"]) / 2 + viewport["y"] + viewport["height"] / 2)
                pointer(f"move {x} {y}")
                time.sleep(.15)
                ipc("startScrollTrace")
                time.sleep(.75)
                idle_frames = json.loads(ipc("scrollTrace"))
                idle_cpu = [f["cpuMs"] - p["cpuMs"] for p, f in zip(idle_frames, idle_frames[1:])]
                ipc("startScrollTrace")
                inputs = []
                for _ in range(30):
                    inputs.append(time.time_ns() / 1_000_000)
                    pointer(f"scroll {source} {15 if source == 'wheel' else 8}")
                    time.sleep(.016)
                pointer("scroll-stop")
                immediate = json.loads(ipc("scrollState"))
                time.sleep(.25)
                frames = json.loads(ipc("scrollTrace"))
                cpu_frames = [frame["cpuMs"] - previous["cpuMs"] for previous, frame in zip(frames, frames[1:])]
                last = state()["scroll"]
                cases.append({"view": view, "input": source, "inputs": inputs, "frames": frames,
                              "final": last, "moved": last["y"] > 0,
                              "direct": abs(last["y"] - 30 * (last["wheelStep"] if source == "wheel" else 8)) < 1,
                              "noTrailingAnimation": abs(last["y"] - immediate["y"]) < .5,
                              "guiCpuMaxMs": max(cpu_frames, default=0),
                              "idleGuiCpuMaxMs": max(idle_cpu, default=0),
                              "idleGuiCpuMedianMs": statistics.median(idle_cpu),
                              "scrollGuiCpuExtraMaxMs": max(0, max(cpu_frames, default=0) - statistics.median(idle_cpu)),
                              "idleFrames": idle_frames,
                              "reusesDelegates": last["reused"], "hiddenUnloaded": last["hiddenCount"] == 0})
        passed = all(c["moved"] and c["direct"] and c["noTrailingAnimation"] and c["reusesDelegates"] and c["hiddenUnloaded"] and c["scrollGuiCpuExtraMaxMs"] <= 16 for c in cases)
        (output / "scroll-result.json").write_text(json.dumps({"passed": passed, "cases": cases}, indent=2))
        print(json.dumps({"passed": passed, "cases": [{k: v for k, v in c.items() if k not in ("frames", "inputs", "idleFrames")} for c in cases]}, indent=2))
        return 0 if passed or args.measure_only else 1
    finally:
        if harness.poll() is None:
            ipc("quit")
        harness.wait(timeout=15)


if __name__ == "__main__":
    raise SystemExit(main())
