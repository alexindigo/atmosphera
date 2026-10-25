#!/usr/bin/env python3
"""Real menu-readiness and reused/destroyed anchor consumer cases, VM only."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
from presentation_harness import add_execution_arguments, run_harness, write_receipt

PROBE = r'''
  property int _identityPhase: 0
  property int _identityTicks: 0
  property bool _identityPending: false
  function _identityItem(suffix) {
    const items = SystemTray.items.values;
    for (let i = 0; i < items.length; i++)
      if (String(items[i].id).endsWith(suffix)) return items[i];
    return null;
  }
  function _identityText(item, text, includeHidden) {
    if (!item) return false;
    if ((includeHidden || item.visible) && item.text === text) return true;
    const children = item.children || [];
    for (let i = 0; i < children.length; i++) if (_identityText(children[i], text, includeHidden)) return true;
    return false;
  }
  Process { id: identityFixture; command: ["python", "-B", Quickshell.shellDir + "/Scripts/dev/fixtures/presentation-tray.py"] }
  Process { id: identityReady; command: ["python", "-B", "-c", "import os; from pathlib import Path; Path(os.environ['PRESENTATION_TRAY_GATE_FILE']).touch()"] }
  Process { id: identityReset; command: ["python", "-B", "-c", "import os; from pathlib import Path; Path(os.environ['PRESENTATION_TRAY_GATE_FILE']).unlink(missing_ok=True)"] }
  PanelWindow {
    screen: Quickshell.screens[0]
    anchors.bottom: true; anchors.left: true
    implicitWidth: 120; implicitHeight: 40; color: "transparent"
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    Loader {
      id: identitySlot
      active: false
      sourceComponent: Item {
        property var modelData: null
        property alias trayAnchor: identityTrayAnchor
        property alias dockAnchor: identityDockAnchor
        width: 100; height: 40
        Item { id: identityTrayAnchor; width: 100; height: 40; readonly property var presentationIdentity: parent.modelData }
        Item { id: identityDockAnchor; width: 100; height: 40; readonly property var presentationIdentity: parent.modelData ? parent.modelData.id : "" }
      }
    }
    DockMenu { id: identityDock }
    NPopupContextMenu { id: identityContext; model: [{label: "Context A"}] }
  }
  Timer {
    interval: 100; running: true; repeat: true
    onTriggered: {
      shellRoot._identityTicks++;
      const items = SystemTray.items.values;
      if (!identityFixture.running) identityFixture.running = true;
      const a = shellRoot._identityItem("-a"), b = shellRoot._identityItem("-b");
      const screen = Quickshell.screens[0];
      const popup = PanelService.getPopupMenuWindow(screen);
      if (!a || !b || !popup || !popup.trayMenuLoader.item || delayedInitTimer.running || shellRoot._identityTicks < 25) return;
      const menu = popup.trayMenuLoader.item;
      if (shellRoot._identityPhase === 0) {
        if (PanelService.openedPanel) PanelService.openedPanel.closeImmediately();
        popup.close(); identitySlot.active = true; identitySlot.item.modelData = a;
        PanelService.showTrayMenu(screen, a, menu, identitySlot.item.trayAnchor, 0, 0, "", -1);
        shellRoot._identityPending = !menu.visible;
        identitySlot.item.modelData = b;
        identityReady.running = true;
      } else if (shellRoot._identityPhase === 1) {
        if (shellRoot._identityTicks < 8) return;
        console.log("IDENTITY_RESULT " + JSON.stringify({case: "reused-pending", pending: shellRoot._identityPending,
          popupVisible: popup.visible, menuVisible: menu.visible}));
        popup.close(); identityReset.running = true;
      } else if (shellRoot._identityPhase === 2) {
        if (identityReset.running || shellRoot._identityText(menu.contentItem, "Sequence Action-a", true)) return;
        identitySlot.item.modelData = a;
        PanelService.showTrayMenu(screen, a, menu, identitySlot.item.trayAnchor, 0, 0, "", -1);
        shellRoot._identityPending = !menu.visible;
        identitySlot.active = false;
        identityReady.running = true;
      } else if (shellRoot._identityPhase === 3) {
        if (shellRoot._identityTicks < 8) return;
        console.log("IDENTITY_RESULT " + JSON.stringify({case: "destroyed-pending", pending: shellRoot._identityPending,
          popupVisible: popup.visible, menuVisible: menu.visible}));
        popup.close(); identitySlot.active = true; identitySlot.item.modelData = b;
        PanelService.showTrayMenu(screen, b, menu, identitySlot.item.trayAnchor, 0, 0, "", -1);
      } else if (shellRoot._identityPhase === 4) {
        if (!menu.visible || !shellRoot._identityText(menu.contentItem, "Sequence Action-b")) return;
        console.log("IDENTITY_RESULT " + JSON.stringify({case: "normal-b", popupVisible: popup.visible, menuVisible: menu.visible, textVisible: true}));
        popup.close(); identityReset.running = true;
      } else if (shellRoot._identityPhase === 5) {
        menu.trayItem = a;
        if (identityReset.running || shellRoot._identityText(menu.contentItem, "Sequence Action-a", true)) return;
        identitySlot.item.modelData = a;
        PanelService.showTrayMenu(screen, a, menu, identitySlot.item.trayAnchor, 0, 0, "", -1);
        shellRoot._identityPending = !menu.visible;
        identityReady.running = true;
      } else if (shellRoot._identityPhase === 6) {
        if (!menu.visible || !shellRoot._identityText(menu.contentItem, "Sequence Action-a")) return;
        console.log("IDENTITY_RESULT " + JSON.stringify({case: "normal-delayed-a", pending: shellRoot._identityPending,
          popupVisible: popup.visible, menuVisible: menu.visible, textVisible: true}));
        popup.close();
        identityContext.openAtItem(identitySlot.item.trayAnchor, screen);
        identitySlot.item.modelData = b;
      } else if (shellRoot._identityPhase === 7) {
        if (shellRoot._identityTicks < 8) return;
        console.log("IDENTITY_RESULT " + JSON.stringify({case: "context-reused", menuVisible: identityContext.visible}));
        identityContext.close(); identitySlot.item.modelData = a;
        identityDock.show(identitySlot.item.dockAnchor, {appId: a.id}, screen);
        identitySlot.item.modelData = b;
      } else {
        if (shellRoot._identityTicks < 8) return;
        console.log("IDENTITY_RESULT " + JSON.stringify({case: "dock-reused", menuVisible: identityDock.visible}));
        identityDock.hide(); identityFixture.running = false; Qt.quit();
      }
      shellRoot._identityPhase++;
      shellRoot._identityTicks = 0;
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
    assert not str(work).startswith('/tmp/')
    work.mkdir()
    shell = work / 'shell'
    shutil.copytree(args.source, shell, ignore=shutil.ignore_patterns('.git', '__pycache__', '*.bak'))
    shutil.copy2(Path(__file__).parent / 'fixtures/presentation-tray.py', shell / 'Scripts/dev/fixtures/presentation-tray.py')
    main_qml = shell / 'shell.qml'
    text = main_qml.read_text().replace('import Quickshell\n', 'import Quickshell\nimport Quickshell.Io\nimport Quickshell.Wayland\nimport Quickshell.Services.SystemTray\nimport qs.Modules.Dock\nimport qs.Widgets\n')
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
    rows = [json.loads(line.split('IDENTITY_RESULT ', 1)[1]) for line in log.splitlines() if 'IDENTITY_RESULT ' in line]
    errors = [line for line in log.splitlines() if re.search(r'Failed to load configuration|TypeError:|ReferenceError:|SyntaxError:', line)]
    expected = [dict(case='reused-pending', pending=True, popupVisible=False, menuVisible=False),
                dict(case='destroyed-pending', pending=True, popupVisible=False, menuVisible=False),
                dict(case='normal-b', popupVisible=True, menuVisible=True, textVisible=True),
                dict(case='normal-delayed-a', pending=True, popupVisible=True, menuVisible=True, textVisible=True),
                dict(case='context-reused', menuVisible=False), dict(case='dock-reused', menuVisible=False)]
    receipt = dict(passed=not errors and rows == expected, cases=rows, qml_errors=errors)
    write_receipt(work, receipt, execution)
    print(json.dumps(receipt, indent=2))
    return 0 if receipt['passed'] else 1

if __name__ == '__main__':
    raise SystemExit(main())
