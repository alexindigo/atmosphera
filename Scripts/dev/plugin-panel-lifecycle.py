#!/usr/bin/env python3
"""Plugin panel ownership regression. Run inside an assigned Wayland test VM.

Uses real PluginPanelSlot/SmartPanel content creation, including destruction on
close. The fixture declares its behavior in its entry point just like plugins.
"""
import argparse
import json
import os
from pathlib import Path
import re
import shutil

from presentation_harness import add_execution_arguments, require_disk_backed_paths, run_harness, write_receipt


PANEL = '''import QtQuick
Item {
  property var pluginApi: null
  property var screen: null
  readonly property bool exclusiveOpen: %s
  readonly property bool exclusiveKeyboard: exclusiveOpen
  readonly property bool closeOnClickOutside: exclusiveOpen
  readonly property bool dimEnabled: exclusiveOpen
  readonly property real contentPreferredWidth: 240
  readonly property real contentPreferredHeight: 180
  MouseArea {
    anchors.fill: parent
    onClicked: parent.pluginApi.clicks++
  }
}
'''

PROBE = r'''
  property var lifecyclePanel: null
  property var lifecycleModal: null
  property int lifecycleStep: 0
  property int lifecycleTicks: 0

  QtObject {
    id: lifecycleApi
    property var panelOpenScreen: null
    property int clicks: 0
  }

  function lifecycleCheck(name, passed) {
    console.log("PLUGIN_PANEL_CASE " + JSON.stringify({name: name, passed: passed,
      open: lifecyclePanel.isPanelOpen, visible: lifecyclePanel.isPanelVisible,
      exclusive: lifecyclePanel.exclusiveOpen, input: lifecyclePanel.keyboardActive,
      opened: PanelService.openedPanel?.objectName || "",
      coexisting: PanelService.coexistingPanel?.objectName || "",
      slots: PanelService.backgroundSlotAssignments.map(p => p?.objectName || "")}));
  }

  function lifecycleLoad(id) {
    Service.loadedPlugins = Object.assign({}, Service.loadedPlugins, {
      [id]: {manifest: {entryPoints: {panel: "Panel.qml"}}, api: lifecycleApi}
    });
    lifecyclePanel.currentPluginId = id;
    lifecyclePanel.currentPluginApi = lifecycleApi;
    lifecyclePanel.open();
  }

  Timer {
    interval: 100
    running: true
    repeat: true
    onTriggered: {
      if (++shellRoot.lifecycleTicks > 200) {
        console.log("PLUGIN_PANEL_TIMEOUT " + shellRoot.lifecycleStep);
        Qt.exit(2);
        return;
      }
      const screen = Quickshell.screens[0];
      if (!screen)
        return;
      if (!shellRoot.lifecyclePanel) {
        // Let the fresh profile's first-run presentation finish requesting its
        // panel before starting the ownership scenarios.
        if (delayedInitTimer.running || wizardRetryTimer.running)
          return;
        shellRoot.lifecyclePanel = PanelService.getPanel("pluginPanel1", screen, false);
        shellRoot.lifecycleModal = PanelService.getPanel("clockPanel", screen, false);
        if (!shellRoot.lifecyclePanel || !shellRoot.lifecycleModal)
          return;
        if (PanelService.openedPanel)
          PanelService.openedPanel.closeImmediately();
        shellRoot.lifecycleModal.open();
        return;
      }
      const p = shellRoot.lifecyclePanel;
      const modal = shellRoot.lifecycleModal;
      switch (shellRoot.lifecycleStep) {
      case 0:
        if (!modal.isPanelVisible || !modal.sizeAnimationComplete)
          return;
        shellRoot.lifecycleLoad("panel-overlay");
        shellRoot.lifecycleStep++;
        break;
      case 1:
        if (!p.isPanelVisible || !p.sizeAnimationComplete || !p.pluginInstance)
          return;
        shellRoot.lifecycleCheck("coexists-with-existing-modal", modal.isPanelOpen && !modal.isClosing && PanelService.openedPanel === modal);
        shellRoot.lifecycleCheck("overlay-input-enabled", p.keyboardActive && p.pluginInstance.enabled);
        shellRoot.lifecycleCheck("overlay-background-owner", PanelService.coexistingPanel === p && PanelService.backgroundSlotAssignments[2] === p);
        modal.closeImmediately();
        modal.open();
        shellRoot.lifecycleStep++;
        break;
      case 2:
        if (!modal.isPanelVisible || !modal.sizeAnimationComplete)
          return;
        shellRoot.lifecycleCheck("survives-new-modal", p.isPanelOpen && !p.isClosing && p.keyboardActive);
        p.close();
        shellRoot.lifecycleStep++;
        break;
      case 3:
        if (p.isPanelOpen)
          return;
        shellRoot.lifecycleCheck("animated-close-releases-overlay", PanelService.coexistingPanel !== p && !PanelService.backgroundSlotAssignments.includes(p));
        shellRoot.lifecycleCheck("overlay-close-keeps-modal", PanelService.openedPanel === modal && modal.keyboardActive);
        shellRoot.lifecycleLoad("panel-overlay");
        shellRoot.lifecycleStep++;
        break;
      case 4:
        if (!p.isPanelVisible || !p.sizeAnimationComplete)
          return;
        shellRoot.lifecycleCheck("reopened-overlay-input", p.keyboardActive && p.pluginInstance.enabled);
        p.closeImmediately();
        shellRoot.lifecycleCheck("immediate-close-releases-overlay", PanelService.coexistingPanel !== p && !PanelService.backgroundSlotAssignments.includes(p));
        shellRoot.lifecycleLoad("panel-modal");
        shellRoot.lifecycleStep++;
        break;
      case 5:
        if (!p.isPanelVisible || !p.sizeAnimationComplete)
          return;
        shellRoot.lifecycleCheck("modal-plugin-owns-input", PanelService.openedPanel === p && p.keyboardActive && p.pluginInstance.enabled && (modal.isClosing || !modal.isPanelOpen));
        p.closeImmediately();
        shellRoot.lifecycleCheck("modal-close-releases-owner", PanelService.openedPanel !== p && !PanelService.backgroundSlotAssignments.includes(p));
        shellRoot.lifecycleLoad("panel-overlay");
        p.closeImmediately();
        shellRoot.lifecycleStep++;
        break;
      case 6:
        shellRoot.lifecycleCheck("cancel-before-open-completion", !p.isPanelOpen && !p.isPanelVisible && PanelService.openedPanel !== p && PanelService.coexistingPanel !== p && !PanelService.backgroundSlotAssignments.includes(p));
        console.log("PLUGIN_PANEL_DONE");
        Qt.quit();
        stop();
      }
    }
  }
'''


