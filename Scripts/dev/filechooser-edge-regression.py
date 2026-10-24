#!/usr/bin/env python3
"""Measure finished icon outlines at real 1x/2x DPR against an 8x render.

Run through the file chooser's private guest runner, like the render suite.
No renderer properties are changed: the production FileIcon is the consumer.
"""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time

from filechooser_isolation import ROOT, enter, profile_env

HERE = Path(__file__).resolve().parent


def main():
    enter()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--label", required=True)
    args = parser.parse_args()
    source = args.source.resolve()
    assert source.is_relative_to(ROOT / "sources") and re.fullmatch(r"[a-z0-9][a-z0-9.-]*", args.label)
    runtime, output = ROOT / "runtime" / args.label, ROOT / "evidence" / args.label
    runtime.mkdir(); output.mkdir()
    shell = runtime / "shell"
    shutil.copytree(source, shell, symlinks=True)
    probe = shell / "edges.qml"
    probe.write_text((HERE / "fixtures/filechooser-edges.qml").read_text())
    (shell / ".qmlls.ini").touch()
    cases = []
    images = {}
    complete, failure = False, ""
    try:
        for scale in (1, 2, 8):
            env = dict(profile_env(runtime / f"profile-{scale}"), QT_SCALE_FACTOR=str(scale))

            def command(argv, binary=False):
                return subprocess.run(["timeout", "10", *map(str, argv)], env=env, capture_output=True,
                                      text=not binary, check=True, timeout=15).stdout

            def ipc(name, *values):
                return command(["qs", "-p", probe, "ipc", "call", "filechooserEdges", name, *values])

            def wait(predicate):
                deadline = time.monotonic() + 20
                while time.monotonic() < deadline:
                    try:
                        state = json.loads(ipc("state"))
                        if predicate(state):
                            return
                    except (subprocess.CalledProcessError, json.JSONDecodeError):
                        pass
                    assert process.poll() is None, "edge probe exited"
                    time.sleep(.05)
                raise AssertionError("edge probe consumer timeout")

            log_path = output / f"scale-{scale}.log"
            with log_path.open("w") as log:
                process = subprocess.Popen(["timeout", "90", "qs", "-p", str(probe)], env=env,
                                           stdout=log, stderr=subprocess.STDOUT)
                try:
                    wait(lambda s: True)
                    for size in (96, 20):
                        for kind in ("folder", "text"):
                            ipc("configure", size, kind)
                            wait(lambda s: s["size"] == size and s["kind"] == kind and not s["saved"])
                            # Allow a frame after changing both geometry and paths.
                            time.sleep(.15)
                            path = output / f"{scale}-{size}-{kind}.png"
                            ipc("capture", path)
                            wait(lambda s: s["saved"] == str(path))
                            dimensions = command(["magick", "identify", "-format", "%wx%h", path]).strip()
                            assert dimensions == f"{size * scale}x{size * scale}", dimensions
                            images[scale, size, kind] = path
                    ipc("quit"); process.wait(timeout=10)
                    errors = re.findall(r".*(?:TypeError|ReferenceError|Cannot assign|Binding loop|Failed to load configuration).*", log_path.read_text())
                    cases.append(dict(case=f"runtime-{scale}", passed=process.returncode == 0 and not errors, errors=errors))
                finally:
                    if process.poll() is None:
                        process.terminate(); process.wait(timeout=10)
        for scale in (1, 2):
            for size in (96, 20):
                for kind in ("folder", "text"):
                    pixels = size * scale
                    actual = command(["magick", images[scale, size, kind], "-alpha", "extract", "-depth", "8", "gray:-"], True)
                    reference = command(["magick", images[8, size, kind], "-alpha", "extract", "-filter", "Box",
                                         "-resize", f"{pixels}x{pixels}!", "-depth", "8", "gray:-"], True)
                    assert len(actual) == len(reference) == pixels * pixels
                    boundary = [i for i, value in enumerate(reference) if 0 < value < 255]
                    assert boundary, "empty supersampled outline"
                    coverage = sum(0 < actual[i] < 255 for i in boundary) / len(boundary)
                    error = sum(abs(actual[i] - reference[i]) for i in boundary) / len(boundary)
                    # Binary/stair-stepped edges have zero partial coverage.
                    # Native analytic AA has a slightly wider footprint than
                    # box supersampling; keep that honest raster tolerance while
                    # requiring a smooth majority of the actual outline.
                    cases.append(dict(case=f"edge-{scale}x-{size}-{kind}", passed=coverage >= .8 and error <= 55,
                                      partial_pixels=sum(0 < v < 255 for v in actual), reference_partial=len(boundary),
                                      boundary_coverage=coverage, edge_mae=error))
        # One renderer owner for every production Shape; paths inherit their
        # container's renderer. This guards future consumers as well as icons.
        bypasses = []
        for folder in ("Widgets", "Modules", "Commons", "Services", "builtin"):
            for path in (source / folder).rglob("*.qml"):
                if path == source / "Widgets/NShape.qml":
                    continue
                if re.search(r"\bShape\s*\{|\bpreferredRendererType\s*:", path.read_text()):
                    bypasses.append(str(path.relative_to(source)))
        cases.append(dict(case="shared-shape-owner", passed=not bypasses, bypasses=bypasses))
        complete = True
    except Exception as error:
        failure = repr(error)
        raise
    finally:
        result = dict(passed=complete and all(c["passed"] for c in cases), complete=complete,
                      source=str(source), failure=failure, cases=cases)
        (output / "result.json").write_text(json.dumps(result, indent=2) + "\n")
        print(json.dumps(result, indent=2), flush=True)
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
