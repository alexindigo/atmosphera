#!/usr/bin/env python3
"""Observe current popup-content ownership through the public service, VM only."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
from presentation_harness import add_execution_arguments, run_harness, write_receipt

PROBE = r'''
  property int _ownerCase: 0
  property int _ownerStage: 0
  property int _ownerTicks: 0
  property int _ownerInvalidations: 0
  property var _ownerMenu: null
  property var _ownerBefore: null
  property var _ownerNames: ["external-invalidated", "external-close", "external-native-hide",
    "external-destroy", "replaced-content", "dynamic-close", "tray-pending-close", "tray-close",
    "dialog-close", "menu-dialog-handoff", "host-native-hide", "external-tray-close",
    "bar-dialog-close", "desktop-dialog-close"]
  function _ownerText(item, text) {
    if (!item || !item.visible) return false;
    if (item.text === text) return true;
    const children = item.children || [];
    for (let i = 0; i < children.length; i++) if (_ownerText(children[i], text)) return true;
    return false;
  }
  function _ownerState(popup) {
    return {popupVisible: popup.visible, menuVisible: !!_ownerMenu?.visible,
      popupOwnsMenu: _ownerMenu !== null && popup.popupContentItem === _ownerMenu,
      popupOpen: BarService.popupOpen, invalidations: _ownerInvalidations,
      actionVisible: _ownerText(_ownerMenu?.contentItem, "Context A"),
      anchorIdentity: ownerAnchor.presentationIdentity};
  }
  function _ownerDialog(popup) {
    ownerDialog.parent = popup.dialogParent;
    if (typeof popup.showDialog === "function") popup.showDialog(ownerDialog);
    else { popup.hasDialog = true; popup.open(); }
    ownerDialog.open();
    _ownerMenu = ownerDialog;
  }
  Process { id: ownerFixture; command: ["python", "-B", Quickshell.shellDir + "/Scripts/dev/fixtures/presentation-tray.py"] }
  PanelWindow {
    screen: Quickshell.screens[0]
    anchors.bottom: true; anchors.left: true
    implicitWidth: 120; implicitHeight: 40; color: "transparent"
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    Item { id: ownerAnchor; width: 100; height: 40; property string presentationIdentity: "A" }
    Item { id: ownerTrayAnchor; width: 100; height: 40; property var presentationIdentity: null }
    TrayMenu { id: ownerExternalTray; shellScreen: Quickshell.screens[0] }
    Loader {
      id: ownerContext
      active: false
      sourceComponent: NPopupContextMenu {
        model: [{label: "Context A", action: "a"}]
        onPresentationInvalidated: shellRoot._ownerInvalidations++
      }
    }
    Controls.Popup {
      id: ownerDialog
      width: 200; height: 100
      closePolicy: Controls.Popup.NoAutoClose
      contentItem: Text { text: "Owner dialog" }
    }
  }
  Timer {
    interval: 100; running: true; repeat: true
    onTriggered: {
      shellRoot._ownerTicks++;
      if (!ownerFixture.running) ownerFixture.running = true;
      const screen = Quickshell.screens[0];
      const popup = PanelService.getPopupMenuWindow(screen);
      const items = SystemTray.items.values;
      const a = items.find(item => String(item.id).endsWith("-a"));
      const b = items.find(item => String(item.id).endsWith("-b"));
      if (!popup?.trayMenuLoader.item || !a || !b || delayedInitTimer.running) return;
      const name = shellRoot._ownerNames[shellRoot._ownerCase];
      if (shellRoot._ownerStage === 0) {
        if (shellRoot._ownerCase === 0 && shellRoot._ownerTicks < 25) return;
        popup.close();
        if (PanelService.openedPanel) PanelService.openedPanel.closeImmediately();
        ownerContext.active = true;
        ownerAnchor.presentationIdentity = "A";
        shellRoot._ownerInvalidations = 0;
        shellRoot._ownerMenu = ownerContext.item;
        if (name === "dynamic-close") {
          popup.showDynamicContextMenu([{label: "Context A", action: "a"}], 50, 50, () => true);
          shellRoot._ownerMenu = popup.popupContentItem;
        } else if (name.includes("tray-")) {
          const item = name === "tray-pending-close" ? a : b;
          ownerTrayAnchor.presentationIdentity = item;
          shellRoot._ownerMenu = name === "external-tray-close" ? ownerExternalTray : popup.trayMenuLoader.item;
          PanelService.showTrayMenu(screen, item, shellRoot._ownerMenu, ownerTrayAnchor, 0, 0, "", -1);
        } else if (name === "dialog-close") {
          shellRoot._ownerDialog(popup);
        } else if (name === "bar-dialog-close") {
          BarService.openWidgetSettings(screen, "center", 0, "Clock", {});
        } else if (name === "desktop-dialog-close") {
          DesktopWidgetRegistry.openWidgetSettings(screen, -1, "Clock", {}, null);
        } else {
          PanelService.showContextMenu(ownerContext.item, ownerAnchor, screen);
        }
        shellRoot._ownerStage = 1;
        shellRoot._ownerTicks = 0;
        return;
      }
      if (shellRoot._ownerStage === 1) {
        if (name === "bar-dialog-close" || name === "desktop-dialog-close") {
          // Qt Quick Popup is not an Item in dialogParent.children. Observe
          // the public hosted QObject, including the real service-created one.
          const dialog = popup.popupContentItem;
          if (!popup.hasDialog || dialog?.widgetId !== "Clock" || !dialog.opened) return;
          shellRoot._ownerMenu = dialog;
        }
        const menu = shellRoot._ownerMenu;
        const ready = name === "tray-pending-close" ? !menu.visible && menu._showRequested
          : name.includes("tray-") ? menu.visible && shellRoot._ownerText(menu.contentItem, "Sequence Action-b")
          : name.endsWith("dialog-close") ? menu.opened : menu.visible && shellRoot._ownerText(menu.contentItem, "Context A");
        if (!ready || !popup.visible || !BarService.popupOpen) return;
        shellRoot._ownerBefore = shellRoot._ownerState(popup);
        if (name === "external-invalidated") ownerAnchor.presentationIdentity = "B";
        else if (name === "host-native-hide") popup.visible = false;
        else if (name === "external-destroy") { shellRoot._ownerMenu = null; ownerContext.active = false; }
        else if (name === "external-native-hide") menu.visible = false;
        else if (name === "replaced-content") {
          popup.showDynamicContextMenu([{label: "Replacement", action: "b"}], 50, 50, () => true);
          shellRoot._ownerMenu = popup.popupContentItem;
          ownerContext.item.presentationInvalidated();
          ownerContext.item.close();
        } else if (name === "menu-dialog-handoff") {
          popup.hideDynamicMenu();
          shellRoot._ownerDialog(popup);
        } else if (name.includes("tray-")) menu.hideMenu();
        else menu.close();
        shellRoot._ownerStage = 2;
        shellRoot._ownerTicks = 0;
        return;
      }
      if (shellRoot._ownerTicks < 4) return;
      const state = shellRoot._ownerState(popup);
      state.hasDialog = popup.hasDialog;
      state.replacementVisible = shellRoot._ownerText(shellRoot._ownerMenu?.contentItem, "Replacement");
      console.log("OWNER_RESULT " + JSON.stringify({case: name, before: shellRoot._ownerBefore, after: state}));
      // Close the native dialog before resetting the host, including on the red baseline.
      ownerDialog.close();
      popup.hasDialog = false;
      popup.close();
      shellRoot._ownerCase++;
      if (shellRoot._ownerCase === shellRoot._ownerNames.length) { ownerFixture.running = false; Qt.quit(); }
      else { shellRoot._ownerStage = 0; shellRoot._ownerTicks = 0; }
    }
  }
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--workspace', type=Path, required=True)
    add_execution_arguments(parser)
    args = parser.parse_args()
    work = args.workspace.resolve()
    assert not str(work).startswith('/tmp/') and 'TMPDIR' in os.environ
    work.mkdir()
    shell = work / 'shell'
    shutil.copytree(args.source, shell, ignore=shutil.ignore_patterns('.git', '__pycache__', '*.bak'))
    shutil.copy2(Path(__file__).parent / 'fixtures/presentation-tray.py', shell / 'Scripts/dev/fixtures/presentation-tray.py')
    main_qml = shell / 'shell.qml'
    text = main_qml.read_text().replace('import Quickshell\n', 'import Quickshell\nimport QtQuick.Controls as Controls\nimport Quickshell.Io\nimport Quickshell.Wayland\nimport Quickshell.Services.SystemTray\nimport qs.Modules.Bar.Extras\nimport qs.Widgets\n')
    pos = text.rfind('}')
    main_qml.write_text(text[:pos] + PROBE + text[pos:])
    env = dict(os.environ, QT_QPA_PLATFORM='wayland', QT_QUICK_BACKEND='software', XDG_CURRENT_DESKTOP='',
               NIRI_SOCKET='', HYPRLAND_INSTANCE_SIGNATURE='', SWAYSOCK='', LABWC_PID='', DISPLAY='',
               PRESENTATION_TRAY_GATE_FILE=str(work / 'menu-ready'))
    for key, leaf in [('HOME', 'home'), ('XDG_CONFIG_HOME', 'config'), ('XDG_DATA_HOME', 'data'),
                      ('XDG_CACHE_HOME', 'cache'), ('XDG_STATE_HOME', 'state')]:
        directory = work / leaf
        directory.mkdir()
        env[key] = str(directory)
    execution = run_harness(['dbus-run-session', '--', 'qs', '-p', str(shell), '--no-color'], work, env, args.budget)
    log = (work / 'shell.log').read_text(errors='replace')
    rows = [json.loads(line.split('OWNER_RESULT ', 1)[1]) for line in log.splitlines() if 'OWNER_RESULT ' in line]
    errors = [line for line in log.splitlines() if re.search(r'Failed to load configuration|TypeError:|ReferenceError:|SyntaxError:', line)]
    expected = ['external-invalidated', 'external-close', 'external-native-hide', 'external-destroy',
                'replaced-content', 'dynamic-close', 'tray-pending-close', 'tray-close', 'dialog-close', 'menu-dialog-handoff',
                'host-native-hide', 'external-tray-close', 'bar-dialog-close', 'desktop-dialog-close']
    for row in rows:
        before, after = row['before'], row['after']
        positive = before['popupVisible'] and before['popupOpen'] and before['popupOwnsMenu']
        positive = positive and (not before['menuVisible'] if row['case'] == 'tray-pending-close' else before['menuVisible'])
        if row['case'] in ('replaced-content', 'menu-dialog-handoff'):
            outcome = after['popupVisible'] and after['popupOpen'] and after['menuVisible'] and after['popupOwnsMenu']
            outcome = outcome and (after['replacementVisible'] if row['case'] == 'replaced-content' else after['hasDialog'])
        else:
            outcome = not any(after[key] for key in ('popupVisible', 'popupOpen', 'menuVisible', 'popupOwnsMenu'))
            if row['case'] == 'external-invalidated':
                outcome = outcome and after['invalidations'] == 1 and after['anchorIdentity'] == 'B'
        row['passed'] = positive and outcome
    receipt = dict(passed=not errors and [row['case'] for row in rows] == expected and all(row['passed'] for row in rows),
                   cases=rows, qml_errors=errors)
    write_receipt(work, receipt, execution)
    print(json.dumps(dict(passed=receipt['passed'], cases=len(rows), failed=[row for row in rows if not row['passed']],
                          qml_errors=errors, execution=execution), indent=2))
    return 0 if receipt['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