def main():
    """Run isolated plugin lifecycle scenarios and record consumer assertions."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--workspace', type=Path, required=True)
    add_execution_arguments(parser)
    args = parser.parse_args()
    work = args.workspace.resolve()
    temp = Path(os.environ['TMPDIR']).resolve()
    try:
        require_disk_backed_paths(work, temp)
    except ValueError:
        parser.error('use disk-backed workspace and TMPDIR inside the assigned VM')
    work.mkdir()
    shell = work / 'shell'
    shutil.copytree(args.source, shell, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__', '*.bak'))
    entry = shell / 'shell.qml'
    original = entry.read_text()
    position = original.rfind('}')
    assert position > 0 and 'id: shellRoot' in original
    entry.write_text(original[:position] + PROBE + original[position:])
    env = dict(os.environ, QT_QPA_PLATFORM='wayland', QT_QUICK_BACKEND='software')
    for key, leaf in (('HOME', 'home'), ('XDG_CONFIG_HOME', 'config'),
                      ('XDG_DATA_HOME', 'data'), ('XDG_CACHE_HOME', 'cache'),
                      ('XDG_STATE_HOME', 'state')):
        directory = work / leaf
        directory.mkdir()
        env[key] = str(directory)
    config = work / 'config' / 'atmosphera'
    env['ATMOSPHERA_CONFIG_DIR'] = str(config) + '/'
    for name, exclusive in (('panel-overlay', False), ('panel-modal', True)):
        plugin = config / 'plugins' / name
        plugin.mkdir(parents=True)
        (plugin / 'Panel.qml').write_text(PANEL % str(exclusive).lower())
    execution = run_harness(['dbus-run-session', '--', 'qs', '-p', str(shell), '--no-color'], work, env, args.budget)
    text = (work / 'shell.log').read_text(errors='replace')
    rows = [json.loads(line.split('PLUGIN_PANEL_CASE ', 1)[1]) for line in text.splitlines()
            if 'PLUGIN_PANEL_CASE ' in line]
    errors = [line for line in text.splitlines() if re.search(
        r'Failed to load configuration|TypeError:|ReferenceError:|SyntaxError:|is not a type|is unavailable', line)]
    receipt = dict(passed=len(rows) == 11 and all(r['passed'] for r in rows)
                   and 'PLUGIN_PANEL_DONE' in text and not errors,
                   cases=rows, qml_errors=errors)
    write_receipt(work, receipt, execution)
    print(json.dumps(receipt, indent=2))
    return 0 if receipt['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
