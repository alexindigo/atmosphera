#!/usr/bin/env python3
"""Edge scrolling controls and configqml persistence, assigned niri VM only."""
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
  property int edgeSettingsStep: 0
  property var edgeSettingsPanel: null
  function edgeSettingsFind(item, name) {
    if (item.objectName === name) return item;
    for (let child of (item.children || [])) {
      let found = edgeSettingsFind(child, name);
      if (found) return found;
    }
    return null;
  }
  function edgeSettingsAssert(ok, message) {
    if (!ok) throw new Error("EDGE_SETTINGS: " + message);
  }
  Timer {
    interval: 100; running: true; repeat: true
    onTriggered: {
      if (!Settings.isLoaded) return;
      if (!shellRoot.edgeSettingsPanel) {
        let panel = PanelService.getPanel("settingsPanel", Quickshell.screens[0], false);
        if (!panel) return;
        shellRoot.edgeSettingsPanel = panel;
        panel.openToTab(2, 2);
        return;
      }
      let panel = shellRoot.edgeSettingsPanel;
      if (!panel.isPanelVisible || !panel.sizeAnimationComplete) return;
      let group = panel._settingsContent ? shellRoot.edgeSettingsFind(panel._settingsContent, "edgeScrollingSettings") : null;
      if (!group) return;
      let toggle = shellRoot.edgeSettingsFind(group, "edgeScrollingToggle");
      let slider = shellRoot.edgeSettingsFind(group, "edgeScrollHoldSlider");
      let notice = shellRoot.edgeSettingsFind(group, "edgeScrollingNotice");
      if (!toggle || !slider || !notice) return;
      try {
        if (Quickshell.env("EDGE_EXPECT_NIRI") === "0") {
          shellRoot.edgeSettingsAssert(!group.visible, "controls visible outside niri");
          console.log("EDGE_SETTINGS: PASS");
          stop(); Qt.quit(); return;
        }
        if (shellRoot.edgeSettingsStep === 0) {
          const expected = Number(Quickshell.env("EDGE_EXPECT_HOLD"));
          shellRoot.edgeSettingsAssert(group.visible && toggle.enabled && slider.enabled && !notice.visible,
                                       "framed controls unavailable");
          shellRoot.edgeSettingsAssert(toggle.checked && slider.value === expected, "stored/default first delay changed");
          shellRoot.edgeSettingsAssert(slider.text === String(expected), "displayed hold time differs from value");
          shellRoot.edgeSettingsAssert(slider.description.includes(String(Math.round(expected*1.5))), "derived repeat not displayed");
          Settings.data.bar.barType = "simple";
        } else if (shellRoot.edgeSettingsStep === 1) {
          shellRoot.edgeSettingsAssert(!toggle.enabled && !slider.enabled && notice.visible,
                                       "non-framed controls/banner");
          Settings.data.bar.barType = "framed";
        } else {
          toggle.toggled(false);
          slider.moved(650);
          shellRoot.edgeSettingsAssert(!Settings.data.bar.edgeScrolling && Settings.data.bar.edgeScrollHoldMs === 650,
                                       "controls did not reach owner");
          stop();
          Settings.saveImmediate(function (result) {
            shellRoot.edgeSettingsAssert(result.status === "saved", "save did not acknowledge");
            console.log("EDGE_SETTINGS: PASS");
            Qt.quit();
          });
        }
        shellRoot.edgeSettingsStep++;
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
    parser.add_argument('--non-niri', action='store_true', help='check hidden controls in a separate compositor lifecycle')
    parser.add_argument('--stored-hold', type=int, help='prove an explicit stored value is not rescaled')
    args = parser.parse_args()
    work = args.workspace.resolve()
    check_execution_paths(parser, work, source=args.source)
    work.mkdir()
    shell = work / 'shell'
    shutil.copytree(args.source, shell, ignore=shutil.ignore_patterns('.git', '.envrc', '.qmlls.ini', '__pycache__', '*.bak'))
    owner = probe_owner_path(shell)
    owner.write_text('import qs.Services.Compositor\n' + inject_probe(owner.read_text(), PROBE))
    env = dict(os.environ, QT_QPA_PLATFORM='wayland', QT_QUICK_BACKEND='software', DISPLAY='')
    env['EDGE_EXPECT_NIRI'] = '0' if args.non_niri else '1'
    env['EDGE_EXPECT_HOLD'] = str(args.stored_hold if args.stored_hold is not None else 600)
    if args.non_niri:
        env.update(NIRI_SOCKET='', XDG_CURRENT_DESKTOP='', HYPRLAND_INSTANCE_SIGNATURE='', SWAYSOCK='', LABWC_PID='')
    for key, leaf in [('HOME', 'home'), ('XDG_CONFIG_HOME', 'config'), ('XDG_DATA_HOME', 'data'),
                      ('XDG_CACHE_HOME', 'cache'), ('XDG_STATE_HOME', 'state')]:
        (work / leaf).mkdir()
        env[key] = str(work / leaf)
    settings = work / 'config' / 'atmosphera' / 'settings'
    settings.mkdir(parents=True)
    (settings / 'general.json').write_text(json.dumps({'showChangelogOnStartup': False}))
    if args.stored_hold is not None:
        (settings / 'bar.json').write_text(json.dumps({'edgeScrollHoldMs': args.stored_hold}))
    execution = run_harness(['dbus-run-session', '--', 'qs', '-p', str(shell), '--no-color'], work, env, 180)
    text = (work / 'shell.log').read_text()
    errors = [line for line in text.splitlines() if re.search(
        r'Failed to load configuration|TypeError:|ReferenceError:|SyntaxError:|Error: EDGE_SETTINGS', line)]
    bar = json.loads((settings / 'bar.json').read_text()) if (settings / 'bar.json').exists() else {}
    persistence = args.non_niri or (bar.get('edgeScrolling') is False and bar.get('edgeScrollHoldMs') == 650)
    receipt = dict(passed='EDGE_SETTINGS: PASS' in text and not errors and persistence,
                   persisted=bar, qml_errors=errors)
    write_receipt(work, receipt, execution)
    print(json.dumps(receipt, indent=2))
    return 0 if receipt['passed'] else 1


if __name__ == '__main__':
    sys.exit(main())
