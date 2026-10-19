#!/usr/bin/env python3
"""Prepare and run the dev-only chooser window in the assigned filechooser VM.

The prepared shell exposes filechooserHarness IPC. Drive it with guest evdev
keys and capture the guest output with grim; it never registers a portal.
"""

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

from filechooser_regression import desktop_fixture

ROOT = Path("/home/tester/Projects/atmosphera-filechooser")


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--source", type=Path, required=True)
    p.add_argument("--label", required=True)
    a = p.parse_args()
    if (os.getuid() != 1000 or Path.home() != Path("/home/tester")
            or "52:54:00:50:b3:8b" not in [f.read_text().strip() for f in Path("/sys/class/net").glob("*/address")]):
        p.error("requires assigned filechooser VM")
    source = a.source.resolve()
    runtime, evidence = ROOT / "runtime" / a.label, ROOT / "evidence" / a.label
    if not source.is_relative_to(ROOT / "sources") or runtime.exists() or evidence.exists():
        p.error("requires exact source and fresh label")
    runtime.mkdir()
    evidence.mkdir()
    shell = runtime / "shell"
    shutil.copytree(source, shell, symlinks=True)
    (shell / ".qmlls.ini").touch()
    probe = shell / "filechooser-harness.qml"
    probe.write_text((source / "Scripts/dev/fixtures/filechooser-harness.qml").read_text().replace('"../../../Helpers/', '"Helpers/'))
    fixtures = runtime / "Fieldwork"
    fixtures.mkdir()
    for folder in ["Empty", "References", "Screens"]:
        (fixtures / folder).mkdir()
    (fixtures / "Field notes.md").write_text("Field notes\n\nLocation: Pacific coast\nDate: 18 October 2026\n\nWatch the light move across the headland.\nKeep the original images with these notes.\n", encoding="utf-8")
    (fixtures / "Read me.txt").write_text("A quiet place to choose the right file.\n", encoding="utf-8")
    (fixtures / ".hidden.txt").write_text("Hidden fixture\n")
    (fixtures / "Unknown.bin").write_bytes(b"\x00\xff\x01")
    (fixtures / "Empty/.hidden.txt").write_text("hidden in empty folder")

    def ffmpeg(args):
        subprocess.run(["timeout", "20", "ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-y", *args], check=True, timeout=25)

    ffmpeg(["-f", "lavfi", "-i", "color=c=0x5282a8:s=720x480,drawbox=x=0:y=300:w=720:h=180:color=0x233f4a:t=fill", "-frames:v", "1", str(fixtures / "Coast.png")])
    ffmpeg(["-f", "lavfi", "-i", "testsrc2=size=640x360:rate=6:duration=2", "-loop", "0", "-c:v", "libwebp_anim", str(fixtures / "Motion.webp")])
    ffmpeg(["-f", "lavfi", "-i", "testsrc2=size=640x360:rate=24:duration=4", "-c:v", "libx264", "-pix_fmt", "yuv420p", str(fixtures / "Tide.mp4")])
    ffmpeg(["-f", "lavfi", "-i", "sine=frequency=440:duration=6", str(fixtures / "Waves.wav")])
    # Minimal real PDF with a deterministic page; no external fixture dependency.
    stream = b"BT /F1 28 Tf 55 260 Td (Fieldwork reference) Tj 0 -42 Td /F1 14 Tf (Pacific coast - October 2026) Tj ET"
    objects = [b"<< /Type /Catalog /Pages 2 0 R >>", b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>", b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 480 340] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>", b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>", b"<< /Length " + str(len(stream)).encode() + b" >>\nstream\n" + stream + b"\nendstream"]
    pdf, offsets = b"%PDF-1.4\n", [0]
    for n, obj in enumerate(objects, 1):
        offsets.append(len(pdf))
        pdf += f"{n} 0 obj\n".encode() + obj + b"\nendobj\n"
    start = len(pdf)
    pdf += b"xref\n0 6\n0000000000 65535 f \n" + b"".join(f"{offset:010d} 00000 n \n".encode() for offset in offsets[1:])
    pdf += f"trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n{start}\n%%EOF\n".encode()
    (fixtures / "Plan.pdf").write_bytes(pdf)
    for i, path in enumerate(sorted(fixtures.iterdir())):
        os.utime(path, (1792260000 + i * 3600, 1792260000 + i * 3600))
    profile = runtime / "profile"
    for directory in ["config", "cache", "state", "data", "tmp"]:
        (profile / directory).mkdir(parents=True)
    defaults = json.loads((source / "Configs/defaults.json").read_text())
    defaults["general"]["showChangelogOnStartup"] = False
    (profile / "config/settings.json").write_text(json.dumps(defaults))
    (profile / "config/user-dirs.dirs").write_text(f'XDG_DOCUMENTS_DIR="{fixtures}/References"\nXDG_PICTURES_DIR="{fixtures}/Screens"\n')
    (profile / "data/recently-used.xbel").write_text(f'<xbel><bookmark href="{(fixtures / "Field notes.md").as_uri()}" modified="2026-10-18T12:00:00Z"/></xbel>')
    desktop_fixture(profile / "data")
    cache = profile / "cache/atmosphera"
    cache.mkdir()
    (cache / "filechooser.json").write_text(json.dumps({"recent": [str(fixtures / "References"), str(fixtures / "Screens")], "sharedFolder": str(fixtures), "appFolders": {}, "preferences": {"view": "grid", "sortKey": "name", "showHidden": False, "sortDescending": False}}))
    # The VM's login defaults to C. Use its installed UTF-8 user locale for
    # presentation fixtures; product formatting continues to use Qt.locale().
    env = dict(os.environ, TMPDIR=str(profile / "tmp"), XDG_RUNTIME_DIR="/run/user/1000", WAYLAND_DISPLAY="wayland-1", LANG="en_US.UTF-8", LC_ALL="en_US.UTF-8",
               NIRI_SOCKET=str(next(Path("/run/user/1000").glob("niri.*.sock"))), FILECHOOSER_UI_ROOT=str(fixtures),
               XDG_CONFIG_HOME=str(profile / "config"), XDG_DATA_HOME=str(profile / "data"),
               ATMOSPHERA_CONFIG_DIR=str(profile / "config") + "/", ATMOSPHERA_CACHE_DIR=str(cache) + "/",
               ATMOSPHERA_STATE_DIR=str(profile / "state") + "/", ATMOSPHERA_SETTINGS_FILE=str(profile / "config/settings.json"), ATMOSPHERA_DEBUG="0")
    (evidence / "recipe.json").write_text(json.dumps({"source": str(source), "runtime": str(runtime), "probe": str(probe), "fixtures": str(fixtures), "environment": {k: v for k, v in env.items() if k.startswith(("ATMOSPHERA_", "FILECHOOSER_", "XDG_", "WAYLAND_", "NIRI_", "TMPDIR", "LANG", "LC_"))}}, indent=2))
    with (evidence / "harness.log").open("w") as log:
        result = subprocess.run(["timeout", "--kill-after=5s", "840", "qs", "-p", str(probe)], cwd=shell, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=850)
    return result.returncode


if __name__ == "__main__":
    sys.exit(main())
