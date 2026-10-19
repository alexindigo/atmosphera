#!/usr/bin/env python3
"""Reproduce the six review defects on an exact 899a57e34 source delivery.

Run this script from the new source with --source pointing at the old source.
Only read-only aliases are added to the disposable runtime picker. Product
logic is unchanged; expected contract failures are retained individually.
"""

import argparse
import json
from pathlib import Path
import sys
import time

from filechooser_regression import Run, SCRIPTS


STATE = '''    function state(): string {
      var entries = Object.entries(FileChooserPortal.activeRequests).map(pair => {
        var entry = pair[1];
        var picker = root.descendants(entry.dialog).find(child => typeof child.openFilePicker === "function");
        return {handle: pair[0], title: entry.dialog.options.title, mode: entry.dialog.mode,
          options: entry.dialog.options, status: picker && picker.probeStatus === 1 ? "ready" : "loading",
          label: picker ? picker.probeAccept.text : "", targets: picker ? picker.probeTargets.count : -1,
          path: picker ? picker.currentPath : "", names: picker ? Array.from({length: picker.probeListing.count}, (_, i) => picker.probeListing.get(i).fileName) : []};
      });
      return JSON.stringify({requests: entries, accepts: root.accepts, cancels: root.cancels, saved: root.saved, icon: settings.valueIconSource, iconType: settings.valueIconType,
        legacy: {path: legacy.currentPath, folder: String(legacy.probeFolder), status: legacy.probeStatus,
          names: Array.from({length: legacy.probeListing.count}, (_, i) => legacy.probeListing.get(i).fileName)}});
    }
    function cancel(): void { FileChooserPortal.closeRequest(Object.keys(FileChooserPortal.activeRequests)[0]); }
    function acceptLegacy(): void { var d = Object.values(FileChooserPortal.activeRequests)[0].dialog; root.descendants(d).find(child => typeof child.openFilePicker === "function").probeAccept.clicked(); }
    function legacyOpen(): void { page.visible = true; legacy.openFilePicker(); }
    function legacyNavigate(path: string): void { legacy.navigateTo(path); }
    function legacyRemember(path: string): void { legacy.close(); legacy.currentPath = path; legacy.openFilePicker(); }
    function legacyClose(): void { legacy.close(); }
'''


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--source", type=Path, required=True)
    p.add_argument("--label", required=True)
    a = p.parse_args()
    r = Run(a.source, a.label)
    defects = []
    def contract(name, passes, detail):
        defects.append({"case": name, "contract_pass": bool(passes), "defect_reproduced": not passes, "detail": detail})
        r.check(name + "-reproduced", not passes, detail)
    try:
        picker = r.shell / "Widgets/AtmoFilePicker.qml"
        text = picker.read_text()
        marker = "  id: root\n"
        button = "\n            icon: Icon.filepickerCheck\n"
        assert text.count(marker) == 1 and text.count(button) == 1
        text = text.replace(marker, marker + "  // Read-only observation aliases, disposable runtime only.\n  readonly property alias probeListing: filteredModel\n  readonly property alias probeFolder: folderModel.folder\n  readonly property alias probeStatus: folderModel.status\n  readonly property alias probeTargets: targetListModel\n  readonly property alias probeAccept: probeAcceptControl\n", 1)
        text = text.replace(button, "\n            id: probeAcceptControl\n            icon: Icon.filepickerCheck\n", 1)
        picker.write_text(text)
        (r.output / "legacy-observation.patch.json").write_text(json.dumps({"source": str(a.source), "file": "Widgets/AtmoFilePicker.qml", "aliases": ["probeListing", "probeFolder", "probeStatus", "probeTargets", "probeAccept"], "behavior_changes": False}, indent=2))
        qml = (SCRIPTS / "fixtures/filechooser-portal.qml").read_text()
        qml = qml.replace("import qs.Services.Files", "import qs.Widgets")
        start, end = qml.index("    function state(): string {"), qml.index("    function settingsOpen(): void")
        qml = qml[:start] + STATE + qml[end:]
        qml = qml.replace("    ScrollView {", '    AtmoFilePicker { id: legacy; initialPath: Quickshell.env("FILECHOOSER_FIXTURES") }\n    ScrollView {', 1)
        r.start(qml=qml)
        r.ipc("settingsOpen")
        r.wait(lambda s: s["cancels"] == 1)
        s = r.state()
        contract("icon-preserved-until-accept", s["icon"] == "/original.svg" and s["iconType"] == "icons", s)
        wire = [json.loads(l) for l in (r.output / "wire.jsonl").read_text().splitlines() if l.startswith("{")]
        calls = [x for x in wire if x.get("type") == "method_call" and x.get("member") == "OpenFile"]
        contract("internal-Desktop-name-and-roundtrip", any(x.get("destination") == "org.freedesktop.portal.Desktop" for x in calls) and s["accepts"] == 1,
                 {"calls": calls, "consumer": s})
        names = ["second #.txt", "first.txt"]
        proc, out = r.call("SaveFiles", current_folder=str(r.fixtures), files=names)
        s = r.state()["requests"][0]
        r.ipc("acceptLegacy")
        # Run.result waits for the helper's exit before reading its final receipt.
        data = r.result(proc, out)
        contract("SaveFiles-app-names-and-order", data["response"] == 0 and data["results"]["uris"] == [(r.fixtures / n).as_uri() for n in names],
                 {"request": s, "consumer": data, "supplied_names": names})
        proc, out = r.call("OpenFile", current_folder=str(r.fixtures), accept_label="Choose this")
        s = r.state()["requests"][0]
        contract("accept-label-rendered", s["label"] == "Choose this", s)
        r.ipc("cancel"); r.result(proc, out)
        other = r.runtime / "Remembered"
        other.mkdir(); (other / "Only remembered.txt").write_text("remembered\n")
        r.ipc("legacyOpen")
        r.wait(lambda s: s["legacy"]["status"] == 1 and s["legacy"]["names"] == ["Chosen.txt", "Icon.png"])
        before = r.state()["legacy"]
        r.ipc("legacyNavigate", str(r.fixtures / "Missing"))
        time.sleep(2)
        s = r.state()["legacy"]
        contract("failed-folder-keeps-path-and-listing", s["path"] == before["path"] and s["names"] == before["names"], {"before": before, "after": s})
        r.ipc("legacyNavigate", str(r.fixtures))
        r.wait(lambda s: s["legacy"]["status"] == 1 and s["legacy"]["names"] == ["Chosen.txt", "Icon.png"])
        r.ipc("legacyRemember", str(other))
        time.sleep(.7)
        s = r.state()["legacy"]
        contract("remembered-folder-drives-listing", s["path"] == str(other) and s["names"] == ["Only remembered.txt"], s)
        r.ipc("legacyClose")
        r.check("all-six-distinct-defects", len(defects) == 6 and all(d["defect_reproduced"] for d in defects))
        r.finish()
    except Exception as error:
        r.failure = repr(error)
        raise
    finally:
        (r.output / "six-defects.json").write_text(json.dumps(defects, indent=2))
        r.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
