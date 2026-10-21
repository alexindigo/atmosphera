#!/usr/bin/env python3
"""Finished-pixel alpha, approved audio and real thumbnail crossfade contracts."""
import argparse
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import time
import xml.etree.ElementTree as ET

from filechooser_isolation import ROOT, enter, profile_env

HERE = Path(__file__).resolve().parent


def main():
    enter()
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--source", type=Path, required=True)
    p.add_argument("--label", required=True)
    a = p.parse_args()
    source = a.source.resolve()
    assert source.is_relative_to(ROOT / "sources") and re.fullmatch(r"[a-z0-9][a-z0-9.-]*", a.label)
    runtime, out = ROOT / "runtime" / a.label, ROOT / "evidence" / a.label
    runtime.mkdir(); out.mkdir()
    shell = runtime / "shell"
    shutil.copytree(source, shell, symlinks=True)
    # Baseline adaptation adds observations only, never changes its painting or
    # timings. The new fixture can therefore exercise the old exact renderer.
    entry = shell / "Modules/FileChooser/FileEntry.qml"
    text = entry.read_text()
    if "function artworkGeometry()" not in text:
        needle = "  readonly property var iconDescriptor: FileTypes.artwork(name, directory, path)"
        assert text.count(needle) == 1
        text = text.replace(needle, needle + "\n  function artworkGeometry() { return artwork.mapToItem(root, 0, 0, artwork.width, artwork.height); }")
    if "reveal: thumbnailArtwork.opacity" not in text:
        needle = "opacity: thumbnail.opacity,"
        assert text.count(needle) == 1
        text = text.replace(needle, needle + "\n imageReady: thumbnail.status === Image.Ready,\n reveal: thumbnail.opacity / (root.iconDescriptor.hidden ? .5 : 1),\n fallbackOpacity: gridIcon.visible ? gridIcon.opacity : 0,\n artworkOpacity: root.iconDescriptor.hidden ? .5 : 1,")
    entry.write_text(text)
    (out / "observed-FileEntry.qml").write_text(text)
    probe = shell / "render-probe.qml"
    probe.write_text((HERE / "fixtures/filechooser-render.qml").read_text())
    (shell / ".qmlls.ini").touch()
    env = dict(profile_env(runtime / "profile"), FILECHOOSER_RENDER_OUTPUT=str(out))
    env["MAGICK_TEMPORARY_PATH"] = env["TMPDIR"]
    defaults = json.loads((source / "Configs/defaults.json").read_text())
    defaults["general"]["showChangelogOnStartup"] = False
    (runtime / "profile/config/settings.json").write_text(json.dumps(defaults))

    def command(argv, seconds=15, binary=False, input=None):
        result = subprocess.run(["timeout", str(seconds), *map(str, argv)], env=env,
                                input=input, capture_output=True, text=not binary, check=True, timeout=seconds + 5)
        return result.stdout if binary else result.stdout.strip()
    def ipc(name, *args):
        return command(["qs", "-p", probe, "ipc", "call", "filechooserRender", name, *args])
    def state(): return json.loads(ipc("state"))
    def wait(fn, seconds=15):
        end = time.monotonic() + seconds
        last = None
        while time.monotonic() < end:
            try:
                last = state()
                if fn(last): return last
            except (subprocess.CalledProcessError, json.JSONDecodeError): pass
            time.sleep(.02)
        raise AssertionError("render consumer timeout: " + json.dumps(last))
    def configure(tag, **fields):
        ipc("configure", json.dumps(dict(tag=tag, **fields)))
        return wait(lambda s: s["tag"] == tag and s["mode"] == fields.get("mode", "icon")
                    and (s["mode"] != "entry" or (s["geometry"].get("width") == 96 and s["geometry"].get("height") == 96)))
    def capture(name):
        path = out / (name + ".png")
        ipc("capture", str(path))
        wait(lambda s: s["saved"] == str(path))
        return path
    def rgb(path, box=None):
        argv = ["magick", "-background", "black", path]
        if box:
            x, y, w, h = [int(round(v)) for v in box]
            argv += ["-crop", f"{w}x{h}+{x}+{y}", "+repage"]
        return command([*argv, "-background", "black", "-alpha", "remove", "-depth", "8", "rgb:-"], binary=True)
    def geometry(s, screen=True):
        g = s["geometry"]
        return (g["x"] + (20 if screen else 0), g["y"] + (20 if screen else 0), g["width"], g["height"])
    cases = []
    def check(name, passed, detail=None):
        cases.append(dict(case=name, **{"pass": bool(passed)}, detail=detail))
        if not passed:
            print(name, "FAIL", flush=True)
    def half(name, visible, hidden, bg):
        assert len(visible) == len(hidden) and len(visible) % 3 == 0
        delta = [abs(actual - (before + bg[i % 3]) / 2) for i, (before, actual) in enumerate(zip(visible, hidden))]
        detail = {"pixels_over_3": sum(max(delta[i:i+3]) > 3 for i in range(0, len(delta), 3)),
                  "max_channel_error": max(delta), "mean_channel_error": sum(delta) / len(delta)}
        check(name, detail["pixels_over_3"] == 0, detail)
    def color(text): return tuple(int(text[i:i+2], 16) for i in (1, 3, 5))
    groups = {"media": ["image", "video", "audio"],
              "text": ["text", "markdown", "pdf", "document", "spreadsheet", "presentation", "ebook", "web", "code", "data"],
              "rest": ["executable", "disk", "font", "unknown"],
              "archives": ["zip", "tar", "gzip", "xz", "bzip", "zstd", "sevenzip", "rar", "archive"]}
    descriptors = [dict(type=t, group=g, folder="") for g, types in groups.items() for t in types]
    descriptors += [dict(type="folder", group="folder", folder=f) for f in ("ordinary", "network", "desktop", "documents", "download", "music", "pictures", "videos", "templates", "publicshare")]
    schemes = {n: json.loads((source / f"Assets/ColorScheme/{n}/{n}.json").read_text()) for n in ("MacOS", "Catppuccin", "Gruvbox", "Ayu")}
    schemes["Mascot"] = json.loads((source / "Scripts/dev/fixtures/filechooser-mascot-scheme.json").read_text())["schemes"]
    media = runtime / "media"
    media.mkdir()
    command(["ffmpeg", "-nostdin", "-v", "error", "-f", "lavfi", "-i", "color=c=0xf04020:s=320x180:rate=8:duration=1", "-c:v", "libx264", "-threads", "1", "-pix_fmt", "yuv420p", media / "Media.mp4"])
    command(["ffmpeg", "-nostdin", "-v", "error", "-f", "lavfi", "-i", "color=c=0x20a070:s=320x180", "-frames:v", "1", media / "Media.png"])
    complete, failure = False, ""
    log = (out / "probe.log").open("w")
    process = subprocess.Popen(["timeout", "720", "qs", "-p", str(probe)], env=env, stdout=log, stderr=subprocess.STDOUT)
    try:
        wait(lambda s: s["ready"], 30)
        assert state()["uiScale"] == 1
        # Actual finished pixels for every type/folder, both optical masters,
        # two role palettes and both background modes. No opacity-property proxy.
        for scheme in ("MacOS", "Mascot"):
            for mode in ("dark", "light"):
                colors = schemes[scheme][mode]
                ipc("palette", json.dumps({k: v for k, v in colors.items() if k.startswith("m")}))
                bg = color(colors["mSurface"])
                for size in (96, 20):
                    for descriptor in descriptors:
                        tag = f"{scheme.lower()}-{mode}-{size}-{descriptor['type']}-{descriptor['folder'] or 'file'}"
                        configure(tag, size=size, descriptor=descriptor)
                        before = rgb(capture(tag + "-visible"), (20, 40, size, size))
                        ipc("hidden", "true")
                        after = rgb(capture(tag + "-hidden"), (20, 40, size, size))
                        half("finished-half-" + tag, before, after, bg)
        # Independent white masks are the approved ellipse/stem paths, not a
        # translation of the product's glyph descriptor. Check filled interiors
        # and absences outside the reference (one edge-pixel raster tolerance).
        for size, master in ((96, "grid"), (20, "list")):
            xml = ET.parse(HERE / f"fixtures/filechooser-audio-{master}.svg")
            xml.getroot().set("width", str(size)); xml.getroot().set("height", str(size))
            reference = out / f"approved-audio-{size}.svg"
            xml.write(reference)
            mask = rgb(reference)[::3]
            for scheme, modes in schemes.items():
                for mode, colors in modes.items():
                    if mode not in ("dark", "light"): continue
                    ipc("palette", json.dumps({k: v for k, v in colors.items() if k.startswith("m")}))
                    tag = f"audio-{scheme.lower()}-{mode}-{size}"
                    configure(tag, size=size, descriptor=dict(type="audio", group="media", folder=""))
                    image = rgb(capture(tag), (20, 40, size, size))
                    paint = color(state()["light"])
                    core = []; extra = []
                    for y in range(size):
                        for x in range(size):
                            # Only the lower subject field; the page's own cold
                            # edge/fold is outside this reference's responsibility.
                            if not (4/20*size <= x < 16/20*size and 8/20*size <= y < 17/20*size): continue
                            neighbors = [mask[yy*size+xx] for yy in range(max(0,y-1),min(size,y+2)) for xx in range(max(0,x-1),min(size,x+2))]
                            value = mask[y*size+x]
                            error = max(abs(image[(y*size+x)*3+c] - paint[c]) for c in range(3))
                            # At 20 px, a 252/255 reference edge pixel is not a
                            # solid interior: SVG/Shapes edge coverage differs.
                            if (min(neighbors) >= 252 if size == 96 else value == 255): core.append(error)
                            if max(neighbors) < 3 and error <= 3: extra.append([x,y])
                    check("approved-light-filled-" + tag, bool(core) and max(core) <= 3 and not extra,
                          {"core_pixels": len(core), "max_core_error": max(core) if core else None, "extra_light_pixels": extra})
        for scheme in ("MacOS", "Mascot"):
            for mode in ("dark", "light"):
                colors = schemes[scheme][mode]
                ipc("palette", json.dumps({k:v for k,v in colors.items() if k.startswith("m")}))
                for kind in ("image", "video"):
                    tag = f"thumbnail-{scheme.lower()}-{mode}-{kind}"
                    path = media / ("Media.mp4" if kind == "video" else "Media.png")
                    configure(tag, mode="entry", path=str(path), name=path.name)
                    ipc("start")
                    wait(lambda s: s["thumbnail"].get("imageReady") and s["thumbnail"].get("reveal") == 1 and not s["grabbing"])
                    ipc("stopRecording")
                    before_state = state(); before = rgb(capture(tag + "-visible"), geometry(before_state))
                    ipc("hidden", "true")
                    wait(lambda s: s["thumbnail"].get("reveal") == 1 and s["thumbnail"].get("opacity") == .5)
                    after = rgb(capture(tag + "-hidden"), geometry(state()))
                    half("finished-half-" + tag, before, after, color(colors["mSurface"]))
        ipc("palette", json.dumps({k:v for k,v in schemes["MacOS"]["dark"].items() if k.startswith("m")}))
        for hidden in (False, True):
            for reduced in (False, True):
                tag = f"crossfade-{'hidden' if hidden else 'normal'}-{'instant' if reduced else 'animated'}"
                video = media / (tag + ".mp4")
                shutil.copy2(media / "Media.mp4", video)
                configure(tag, mode="entry", path=str(video), name=video.name, hidden=hidden, reduced=reduced)
                wait(lambda s: not s["thumbnail"].get("imageReady") and s["thumbnail"].get("reveal") == 0)
                before_state = state(); before = rgb(capture(tag + "-before"), geometry(before_state))
                ipc("start")
                # Do not spawn IPC clients throughout a 150 ms render probe in
                # a one-core unit. The fixture writes its actual completed frame;
                # watching that artifact leaves the scene's frame clock alone.
                deadline = time.monotonic() + 15
                while not (out / (tag + "-complete.png")).exists():
                    assert process.poll() is None and time.monotonic() < deadline, tag
                    time.sleep(.02)
                ipc("stopRecording")
                final = state(); after = rgb(capture(tag + "-after"), geometry(final))
                (out / (tag + ".json")).write_text(json.dumps(final, indent=2))
                middle = [s for s in final["samples"] if s["ready"] and 0 < s["reveal"] < 1]
                factor = .5 if hidden else 1
                complementary = all(abs(s["fallbackOpacity"] - factor*(1-s["reveal"])) < .001 and s["fallbackOpacity"] > 0 for s in middle)
                terminal = abs(final["thumbnail"]["opacity"] - factor) < .001 and final["thumbnail"]["fallbackOpacity"] == 0
                timing = final["thumbnail"]["duration"] == 0 if reduced else final["thumbnail"]["duration"] > 0
                check(tag + "-handoff", terminal and timing and (not middle if reduced else bool(middle) and complementary),
                      {"intermediate": middle, "final": final["thumbnail"]})
                # Video letterboxing leaves a part of the type page outside the
                # final frame. A true crossfade still paints it mid-transition;
                # the former Image.Ready cut yields background-only pixels there.
                bg = color(schemes["MacOS"]["dark"]["mSurface"])
                width = int(round(final["geometry"]["width"]))
                letterbox = math.floor((final["geometry"]["height"] - final["thumbnail"]["playGeometry"]["frameHeight"]) / 2) - 2
                mask = [i for i in range(0,len(before),3) if (i//3)//width < letterbox
                        and max(abs(before[i+c]-bg[c]) for c in range(3)) > 30
                        and max(abs(after[i+c]-bg[c]) for c in range(3)) <= 3]
                rendered = []
                for frame in final["frames"]:
                    if not frame["saved"] or frame["after"].get("reveal",1) >= .9: continue
                    pixels = rgb(frame["file"], geometry(final, screen=False))
                    painted = sum(max(abs(pixels[i+c]-bg[c]) for c in range(3)) > 3 for i in mask)
                    rendered.append({"file": frame["file"], "painted_fallback_pixels": painted})
                check(tag + "-rendered-fallback", not rendered if reduced else bool(mask) and bool(rendered) and all(f["painted_fallback_pixels"] > 0 for f in rendered), rendered)
        ipc("quit"); process.wait(timeout=15)
        complete = True
    except Exception as error:
        failure = repr(error)
        raise
    finally:
        if process.poll() is None:
            ipc("quit"); process.wait(timeout=15)
        log.close()
        errors = [l for l in (out/"probe.log").read_text().splitlines() if re.search(r"TypeError|ReferenceError|Cannot assign|Binding loop|Failed to load configuration|Unable to assign", l)]
        check("render-runtime", process.returncode == 0 and not errors, errors)
        result = {"passed": complete and all(c["pass"] for c in cases), "complete": complete, "cases": cases,
                  "failure": failure, "source": str(source), "shell_exit": process.returncode}
        (out/"result.json").write_text(json.dumps(result,indent=2))
        print(json.dumps({"passed": result["passed"], "complete": complete, "cases": len(cases),
                          "failures": sum(not c["pass"] for c in cases), "failure": failure,
                          "shell_exit": process.returncode}, indent=2), flush=True)
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
