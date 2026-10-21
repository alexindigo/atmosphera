#!/usr/bin/env python3
"""Observe the real monochrome renderer in the assigned private guest session."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import time

from filechooser_isolation import ROOT, enter, profile_env


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--label", required=True)
    parser.add_argument("--diagnose-only", action="store_true")
    args = parser.parse_args()
    source = args.source.resolve()
    assert source.is_relative_to(ROOT / "sources")
    # Exercise the candidate runner as well as its product tree. The same fixed
    # pixel check can therefore prove the historical runner red without editing it.
    spec = importlib.util.spec_from_file_location("candidate_isolation", source / "Scripts/dev/filechooser_isolation.py")
    candidate = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(candidate)
    candidate.enter()
    runtime, output = ROOT / "runtime" / args.label, ROOT / "evidence" / args.label
    runtime.mkdir(); output.mkdir()
    shell = runtime / "shell"
    shutil.copytree(source, shell, symlinks=True)
    env = profile_env(runtime / "profile")
    defaults = json.loads((source / "Configs/defaults.json").read_text())
    (runtime / "profile/config/settings.json").write_text(json.dumps(defaults))
    probe = shell / "glyph-probe.qml"
    probe.write_text('''import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI
import qs.Widgets
ShellRoot {
  id: root
  FileView {
    path: Quickshell.shellDir + "/builtin/plugins/atmosphera-icons/icons.json"
    onLoaded: IconRegistry.register("dev:atmosphera-icons", JSON.parse(text()), Quickshell.shellDir + "/builtin/plugins/atmosphera-icons")
  }
  FloatingWindow {
    id: window
    visible: true
    implicitWidth: 480
    implicitHeight: 160
    color: "#202020"
    Row {
      id: row
      x: 16; y: 16
      spacing: 16
      Repeater {
        model: ["home", "refresh", "media-play", "close"]
        Item {
          required property string modelData
          width: 64; height: 64
          AtmoIcon { anchors.centerIn: parent; icon: modelData; pointSize: 28; color: "#ffffff" }
        }
      }
    }
    Image {
      id: direct
      x: 16; y: 96; width: 32; height: 32
      source: Quickshell.shellDir + "/builtin/plugins/atmosphera-icons/svg/home.svg"
    }
  }
  IpcHandler {
    target: "glyphProbe"
    function state(): string {
      return JSON.stringify({registered: Object.keys(IconRegistry.resolved).length, directStatus: direct.status,
        entries: ["home", "refresh", "media-play", "close"].map(k => IconRegistry.resolved[k]),
        backend: Quickshell.env("QT_QUICK_BACKEND"), rhi: Quickshell.env("QSG_RHI_BACKEND")});
    }
    function quit(): void { Qt.quit(); }
  }
}
''')
    def command(argv):
        return subprocess.run(["timeout", "10", *map(str, argv)], env=env, capture_output=True,
                              text=True, check=True, timeout=15).stdout.strip()
    def ipc(name): return command(["qs", "-p", probe, "ipc", "call", "glyphProbe", name])
    with (output / "shell.log").open("w") as log:
        app = subprocess.Popen(["timeout", "60", "qs", "-p", str(probe)], env=env, stdout=log, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 20
            while True:
                try:
                    state = json.loads(ipc("state"))
                    if state["registered"] and state["directStatus"] == 1:
                        break
                except (subprocess.CalledProcessError, json.JSONDecodeError):
                    pass
                assert app.poll() is None and time.monotonic() < deadline, "diagnostic scene startup failed"
                time.sleep(.1)
            time.sleep(1)
            command(["grim", output / "glyphs.png"])
            (output / "state.json").write_text(json.dumps(state, indent=2))
            print(json.dumps(state), flush=True)
            ipc("quit")
            app.wait(timeout=10)
            assert app.returncode == 0
        finally:
            if app.poll() is None:
                ipc("quit"); app.wait(timeout=10)
    if args.diagnose_only:
        return 0
    fixtures = runtime / "Files"
    fixtures.mkdir()
    (fixtures / "Field notes.txt").write_text("A monochrome consumer fixture\n")
    env["FILECHOOSER_UI_ROOT"] = str(fixtures)
    text = (source / "Scripts/dev/fixtures/filechooser-harness.qml").read_text().replace('"../../../Helpers/', '"Helpers/')
    needle = '    function state(): string {'
    assert text.count(needle) == 1
    text = text.replace(needle, '''    function glyphs(): string {
      var window = windowLoader.item;
      var boxes = [];
      function visit(node) {
        if (!node.visible) return;
        if (node._resolved && node._resolved.type === "svg") {
          var rect = node.mapToItem(window.contentItem, 0, 0, node.width, node.height);
          boxes.push({source: node._resolved.source, x: rect.x, y: rect.y, width: rect.width, height: rect.height});
        }
        for (var i = 0; i < node.children.length; ++i) visit(node.children[i]);
      }
      visit(window.contentItem);
      return JSON.stringify(boxes);
    }
''' + needle)
    probe.write_text(text)
    def harness_ipc(member, *values):
        return command(["qs", "-p", probe, "ipc", "call", "filechooserHarness", member, *values])
    cases = []
    with (output / "chooser.log").open("w") as log:
        app = subprocess.Popen(["timeout", "60", "qs", "-p", str(probe)], env=env, stdout=log, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 20
            while True:
                try:
                    state = json.loads(harness_ipc("state"))
                    if state["ready"] and state["nativeActive"]:
                        break
                except (subprocess.CalledProcessError, json.JSONDecodeError):
                    pass
                assert app.poll() is None and time.monotonic() < deadline, "chooser startup failed"
                time.sleep(.1)
            time.sleep(1)
            boxes = json.loads(harness_ipc("glyphs"))
            image = output / "chooser.png"
            # The chooser layer covers the sole private output; its contentItem
            # coordinates are output coordinates. Quickshell's proxy contentItem
            # has no QML engine, so observe the finished compositor pixels instead.
            command(["grim", image])
            for name in ("filepicker-home", "filepicker-refresh", "filepicker-layout-grid", "filepicker-list"):
                matching = [b for b in boxes if b["source"].endswith("/" + name + ".svg")]
                assert matching, (name, boxes)
                box = matching[0]
                w, h = int(box["width"]), int(box["height"])
                x, y = round(box["x"]), round(box["y"])
                pixels = subprocess.run(["timeout", "10", "magick", str(image), "-crop", f"{w}x{h}+{x}+{y}", "+repage", "-depth", "8", "rgb:-"],
                                        env=env, capture_output=True, check=True, timeout=15).stdout
                colors = [tuple(pixels[i:i+3]) for i in range(0, len(pixels), 3)]
                background = max(set(colors), key=colors.count)
                ink = sum(max(abs(c[i] - background[i]) for i in range(3)) > 20 for c in colors)
                cases.append({"case": name + "-finished-pixels", "pass": ink > 8, "ink_pixels": ink, "box": box})
            (output / "result.json").write_text(json.dumps({"cases": cases, "passed": all(c["pass"] for c in cases)}, indent=2))
            print(json.dumps(cases), flush=True)
            assert all(c["pass"] for c in cases), "monochrome chooser pixels missing"
            harness_ipc("quit"); app.wait(timeout=10)
            assert app.returncode == 0
        finally:
            if app.poll() is None:
                harness_ipc("quit"); app.wait(timeout=10)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
