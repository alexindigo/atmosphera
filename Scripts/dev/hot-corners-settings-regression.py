#!/usr/bin/env python3
"""Hot corner settings page and configqml persistence, assigned niri VM only."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import sys

from presentation_harness import check_execution_paths, run_harness, write_receipt
from qml_probe import inject_probe, probe_owner_path


PROBE = r'''
  property int cornerSettingsStep: 0
  property var cornerSettingsPanel: null
  property var cornerSettingsExpected: ({})
  function cornerSettingsFind(item, name) {
    if (!item) return null;
    if (item.objectName === name) return item;
    for (let child of (item.children || [])) {
      let found = cornerSettingsFind(child, name);
      if (found) return found;
    }
    return null;
  }
  function cornerSettingsAssert(ok, message) {
    if (!ok) throw new Error("HOT_CORNER_SETTINGS: " + message);
  }
  property string cornerSettingsWait: ""
  function cornerSettingsWaiting(reason) {
    if (reason !== cornerSettingsWait) console.log("HOT_CORNER_SETTINGS_WAIT " + reason);
    cornerSettingsWait = reason;
  }
  function cornerSettingsAction(command) {
    return ActionRegistry.actions.find(action => action.command === command) || null;
  }
  function cornerSettingsValues() {
    const corners = Settings.data.general.hotCorners;
    return {topLeft: corners.topLeft, topRight: corners.topRight, bottomLeft: corners.bottomLeft,
            bottomRight: corners.bottomRight, delayMs: corners.delayMs};
  }
  Timer {
    interval: 100; running: true; repeat: true
    onTriggered: {
      if (!Settings.isLoaded || !ActionRegistry.ready) return shellRoot.cornerSettingsWaiting("settings/catalog");
      if (!shellRoot.cornerSettingsPanel) {
        let panel = PanelService.getPanel("settingsPanel", Quickshell.screens[0], false);
        if (!panel) return;
        shellRoot.cornerSettingsPanel = panel;
        panel.openToTab(10, 3);
        return;
      }
      let panel = shellRoot.cornerSettingsPanel;
      if (!panel.isPanelVisible || !panel.sizeAnimationComplete) return shellRoot.cornerSettingsWaiting("panel");
      let page = panel._settingsContent ? shellRoot.cornerSettingsFind(panel._settingsContent, "hotCornersSettings") : null;
      if (page && !page.visible && panel._settingsContent._pendingSubTab === 3) {
        // General is the first, already-loaded tab: a sub-tab requested while
        // opening stays pending. Request it again through the open-panel path.
        panel.openToTab(10, 3);
        return shellRoot.cornerSettingsWaiting("sub-tab re-requested");
      }
      if (!page || !page.visible) return shellRoot.cornerSettingsWaiting("page " + !!page);
      let fields = ["topLeft", "topRight", "bottomLeft", "bottomRight"].map(key => shellRoot.cornerSettingsFind(page, "hotCorner-" + key));
      let slider = shellRoot.cornerSettingsFind(page, "hotCornersDelaySlider");
      let note = shellRoot.cornerSettingsFind(page, "hotCornersNiriNote");
      if (fields.some(field => !field) || !slider || !note) return shellRoot.cornerSettingsWaiting("controls");
      try {
        const step = shellRoot.cornerSettingsStep;
        if (step === 0) {
          shellRoot.cornerSettingsAssert(JSON.stringify(shellRoot.cornerSettingsValues()) === JSON.stringify(
            {topLeft: "", topRight: "", bottomLeft: "", bottomRight: "", delayMs: 200}), "defaults " + JSON.stringify(shellRoot.cornerSettingsValues()));
          for (const key of ["topLeft", "topRight", "bottomLeft", "bottomRight"])
            shellRoot.cornerSettingsAssert(Settings.getDefaultValue("general.hotCorners." + key) === "", "schema default " + key);
          shellRoot.cornerSettingsAssert(Settings.getDefaultValue("general.hotCorners.delayMs") === 200, "schema delay default");
          shellRoot.cornerSettingsAssert(slider.from === 100 && slider.to === 1000 && slider.stepSize === 50 && slider.value === 200
                                         && slider.defaultValue === 200, "slider range/default");
          shellRoot.cornerSettingsAssert(note.visible === CompositorService.isNiri, "niri note visibility");
          for (const field of fields)
            shellRoot.cornerSettingsAssert(field.visible && field._closedText === "No action" && !field.hasValue, "empty field " + field.objectName);
          // Bounds: out-of-range writes never become the stored value.
          for (const bad of [50, 99, 1001, 5000]) {
            let refused = "";
            try { Settings.data.general.hotCorners.delayMs = bad; } catch (error) { refused = String(error); }
            shellRoot.cornerSettingsAssert(refused.includes("range") && Settings.data.general.hotCorners.delayMs === 200,
                                           "out-of-range delay " + bad + " refusal=" + refused);
          }
          for (const good of [100, 1000]) {
            Settings.data.general.hotCorners.delayMs = good;
            shellRoot.cornerSettingsAssert(Settings.data.general.hotCorners.delayMs === good, "rejected in-range delay " + good);
          }
          Settings.data.general.hotCorners.delayMs = 200;
          console.log("HOT_CORNER_SETTINGS: defaults, bounds and four fields");
        } else if (step === 1) {
          const center = shellRoot.cornerSettingsAction("atmosphera ipc controlCenter toggle");
          const awake = shellRoot.cornerSettingsAction("atmosphera ipc idleInhibitor enableFor");
          const tab = shellRoot.cornerSettingsAction("atmosphera ipc settings openTab");
          shellRoot.cornerSettingsAssert(center && awake && tab, "catalog actions missing");
          fields[0].selected(center.key);
          fields[1].selected(tab.key);
          fields[3].selected(awake.key);
          fields[2].customEntered("foo --app-id=corner-terminal");
          shellRoot.cornerSettingsExpected = {topLeft: ActionRegistry.compose(center, {}), topRight: ActionRegistry.compose(tab, {}),
            bottomLeft: "foo --app-id=corner-terminal", bottomRight: ActionRegistry.compose(awake, {}), delayMs: 200};
          shellRoot.cornerSettingsAssert(shellRoot.cornerSettingsExpected.topLeft === "atmosphera ipc controlCenter toggle"
                                         && shellRoot.cornerSettingsExpected.bottomRight === "atmosphera ipc idleInhibitor enableFor 900",
                                         "composed defaults " + JSON.stringify(shellRoot.cornerSettingsExpected));
          shellRoot.cornerSettingsAssert(JSON.stringify(shellRoot.cornerSettingsValues()) === JSON.stringify(shellRoot.cornerSettingsExpected),
                                         "chosen rows did not write " + JSON.stringify(shellRoot.cornerSettingsValues()));
          console.log("HOT_CORNER_SETTINGS: choosing rows writes the composed commands");
        } else if (step === 2) {
          // Arrow keys move the highlight only, on the action and choice fields.
          const before = JSON.stringify(shellRoot.cornerSettingsValues());
          const highlight = fields[0]._highlight;
          fields[0].navigate(1); fields[0].navigate(1);
          shellRoot.cornerSettingsAssert(fields[0]._highlight === highlight + 2, "highlight did not move");
          const choice = shellRoot.cornerSettingsFind(page, "hotCorner-topRight-tab");
          shellRoot.cornerSettingsAssert(choice && choice.visible, "choice argument row missing");
          choice.navigate(1); choice.navigate(1);
          shellRoot.cornerSettingsAssert(JSON.stringify(shellRoot.cornerSettingsValues()) === before, "arrows wrote " + JSON.stringify(shellRoot.cornerSettingsValues()));
          choice.selected("plugins");
          shellRoot.cornerSettingsExpected.topRight = "atmosphera ipc settings openTab plugins";
          const seconds = shellRoot.cornerSettingsFind(page, "hotCorner-bottomRight-seconds");
          shellRoot.cornerSettingsAssert(seconds && seconds.visible, "number argument row missing");
          shellRoot.cornerSettingsAssert(JSON.stringify(shellRoot.cornerSettingsValues()) === JSON.stringify(shellRoot.cornerSettingsExpected),
                                         "argument choice did not write " + JSON.stringify(shellRoot.cornerSettingsValues()));
          console.log("HOT_CORNER_SETTINGS: arrows write nothing; argument choice writes");
        } else if (step === 3) {
          fields[1].cleared();
          shellRoot.cornerSettingsExpected.topRight = "";
          shellRoot.cornerSettingsAssert(Settings.data.general.hotCorners.topRight === "", "clear did not write empty");
          shellRoot.cornerSettingsAssert(!shellRoot.cornerSettingsFind(page, "hotCorner-topRight-tab"), "cleared argument row remains");
          slider.moved(650);
          shellRoot.cornerSettingsExpected.delayMs = 650;
          shellRoot.cornerSettingsAssert(JSON.stringify(shellRoot.cornerSettingsValues()) === JSON.stringify(shellRoot.cornerSettingsExpected),
                                         "clear/slider " + JSON.stringify(shellRoot.cornerSettingsValues()));
          console.log("HOT_CORNER_SETTINGS: clear writes empty; slider writes delayMs");
          console.log("HOT_CORNER_SETTINGS_EXPECTED " + JSON.stringify(shellRoot.cornerSettingsExpected));
        } else if (step >= 4) {
          // Live writes are persisted by the owner, without any page Apply.
          if (step < 40) { shellRoot.cornerSettingsStep++; return; }
          stop();
          console.log("HOT_CORNER_SETTINGS: PASS");
          Qt.quit();
          return;
        }
        shellRoot.cornerSettingsStep++;
      } catch (error) {
        console.error(error);
        stop(); Qt.quit();
      }
    }
  }
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--workspace', type=Path, required=True)
    args = parser.parse_args()
    work = args.workspace.resolve()
    check_execution_paths(parser, work, source=args.source)
    work.mkdir()
    shell = work / 'shell'
    shutil.copytree(args.source, shell, ignore=shutil.ignore_patterns('.git', '.envrc', '.qmlls.ini', '__pycache__', '*.bak'))
    owner = probe_owner_path(shell)
    owner.write_text('import qs.Services.Actions\nimport qs.Services.Compositor\n' + inject_probe(owner.read_text(), PROBE))
    env = dict(os.environ, QT_QPA_PLATFORM='wayland', QT_QUICK_BACKEND='software', DISPLAY='')
    for key, leaf in [('HOME', 'home'), ('XDG_CONFIG_HOME', 'config'), ('XDG_DATA_HOME', 'data'),
                      ('XDG_CACHE_HOME', 'cache'), ('XDG_STATE_HOME', 'state')]:
        (work / leaf).mkdir()
        env[key] = str(work / leaf)
    settings = work / 'config' / 'atmosphera' / 'settings'
    settings.mkdir(parents=True)
    (settings / 'general.json').write_text(json.dumps({'showChangelogOnStartup': False}))
    execution = run_harness(['dbus-run-session', '--', 'qs', '-p', str(shell), '--no-color'], work, env, 180)
    text = (work / 'shell.log').read_text()
    errors = [line for line in text.splitlines() if re.search(
        r'Failed to load configuration|TypeError:|ReferenceError:|SyntaxError:|is not a type|Error: HOT_CORNER_SETTINGS', line)]
    expected = next((json.loads(line.split('HOT_CORNER_SETTINGS_EXPECTED ', 1)[1]) for line in text.splitlines()
                     if 'HOT_CORNER_SETTINGS_EXPECTED ' in line), None)
    general = json.loads((settings / 'general.json').read_text())
    persisted = general.get('hotCorners')
    # The shard may omit values equal to their defaults; read it as the owner does.
    defaults = json.loads((shell / 'Configs/defaults.json').read_text())['general']['hotCorners']
    effective = dict(defaults, **persisted) if isinstance(persisted, dict) else None
    receipt = dict(passed='HOT_CORNER_SETTINGS: PASS' in text and not errors and expected is not None and effective == expected,
                   expected=expected, persisted=persisted, effective=effective, qml_errors=errors)
    write_receipt(work, receipt, execution)
    print(json.dumps(receipt, indent=2))
    return 0 if receipt['passed'] else 1


if __name__ == '__main__':
    sys.exit(main())
