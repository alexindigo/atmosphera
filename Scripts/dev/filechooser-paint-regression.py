#!/usr/bin/env python3
"""Every dynamically repainted icon must equal a newly constructed picture.

Real FileIcon consumers, complete RGB over the scheme surface, both optical
masters at 1x/2x DPR. References are new Loader instances after the target state
is applied; persistent peers first finish rendering a different state. This
catches fill-node ordering and stale paint/glyph/opacity, not just silhouette AA.
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


def difference(actual, reference, size):
    """3 channel levels; only edge pixels may match within one physical pixel."""
    assert len(actual) == len(reference) == size * size * 3
    if actual == reference:
        return dict(passed=True, exact=True, pixels_over_3=0, tolerated_edges=0, nonedge_changes=0, unmatched_edges=0, examples=[])

    def neighbors(x, y, radius):
        return [(yy * size + xx) * 3 for yy in range(max(0, y-radius), min(size, y+radius+1))
                for xx in range(max(0, x-radius), min(size, x+radius+1))]

    def edge(raw, indices):
        return max(max(raw[i+c] for i in indices) - min(raw[i+c] for i in indices) for c in range(3)) > 12

    def matches(pixel, raw, indices):
        return any(max(abs(pixel[c] - raw[i+c]) for c in range(3)) <= 3 for i in indices)

    changed = tolerated = interior = unmatched = 0
    examples = []
    for i in range(0, len(actual), 3):
        delta = max(abs(actual[i+c] - reference[i+c]) for c in range(3))
        if delta <= 3:
            continue
        changed += 1
        x, y = (i // 3) % size, (i // 3) // size
        region = neighbors(x, y, 2)
        is_edge = edge(actual, region) or edge(reference, region)
        nearby = neighbors(x, y, 1)
        if is_edge and matches(actual[i:i+3], reference, nearby) and matches(reference[i:i+3], actual, nearby):
            tolerated += 1
            continue
        if is_edge:
            unmatched += 1
        else:
            interior += 1
        if len(examples) < 8:
            examples.append(dict(x=x, y=y, actual=list(actual[i:i+3]), reference=list(reference[i:i+3]), edge=is_edge))
    return dict(passed=interior == 0 and unmatched == 0, exact=False, pixels_over_3=changed,
                tolerated_edges=tolerated, nonedge_changes=interior, unmatched_edges=unmatched, examples=examples)


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
    probe = shell / "paint-probe.qml"
    probe.write_text((HERE / "fixtures/filechooser-paint.qml").read_text())
    (shell / ".qmlls.ini").touch()
    groups = {"media": ["image", "video", "audio"],
              "text": ["text", "markdown", "pdf", "document", "spreadsheet", "presentation", "ebook", "web", "code", "data"],
              "rest": ["executable", "disk", "font", "unknown"],
              "archives": ["zip", "tar", "gzip", "xz", "bzip", "zstd", "sevenzip", "rar", "archive"]}
    files = [dict(type=t, group=g, folder="") for g, types in groups.items() for t in types]
    folders = [dict(type="folder", group="folder", folder=f) for f in
               ("ordinary", "network", "desktop", "documents", "download", "music", "pictures", "videos", "templates", "publicshare")]
    descriptors = files + folders
    assert len(descriptors) == 36
    schemes = {"MacOS": json.loads((source / "Assets/ColorScheme/MacOS/MacOS.json").read_text())}
    schemes["Mascot"] = json.loads((source / "Scripts/dev/fixtures/filechooser-mascot-scheme.json").read_text())["schemes"]
    palettes = [(name, mode, {k: v for k, v in modes[mode].items() if k.startswith("m")})
                for name, modes in schemes.items() for mode in ("dark", "light")]
    rows, runtimes = [], []
    complete, failure = False, ""
    try:
        for scale in (1, 2):
            env = dict(profile_env(runtime / f"profile-{scale}"), QT_SCALE_FACTOR=str(scale))

            def command(argv, binary=False):
                return subprocess.run(["timeout", "15", *map(str, argv)], env=env, capture_output=True,
                                      text=not binary, check=True, timeout=20).stdout

            def ipc(name, *values):
                return command(["qs", "-p", probe, "ipc", "call", "filechooserPaint", name, *values]).strip()

            def wait(predicate):
                deadline = time.monotonic() + 25
                while time.monotonic() < deadline:
                    try:
                        state = json.loads(ipc("state"))
                        if predicate(state):
                            return state
                    except (subprocess.CalledProcessError, json.JSONDecodeError):
                        pass
                    assert process.poll() is None, "paint probe exited"
                    time.sleep(.03)
                raise AssertionError("paint probe consumer timeout")

            # Accommodate the complete paired sheet even at forced 2x DPR.
            command(["swaymsg", "output", "HEADLESS-1", "mode", "2800x1400"])
            log_path = output / f"scale-{scale}.log"
            with log_path.open("w") as log:
                process = subprocess.Popen(["timeout", "700", "qs", "-p", str(probe)], env=env,
                                           stdout=log, stderr=subprocess.STDOUT)
                try:
                    wait(lambda s: s["ready"])
                    generations = 0
                    for size in (96, 20):
                        for palette_index, (name, mode, colors) in enumerate(palettes):
                            for hidden in (False, True):
                                target = [dict(d, hidden=hidden) for d in descriptors]
                                for transition in ("file-folder", "type-type", "palette", "hidden"):
                                    seed, seed_colors = target, colors
                                    if transition == "file-folder":
                                        seed = [dict(files[0] if d["type"] == "folder" else folders[0], hidden=hidden) for d in descriptors]
                                    elif transition == "type-type":
                                        seed = [dict(files[(i+1) % len(files)] if i < len(files)
                                                     else folders[(i-len(files)+1) % len(folders)], hidden=hidden)
                                                for i in range(len(descriptors))]
                                    elif transition == "palette":
                                        seed_colors = palettes[(palette_index+1) % len(palettes)][2]
                                        assert seed_colors != colors
                                    else:
                                        seed = [dict(d, hidden=not hidden) for d in descriptors]
                                    tag = f"{scale}x-{size}-{name.lower()}-{mode}-{'hidden' if hidden else 'normal'}-{transition}"
                                    path = output / (tag + ".png")
                                    ipc("exercise", json.dumps(dict(tag=tag, file=str(path), seedFile=str(output / (tag + "-seed.png")), size=size,
                                        seed=dict(descriptors=seed, colors=seed_colors), target=dict(descriptors=target, colors=colors))))
                                    state = wait(lambda s: s["completed"] == tag)
                                    generations += 1
                                    assert state["saved"] and state["seedRendered"] and state["count"] == 36
                                    assert state["warmCreations"] == 36 and state["coldCreations"] == generations * 36, state
                                    width, height = 6 * (2 * size + 8) * scale, 6 * (size + 8) * scale
                                    dimensions = command(["magick", "identify", "-format", "%wx%h", path]).strip()
                                    assert dimensions == f"{width}x{height}", dimensions
                                    image = command(["magick", path, "-alpha", "off", "-depth", "8", "rgb:-"], True)
                                    assert len(image) == width * height * 3
                                    pixels = size * scale

                                    def tile(index, cold):
                                        x = ((index % 6) * (2 * size + 8) + (size + 8 if cold else 0)) * scale
                                        y = (index // 6) * (size + 8) * scale
                                        return b"".join(image[((y+dy)*width+x)*3:((y+dy)*width+x+pixels)*3] for dy in range(pixels))

                                    for index, descriptor in enumerate(target):
                                        observed = difference(tile(index, False), tile(index, True), pixels)
                                        direction = ("file-to-folder" if descriptor["type"] == "folder" else "folder-to-file") if transition == "file-folder" else transition
                                        rows.append(dict(case=tag+"-"+descriptor["type"]+"-"+(descriptor["folder"] or "file"),
                                                         transition=direction, scale=scale, size=size, scheme=name, mode=mode,
                                                         descriptor=descriptor, capture=path.name, **observed))
                                    (output / "progress.json").write_text(json.dumps(dict(batch=tag, comparisons=len(rows), failures=sum(not r["passed"] for r in rows))))
                    ipc("quit"); process.wait(timeout=10)
                    errors = re.findall(r".*(?:TypeError|ReferenceError|Cannot assign|Binding loop|Failed to load configuration|Unable to assign).*", log_path.read_text())
                    runtimes.append(dict(scale=scale, passed=process.returncode == 0 and not errors, errors=errors))
                finally:
                    if process.poll() is None:
                        process.terminate(); process.wait(timeout=10)
        assert len(rows) == 2 * 2 * 4 * 2 * 4 * 36 == 4608
        assert {r["transition"] for r in rows} == {"file-to-folder", "folder-to-file", "type-type", "palette", "hidden"}
        complete = True
    except Exception as error:
        failure = repr(error)
        raise
    finally:
        result = dict(passed=complete and all(r["passed"] for r in rows+runtimes), complete=complete,
                      source=str(source), failure=failure, comparisons=len(rows), failures=sum(not r["passed"] for r in rows),
                      tolerance=dict(channel=3, edge_radius_physical_pixels=1, interior_channel=3), runtimes=runtimes, cases=rows)
        (output / "result.json").write_text(json.dumps(result, indent=2) + "\n")
        print(json.dumps({k: v for k, v in result.items() if k != "cases"}, indent=2), flush=True)
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
