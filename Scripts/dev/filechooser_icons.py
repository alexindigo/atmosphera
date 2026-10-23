"""Icon consumer cases for the existing isolated chooser UI suite.

Also regenerates the mascot palette fixture from the approved reference, using
the product's own wallpaper processor, when explicitly supplied that image.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

from filechooser_isolation import enter, ROOT


def exercise(source, runtime, evidence, command, ipc, state, wait, check, open_request):
    mixed = runtime / "Icon collection"
    mixed.mkdir()
    xdg = {"DESKTOP": "Atelier", "DOCUMENTS": "Documents", "DOWNLOAD": "Incoming", "MUSIC": "Music", "PICTURES": "Pictures", "VIDEOS": "Cinema", "TEMPLATES": "Templates", "PUBLICSHARE": "Public"}
    for name in [*xdg.values(), "Ordinary", "Remote", ".Hidden folder"]:
        (mixed / name).mkdir()
    specimens = ["Image.heic", "Video.mpg", "Audio.aiff", "Readme.txt", "Notes.md", "Print.pdf", "Letter.docx", "Table.csv", "Talk.pptx", "Book.epub", "Web.html", "Code.qml", "Data.json", "Archive.tar.gz", "Executable.sh", "Disk.iso", "Font.otf", "Unknown.xyz", ".Hidden.txt"]
    for name in specimens:
        (mixed / name).write_text("icon specimen\n")
    for suffix in ("zip", "tar", "xz", "bz2", "zst", "7z", "rar", "cab"):
        (mixed / ("Archive." + suffix)).write_text("archive icon specimen\n")
    for name in ("Coast.png", "Tide.mp4"):
        shutil.copyfile(runtime / "Fieldwork" / name, mixed / name)
    for path in mixed.iterdir():
        os.utime(path, (1792260000, 1792260000))
    config = runtime / "profile/config"
    (config / "user-dirs.dirs").write_text("".join(f'XDG_{key}_DIR="{mixed / name}"\n' for key, name in xdg.items()))
    ipc("refreshPlaces")
    # The fixture tests mount classification without mounting anything or
    # touching the console's namespace. Unit cases cover real mountinfo syntax.
    remote = str(mixed / "Remote").replace(" ", "\\040")
    mounts = f"1 0 0:1 / / rw - ext4 /dev/vda rw\n2 1 0:2 / {remote} rw - cifs //fixture/share rw\n"
    command(["swaymsg", "output", "HEADLESS-1", "mode", "1280x2600"])
    palettes = {name: json.loads((source / f"Assets/ColorScheme/{name}/{name}.json").read_text()) for name in ("MacOS", "Catppuccin", "Gruvbox", "Ayu")}
    palettes["Mascot"] = json.loads((source / "Scripts/dev/fixtures/filechooser-mascot-scheme.json").read_text())["schemes"]
    open_request("open", "dev.filechooser.icons", str(mixed))
    ipc("panelWidth", "1100")
    ipc("panelHeight", "2500")
    ipc("focusListing")
    command(["ydotool", "key", "29:1", "35:1", "35:0", "29:0"])
    wait(lambda s: s["hidden"] and s["count"] == 40)
    wait(lambda s: len([p for p in s["places"] if p["kind"] == "standard"]) == 8)
    previous_faces = None
    for name, schemes in palettes.items():
        for mode in ("dark", "light"):
            scheme = {k: v for k, v in schemes[mode].items() if k.startswith("m")}
            pending = config / "colors.pending"
            pending.write_text(json.dumps(scheme)); pending.replace(config / "colors.json")
            wait(lambda s: s["palette"]["primary"].lower() == scheme["mPrimary"].lower() and s["palette"]["surface"].lower() == scheme["mSurface"].lower() and s["palette"]["standout"].lower() == scheme["mStandout"].lower())
            time.sleep(.8)
            for view in ("grid", "list"):
                ipc(view)
                ipc("iconMounts", mounts)
                wait(lambda s: s["view"] == view and len(s["icons"]) == 40 and all(i["artwork"] for i in s["icons"]))
                tag = "icons-" + name.lower() + "-" + mode + "-" + view
                size = 96 if view == "grid" else 20
                check(tag + "-geometry", lambda s: all(abs(i["artwork"]["width"] - size) < .01 and abs(i["artwork"]["height"] - size) < .01 for i in s["icons"]))
                check(tag + "-hidden-opacity", lambda s: all(i["artwork"]["opacity"] == (.5 if i["name"].startswith(".") else 1) for i in s["icons"]))
                check(tag + "-folders", lambda s: {i["descriptor"]["folder"] for i in s["icons"] if i["descriptor"]["type"] == "folder"} == {"ordinary", "network", *[k.lower() for k in xdg]})
                check(tag + "-complete-type-set", lambda s: {i["descriptor"]["type"] for i in s["icons"]} == {"folder", "image", "video", "audio", "text", "markdown", "pdf", "document", "spreadsheet", "presentation", "ebook", "web", "code", "data", "executable", "disk", "font", "unknown", "zip", "tar", "gzip", "xz", "bzip", "zstd", "sevenzip", "rar", "archive"})
                if view == "grid":
                    check(tag + "-thumbnail-tile", lambda s: all(i["thumbnailWidth"] == 96 and i["thumbnailHeight"] == 96 for i in s["icons"]))
                    check(tag + "-four-columns", lambda s: len({round(t["x"], 1) for t in s["layoutGeometry"]["entries"]["tiles"]}) == 4)
                    faces = {i["name"]: i["artwork"]["face"] for i in state()["icons"]}
                    if previous_faces:
                        check(tag + "-recolours-existing-consumer", lambda s: any(i["artwork"]["face"] != previous_faces[i["name"]] for i in s["icons"]))
                    previous_faces = faces
                if name in ("MacOS", "Mascot"):
                    command(["grim", evidence / (tag + ".png")])
                    (evidence / (tag + ".json")).write_text(json.dumps(state(), indent=2))
    command(["swaymsg", "output", "HEADLESS-1", "mode", "1280x800"])


def generate():
    enter()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--label", required=True)
    parser.add_argument("--mascot-image", type=Path, required=True)
    args = parser.parse_args()
    output = ROOT / "evidence" / args.label
    output.mkdir()
    result = subprocess.run(["timeout", "120", "python3", "-B", str(args.source / "Scripts/python/src/theming/template-processor.py"), str(args.mascot_image), "--scheme-type", "tonal-spot"], capture_output=True, text=True, check=True, timeout=130)
    raw = json.loads(result.stdout)
    mapping = {"mPrimary": "primary", "mOnPrimary": "on_primary", "mSecondary": "secondary", "mOnSecondary": "on_secondary", "mTertiary": "tertiary", "mOnTertiary": "on_tertiary", "mStandout": "standout", "mOnStandout": "on_standout", "mError": "error", "mOnError": "on_error", "mSurface": "surface", "mOnSurface": "on_surface", "mSurfaceVariant": "surface_container", "mOnSurfaceVariant": "on_surface_variant", "mOutline": "outline", "mShadow": "shadow", "mHover": "primary", "mOnHover": "on_primary"}
    fixture = {"image_sha256": hashlib.sha256(args.mascot_image.read_bytes()).hexdigest(), "source": "approved round-3 file-icons-mascot/reference.png", "method": "product template-processor.py, tonal-spot; AtmoColor template role mapping", "schemes": {mode: {role: colors[key] for role, key in mapping.items()} for mode, colors in raw.items()}}
    (output / "mascot-scheme.json").write_text(json.dumps(fixture, indent=2) + "\n")
    print(json.dumps(fixture, indent=2))


if __name__ == "__main__":
    generate()
