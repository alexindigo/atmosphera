#!/usr/bin/env python3
"""Fresh-profile Wayland regression; run only inside the assigned test VM.

Usage: python Scripts/dev/panel-cold-load.py --workspace /guest/disk/fresh-run
The private shell copy exits itself; the console shell is never restarted.
"""

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import sys
from presentation_harness import add_execution_arguments, run_harness, write_receipt


PROBE = r'''
  property int _probeStep: 0
  property int _probeOpened: 0
  property var _probePanel: null
  readonly property var _probeNames: ["setupWizardPanel", "setupWizardPanel", "clockPanel", "controlCenterPanel"]

  function _probeObserveOpen() {
    shellRoot._probeOpened++;
  }

  function _probeCheckClosed() {
    const panel = shellRoot._probePanel;
    console.log("PANEL_CANCEL " + JSON.stringify({open: panel.isPanelOpen,
      visible: panel.isPanelVisible, opened: shellRoot._probeOpened}));
    // Also destroy the owning QML context with completion still queued, as can
    // happen when an output/host disappears during content creation.
    const loader = Qt.createQmlObject('import QtQuick; Loader { active: false; anchors.fill: parent }',
      panel.parent, "panel-lifetime-loader");
    loader.setSource(Quickshell.shellDir + "/Modules/Panels/Clock/ClockPanel.qml",
      {objectName: "panel-lifetime-probe", screen: Quickshell.screens[0]});
    loader.active = true;
    loader.item.open();
    loader.active = false;
    loader.destroy();
    Qt.callLater(shellRoot._probeFinish);
  }

  function _probeFinish() {
    console.log("PANEL_LIFETIME complete");
    Qt.quit();
  }

  Timer {
    interval: 100
    running: true
    repeat: true
    onTriggered: {
      if (!shellRoot._probePanel) {
        const screen = Quickshell.screens[0];
        if (!screen)
          return;
        const panel = PanelService.getPanel(shellRoot._probeNames[shellRoot._probeStep], screen, false);
        if (!panel)
          return;
        shellRoot._probePanel = panel;
        shellRoot._probeOpened = 0;
        panel.opened.connect(shellRoot._probeObserveOpen);
        if (shellRoot._probeStep > 0)
          panel.open();
        return;
      }
      const panel = shellRoot._probePanel;
      if (!panel.isPanelOpen || !panel.isPanelVisible || !panel.sizeAnimationComplete)
        return;
      const region = panel.panelRegion;
      if (!region || region.width <= 0 || region.height <= 0)
        return;
      console.log("PANEL_RESULT " + JSON.stringify({step: shellRoot._probeStep,
        name: shellRoot._probeNames[shellRoot._probeStep], open: panel.isPanelOpen,
        visible: panel.isPanelVisible, initialized: panel.sizeAnimationComplete,
        opened: shellRoot._probeOpened,
        geometry: {x: region.x, y: region.y, width: region.width, height: region.height},
        available: {width: panel.width, height: panel.height}}));
      panel.opened.disconnect(shellRoot._probeObserveOpen);
      panel.closeImmediately();
      shellRoot._probePanel = null;
      shellRoot._probeStep++;
      if (shellRoot._probeStep === shellRoot._probeNames.length) {
        // Cancel while Loader.onLoaded's deferred completion is still pending.
        // This must not resurrect content or emit opened for a closed panel.
        const closing = PanelService.getPanel("clockPanel", Quickshell.screens[0], false);
        shellRoot._probePanel = closing;
        shellRoot._probeOpened = 0;
        closing.opened.connect(shellRoot._probeObserveOpen);
        closing.open();
        closing.closeImmediately();
        Qt.callLater(shellRoot._probeCheckClosed);
        stop();
      }
    }
  }
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--workspace", type=Path, required=True, help="fresh disk-backed guest directory")
    add_execution_arguments(parser)
    args = parser.parse_args()
    source = args.source.resolve()
    work = args.workspace.resolve()
    temp = Path(os.environ["TMPDIR"]).resolve()
    if str(work).startswith("/tmp/") or str(temp).startswith("/tmp/"):
        parser.error("use the assigned VM's disk-backed workspace and TMPDIR")
    work.mkdir()  # Preserve earlier runs instead of replacing their evidence.
    shell = work / "shell"
    shutil.copytree(source, shell, ignore=shutil.ignore_patterns(".git", "__pycache__", "*.bak"))
    main_qml = shell / "shell.qml"
    original = main_qml.read_text()
    position = original.rfind("}")
    assert position > 0 and "id: shellRoot" in original
    main_qml.write_text(original[:position] + PROBE + original[position:])
    env = dict(os.environ, QT_QPA_PLATFORM="wayland", QT_QUICK_BACKEND="software",
               XDG_CURRENT_DESKTOP="", NIRI_SOCKET="", HYPRLAND_INSTANCE_SIGNATURE="",
               SWAYSOCK="", LABWC_PID="", DISPLAY="")
    for key, leaf in (("HOME", "home"), ("XDG_CONFIG_HOME", "config"),
                      ("XDG_DATA_HOME", "data"), ("XDG_CACHE_HOME", "cache"),
                      ("XDG_STATE_HOME", "state")):
        directory = work / leaf
        directory.mkdir()
        env[key] = str(directory)
    execution = run_harness(["dbus-run-session", "--", "qs", "-p", str(shell), "--no-color"], work, env, args.budget)
    text = (work / 'shell.log').read_text(errors='replace')
    rows = [json.loads(line.split("PANEL_RESULT ", 1)[1]) for line in text.splitlines()
            if "PANEL_RESULT " in line]
    cancellations = [json.loads(line.split("PANEL_CANCEL ", 1)[1]) for line in text.splitlines()
                     if "PANEL_CANCEL " in line]
    errors = [line for line in text.splitlines() if re.search(
        r"Failed to load configuration|TypeError:|ReferenceError:|SyntaxError:|is not a type|is unavailable", line)]
    passed = (execution['exit_code'] == 0 and "Configuration Loaded" in text and not errors
              and len(rows) == 4 and all(row["opened"] > 0 for row in rows[1:])
              and cancellations == [{"open": False, "visible": False, "opened": 0}]
              and "PANEL_LIFETIME complete" in text)
    if passed:
        # Observe usable first-run content geometry, not just successful parsing
        # or an intermediate function call. The bar can offset its usable area.
        geometry = rows[0]["geometry"]
        available = rows[0]["available"]
        passed = (geometry["x"] > 0 and geometry["y"] > 0
                  and geometry["x"] + geometry["width"] <= available["width"]
                  and geometry["y"] + geometry["height"] <= available["height"])
    receipt = dict(passed=passed, exit_code=execution['exit_code'], panels=rows,
                   cancellations=cancellations, qml_errors=errors)
    write_receipt(work, receipt, execution)
    print(json.dumps(receipt, indent=2))
    return 0 if receipt['passed'] else 1


if __name__ == "__main__":
    sys.exit(main())
