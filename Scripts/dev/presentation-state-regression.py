#!/usr/bin/env python3
"""Consumer races in a private Wayland shell; execute only in the assigned VM."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
from presentation_harness import add_execution_arguments, run_harness, write_receipt

PROBE = r'''
  property var _stateOsd: null
  property var _stateNotifications: null
  property int _statePhase: 0
  property int _stateClosed: 0
  property var _stateNotificationItem: null
  function _stateNotificationData(id) {
    return {id: id, summary: "Presentation probe", summaryMarkdown: "Presentation probe",
      body: "", bodyMarkdown: "", appName: "Probe", urgency: 1, expireTimeout: 60000,
      timestamp: new Date(), progress: 1.0, originalImage: "", cachedImage: "",
      originalId: 0, actionsJson: "[]"};
  }
  function _stateVisible(o) {
    if (!o || !o.item) return false;
    const children = o.item.contentItem.children;
    for (let i = 0; i < children.length; i++)
      if (typeof children[i].hideImmediately === "function")
        return children[i].visible && children[i].opacity > 0;
    return false;
  }
  PanelWindow {
    screen: Quickshell.screens[0]
    anchors.bottom: true
    anchors.left: true
    implicitWidth: 120
    implicitHeight: 40
    color: "transparent"
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    Item { id: stateAnchor; width: 100; height: 40 }
    DockMenu { id: stateDock; onRequestClose: shellRoot._stateClosed++ }
  }
  Timer {
    interval: 250
    running: true
    repeat: true
    onTriggered: {
      if (!shellRoot._stateOsd || !shellRoot._stateOsd.instances.length ||
          !shellRoot._stateNotifications || !shellRoot._stateNotifications.instances.length)
        return;
      const o = shellRoot._stateOsd.instances[0];
      if (shellRoot._statePhase === 0) {
        o.startupComplete = true;
        o.showOSD(0);
        AudioService.sinkChanged();
        o.hideOSD();
        stateDock.show(stateAnchor, {appId: "first"}, Quickshell.screens[0]);
        stateDock.handlePin("");
        stateDock.hide();
        stateDock.show(stateAnchor, {appId: "second"}, Quickshell.screens[0]);
        const model = NotificationService.popupModel;
        model.clear();
        model.append({notificationId: "presentation-probe"});
        model.clear();
      } else if (shellRoot._statePhase === 1) {
        console.log("STATE_RESULT " + JSON.stringify({case: "hide-replace",
          osdVisible: shellRoot._stateVisible(o), osdActive: o.active,
          dockVisible: stateDock.visible, dockApp: stateDock.appData ? stateDock.appData.appId : null,
          dockClosed: shellRoot._stateClosed,
          notificationsActive: shellRoot._stateNotifications.instances[0].shouldBeActive}));
        o.showOSD(0);
        AudioService.sinkChanged();
        o.showOSD(2);
      } else if (shellRoot._statePhase === 2) {
        // Startup/layout may take more than one observation tick. Observe the
        // real positive consumer outcome; the shared deadline bounds waiting.
        if (o.currentOSDType === 2 && !shellRoot._stateVisible(o)) return;
        console.log("STATE_RESULT " + JSON.stringify({case: "new-show",
          osdVisible: shellRoot._stateVisible(o), osdType: o.currentOSDType}));
        stateDock.handlePin("");
      } else if (shellRoot._statePhase === 3) {
        console.log("STATE_RESULT " + JSON.stringify({case: "ordinary-close",
          dockVisible: stateDock.visible, dockClosed: shellRoot._stateClosed}));
        o.showOSD(0);
        AudioService.sinkChanged();
        const children = o.item.contentItem.children;
        for (let i = 0; i < children.length; i++)
          if (typeof children[i].hideImmediately === "function") children[i].hide();
      } else if (shellRoot._statePhase === 5) {
        console.log("STATE_RESULT " + JSON.stringify({case: "fade-hide",
          osdVisible: shellRoot._stateVisible(o), osdActive: o.active}));
        NotificationService.popupModel.append(shellRoot._stateNotificationData("continuity-first"));
      } else if (shellRoot._statePhase === 6) {
        shellRoot._stateNotificationItem = shellRoot._stateNotifications.instances[0].item;
        NotificationService.popupModel.clear();
        NotificationService.popupModel.append(shellRoot._stateNotificationData("continuity-second"));
      } else if (shellRoot._statePhase === 7) {
        const notifications = shellRoot._stateNotifications.instances[0];
        console.log("STATE_RESULT " + JSON.stringify({case: "notification-continuity",
          active: notifications.shouldBeActive, sameItem: notifications.item === shellRoot._stateNotificationItem}));
        Qt.quit();
      }
      shellRoot._statePhase++;
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
    main_qml = shell / 'shell.qml'
    text = main_qml.read_text().replace('import Quickshell\n', 'import Quickshell\nimport Quickshell.Wayland\nimport qs.Modules.Dock\nimport qs.Services.Media\n')
    assert '      OSD {}' in text and '      Notification {}' in text
    text = text.replace('      OSD {}', '      OSD { Component.onCompleted: shellRoot._stateOsd = this }')
    text = text.replace('      Notification {}', '      Notification { Component.onCompleted: shellRoot._stateNotifications = this }')
    pos = text.rfind('}')
    main_qml.write_text(text[:pos] + PROBE + text[pos:])
    env = dict(os.environ, QT_QPA_PLATFORM='wayland', QT_QUICK_BACKEND='software',
               XDG_CURRENT_DESKTOP='', NIRI_SOCKET='', HYPRLAND_INSTANCE_SIGNATURE='', SWAYSOCK='', LABWC_PID='', DISPLAY='')
    for key, leaf in [('HOME', 'home'), ('XDG_CONFIG_HOME', 'config'), ('XDG_DATA_HOME', 'data'),
                      ('XDG_CACHE_HOME', 'cache'), ('XDG_STATE_HOME', 'state')]:
        directory = work / leaf
        directory.mkdir()
        env[key] = str(directory)
    execution = run_harness(['dbus-run-session', '--', 'qs', '-p', str(shell), '--no-color'], work, env, args.budget)
    log = (work / 'shell.log').read_text(errors='replace')
    rows = [json.loads(line.split('STATE_RESULT ', 1)[1]) for line in log.splitlines() if 'STATE_RESULT ' in line]
    errors = [line for line in log.splitlines() if re.search(r'Failed to load configuration|TypeError:|ReferenceError:|SyntaxError:', line)]
    passed = (execution['exit_code'] == 0 and not errors and len(rows) == 5
              and rows[0] == dict(case='hide-replace', osdVisible=False, osdActive=False,
                                  dockVisible=True, dockApp='second', dockClosed=0, notificationsActive=False)
              and rows[1] == dict(case='new-show', osdVisible=True, osdType=2)
              and rows[2] == dict(case='ordinary-close', dockVisible=False, dockClosed=1)
              and rows[3] == dict(case='fade-hide', osdVisible=False, osdActive=False)
              and rows[4] == dict(case='notification-continuity', active=True, sameItem=True))
    receipt = dict(passed=passed, exit_code=execution['exit_code'], cases=rows, qml_errors=errors)
    write_receipt(work, receipt, execution)
    print(json.dumps(receipt, indent=2))
    return 0 if receipt['passed'] else 1

if __name__ == '__main__':
    raise SystemExit(main())
