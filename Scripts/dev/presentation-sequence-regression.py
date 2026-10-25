#!/usr/bin/env python3
"""Latest-request completion matrix; run only in the assigned Wayland VM."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

PROBE = r'''
  property var _sequenceOsd: null
  property var _sequenceNotifications: null
  property int _sequenceCase: 0
  property int _sequenceStage: -1
  property int _sequenceTicks: 0
  property int _sequenceOpened: 0
  property int _sequenceBefore: 0
  property int _sequenceLintExit: -1
  property bool _sequenceReentrantStarted: false
  property bool _sequenceReentrantRecorded: false
  property var _sequenceExceptions: []
  readonly property var _sequenceHosts: ["clockPanel", "settingsPanel", "launcherPanel", "controlCenterPanel", "pluginPanel1",
    "dialog", "settings-window", "osd", "dock", "popup", "tray", "notifications", "settings-tab"]
  readonly property var _sequenceNames: ["open-open", "open-close-open", "close-open", "open-close"]
  function _sequenceHost() { return _sequenceHosts[Math.floor(_sequenceCase / 4)]; }
  function _sequencePanel() { return PanelService.getPanel(_sequenceHost() === "settings-tab" ? "settingsPanel" : _sequenceHost(), Quickshell.screens[0], false); }
  function _sequenceIsPanel() { return Math.floor(_sequenceCase / 4) < 5 || _sequenceHost() === "settings-tab"; }
  function _sequenceOnOpened() { _sequenceOpened++; }
  function _sequenceCancelRegisteredOpen() {
    PanelService.willOpen.disconnect(shellRoot._sequenceCancelRegisteredOpen);
    PanelService.getPanel("clockPanel", Quickshell.screens[0], false).close();
  }
  function _sequenceText(item, text) {
    if (!item) return false;
    if (item.visible && item.text === text) return true;
    const children = item.children || [];
    for (let i = 0; i < children.length; i++) if (_sequenceText(children[i], text)) return true;
    return false;
  }
  function _sequenceSettings(item) {
    if (!item) return null;
    if (typeof item.navigateToTab === "function" && item.tabsModel) return item;
    const children = item.children || [];
    for (let i = 0; i < children.length; i++) { const found = _sequenceSettings(children[i]); if (found) return found; }
    return null;
  }
  function _sequenceVisual(o) {
    if (!o || !o.item) return false;
    const children = o.item.contentItem.children;
    for (let i = 0; i < children.length; i++)
      if (typeof children[i].hideImmediately === "function") return children[i].visible && children[i].opacity > 0;
    return false;
  }
  function _sequenceData(marker) {
    return {id: "sequence-" + marker, summary: "Sequence" + marker, summaryMarkdown: "Sequence" + marker,
      body: "", bodyMarkdown: "", appName: "Probe", urgency: 1, expireTimeout: 60000,
      timestamp: new Date(), progress: 1.0, originalImage: "", cachedImage: "", originalId: 0, actionsJson: "[]"};
  }
  function _sequenceOpen(marker) {
    const host = _sequenceHost(); const screen = Quickshell.screens[0];
    try {
    if (host === "settings-tab") _sequencePanel().openToTab(marker - 1, -1, null, Qt.point(screen.width * (marker === 1 ? 0.4 : 0.6), 0));
    else if (_sequenceIsPanel()) _sequencePanel().open(null, Qt.point(screen.width * (marker === 1 ? 0.4 : 0.6), 0));
    else if (host === "dialog") PanelService.getPanel("dialogPanel", screen, false).showFor(2, "Sequence" + marker, "Sequence" + marker, "");
    else if (host === "settings-window") SettingsPanelService.openWindow(marker - 1);
    else if (host === "osd") { const o = _sequenceOsd.instances[0]; o.startupComplete = true; o.showOSD(marker === 1 ? 0 : 2); }
    else if (host === "dock") sequenceDock.show(sequenceAnchor, {appId: "sequence-" + marker}, screen);
    else if (host === "popup") PanelService.getPopupMenuWindow(screen).showDynamicContextMenu([{label: "Sequence" + marker}], 400, 400, function () { return false; });
    else if (host === "tray") sequenceTray.showAt(sequenceAnchor, marker * 20, 0);
    else if (host === "notifications") { NotificationService.popupModel.clear(); NotificationService.popupModel.append(_sequenceData(marker)); }
    } catch (error) {
      _sequenceExceptions = _sequenceExceptions.concat(String(error));
      console.log("SEQUENCE_EXCEPTION " + host + " " + String(error));
    }
  }
  function _sequenceClose(immediate) {
    const host = _sequenceHost(); const screen = Quickshell.screens[0];
    if (_sequenceIsPanel()) { const p = _sequencePanel(); if (immediate) p.closeImmediately(); else p.close(); }
    else if (host === "dialog") PanelService.getPanel("dialogPanel", screen, false).visible = false;
    else if (host === "settings-window") SettingsPanelService.closeWindow();
    else if (host === "osd") _sequenceOsd.instances[0].hideOSD();
    else if (host === "dock") sequenceDock.hide();
    else if (host === "popup") PanelService.closeContextMenu(screen);
    else if (host === "tray") sequenceTray.hideMenu();
    else if (host === "notifications") NotificationService.popupModel.clear();
  }
  function _sequenceState() {
    const host = _sequenceHost(); const screen = Quickshell.screens[0];
    if (_sequenceIsPanel()) {
      const p = _sequencePanel(); const region = p.panelRegion;
      return {open: p.isPanelOpen, visible: p.isPanelVisible, ready: p.sizeAnimationComplete && !p.isClosing,
        width: region ? region.width : 0, height: region ? region.height : 0,
        latest: host === "settings-tab" ? !!(p.tabsModel[p.currentTabIndex] && p.tabsModel[p.currentTabIndex].id === 1) : p.buttonPosition.x > screen.width / 2,
        completed: _sequenceOpened - _sequenceBefore,
        ownsSlot: p.exclusiveOpen ? PanelService.openedPanel === p && PanelService.closingPanel !== p : PanelService.coexistingPanel === p};
    }
    if (host === "dialog") {
      const p = PanelService.getPanel("dialogPanel", screen, false);
      return {open: p.visible, visible: p.visible, ready: p.visible, latest: _sequenceText(p.contentItem, "Sequence2")};
    }
    if (host === "settings-window") {
      const p = SettingsPanelService.settingsWindow; const content = _sequenceSettings(p.contentItem);
      return {open: p.visible, visible: p.visible, ready: p.isInitialized,
        latest: content && content.tabsModel[content.currentTabIndex] && content.tabsModel[content.currentTabIndex].id === 1};
    }
    if (host === "osd") { const p = _sequenceOsd.instances[0]; return {open: p.active, visible: _sequenceVisual(p), ready: p.active, latest: p.currentOSDType === 2}; }
    if (host === "dock") return {open: sequenceDock.visible, visible: sequenceDock.visible, ready: sequenceDock.visible, latest: sequenceDock.appData && sequenceDock.appData.appId === "sequence-2"};
    if (host === "popup") {
      const p = PanelService.getPopupMenuWindow(screen); const menu = p.popupContentItem;
      return {open: p.visible, visible: p.visible && menu && menu.visible, ready: menu && menu.width > 0,
        latest: menu && _sequenceText(menu.contentItem, "Sequence2")};
    }
    if (host === "tray") return {open: sequenceTray.visible, visible: sequenceTray.visible, ready: sequenceTray.height > 0,
      latest: sequenceTray.anchorX === 40 && _sequenceText(sequenceTray.contentItem, "Sequence Action")};
    const p = _sequenceNotifications.instances[0];
    return {open: p.shouldBeActive, visible: p.shouldBeActive && p.active && p.item !== null, ready: p.item !== null,
      latest: p.item && _sequenceText(p.item.contentItem, "Sequence2")};
  }
  Process { id: sequenceTrayFixture; command: ["python", "-B", Quickshell.shellDir + "/Scripts/dev/fixtures/presentation-tray.py"] }
  Process {
    id: sequenceLintWorker
    command: ["python", "-B", Quickshell.shellDir + "/Scripts/dev/presentation-sequence-regression.py", "--lint-worker", Quickshell.shellDir]
    onExited: (exitCode) => { shellRoot._sequenceLintExit = exitCode; }
  }
  PanelWindow {
    screen: Quickshell.screens[0]
    anchors.bottom: true; anchors.left: true
    implicitWidth: 120; implicitHeight: 40; color: "transparent"
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    Item { id: sequenceAnchor; width: 100; height: 40 }
    DockMenu { id: sequenceDock }
    TrayMenu { id: sequenceTray; shellScreen: Quickshell.screens[0] }
  }
  Timer {
    interval: 100; running: true; repeat: true
    onTriggered: {
      if (shellRoot._sequenceCase === shellRoot._sequenceHosts.length * 4) {
        if (!shellRoot._sequenceReentrantStarted) {
          shellRoot._sequenceReentrantStarted = true;
          const panel = PanelService.getPanel("clockPanel", Quickshell.screens[0], false);
          panel.closeImmediately();
          PanelService.willOpen.connect(shellRoot._sequenceCancelRegisteredOpen);
          panel.open();
          shellRoot._sequenceTicks = 0;
          return;
        }
        shellRoot._sequenceTicks++;
        if (shellRoot._sequenceTicks < 8) return;
        if (!shellRoot._sequenceReentrantRecorded) {
          const panel = PanelService.getPanel("clockPanel", Quickshell.screens[0], false);
          console.log("SEQUENCE_REENTRANT_RESULT " + JSON.stringify({open: panel.isPanelOpen,
            visible: panel.isPanelVisible, ownsSlot: PanelService.openedPanel === panel}));
          shellRoot._sequenceReentrantRecorded = true;
        }
        if (Quickshell.env("SEQUENCE_LINT_FILES") === "[]" || shellRoot._sequenceLintExit !== -1) {
          sequenceTrayFixture.running = false;
          Qt.quit();
        }
        return;
      }
      shellRoot._sequenceTicks++;
      if (shellRoot._sequenceStage === -1) {
        const items = SystemTray.items.values;
        if (!sequenceTrayFixture.running) sequenceTrayFixture.running = true;
        if (!shellRoot.settingsLoaded || !shellRoot.i18nLoaded || delayedInitTimer.running || !PanelService.getPanel("clockPanel", Quickshell.screens[0], false) || !items.length || shellRoot._sequenceTicks < 25) return;
        sequenceTray.trayItem = items[0];
        if (Quickshell.env("SEQUENCE_LINT_FILES") !== "[]") sequenceLintWorker.running = true;
        if (PanelService.openedPanel) PanelService.openedPanel.closeImmediately();
        shellRoot._sequenceStage = 0;
      }
      if (shellRoot._sequenceStage === 0) {
        shellRoot._sequenceClose(true);
        shellRoot._sequenceOpened = 0;
        shellRoot._sequenceBefore = 0;
        shellRoot._sequenceExceptions = [];
        if (shellRoot._sequenceIsPanel()) shellRoot._sequencePanel().opened.connect(shellRoot._sequenceOnOpened);
        if (shellRoot._sequenceCase % 4 === 2) {
          shellRoot._sequenceOpen(1);
          shellRoot._sequenceStage = 1;
          shellRoot._sequenceTicks = 0;
          return;
        }
        shellRoot._sequenceOpen(1);
        if (shellRoot._sequenceCase % 4 !== 0) shellRoot._sequenceClose(false);
        if (shellRoot._sequenceCase % 4 !== 3) shellRoot._sequenceOpen(2);
        shellRoot._sequenceStage = 2;
        shellRoot._sequenceTicks = 0;
        return;
      }
      if (shellRoot._sequenceStage === 1) {
        const initial = shellRoot._sequenceState();
        if (!(initial.open && initial.visible && initial.ready) && shellRoot._sequenceTicks < 25) return;
        shellRoot._sequenceBefore = shellRoot._sequenceOpened;
        shellRoot._sequenceClose(false);
        shellRoot._sequenceOpen(2);
        shellRoot._sequenceStage = 2;
        shellRoot._sequenceTicks = 0;
        return;
      }
      if (shellRoot._sequenceTicks < 8) return;
      const state = shellRoot._sequenceState();
      const wantOpen = shellRoot._sequenceCase % 4 !== 3;
      console.log("SEQUENCE_RESULT " + JSON.stringify({host: shellRoot._sequenceHost(),
        sequence: shellRoot._sequenceNames[shellRoot._sequenceCase % 4], wantOpen: wantOpen, state: state,
        exceptions: shellRoot._sequenceExceptions}));
      shellRoot._sequenceClose(true);
      if (shellRoot._sequenceIsPanel()) shellRoot._sequencePanel().opened.disconnect(shellRoot._sequenceOnOpened);
      shellRoot._sequenceCase++;
      shellRoot._sequenceStage = 0;
      shellRoot._sequenceTicks = 0;
      if (shellRoot._sequenceCase === shellRoot._sequenceHosts.length * 4) {
        sequenceTrayFixture.running = false;
      }
    }
  }
  Timer { interval: 360000; running: true; onTriggered: { sequenceTrayFixture.running = false; Qt.quit(); } }
'''

def lint_worker(shell):
    vfs = (shell / '.qmlls.ini').resolve().parent
    assert (vfs / 'qs/Commons/qmldir').exists(), vfs
    env = dict(os.environ, QS_VFS=str(vfs))
    commands = [('qmllint', ['bash', 'Scripts/dev/qmllint.sh', *json.loads(env['SEQUENCE_LINT_FILES'])]),
                ('plugin-selftest', ['python', '-B', 'Scripts/dev/plugin-lint-selftest.py']),
                ('plugin-audit', ['python', '-B', 'Scripts/dev/plugin-lint.py', '--root', 'builtin/plugins', '--catalog', 'builtin/plugins/registry.json'])]
    results = {}
    for name, command in commands:
        with (shell.parent / (name + '.log')).open('x') as log:
            result = subprocess.run(command, cwd=shell, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=300)
        results[name] = result.returncode
        (shell.parent / 'shell-gate.json').write_text(json.dumps(results, indent=2))
        if result.returncode:
            return result.returncode
    return 0

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--workspace', type=Path, required=True)
    parser.add_argument('--lint', nargs='+', default=[])
    args = parser.parse_args()
    work = args.workspace.resolve()
    assert not str(work).startswith('/tmp/') and 'TMPDIR' in os.environ
    work.mkdir()
    shell = work / 'shell'
    shutil.copytree(args.source, shell, ignore=shutil.ignore_patterns('.git', '__pycache__', '*.bak'))
    # The tested revision may predate these test-only helpers.
    fixtures = shell / 'Scripts/dev/fixtures'
    fixtures.mkdir(parents=True, exist_ok=True)
    shutil.copy2(Path(__file__).parent / 'fixtures/presentation-tray.py', fixtures / 'presentation-tray.py')
    shutil.copy2(__file__, shell / 'Scripts/dev/presentation-sequence-regression.py')
    main_qml = shell / 'shell.qml'
    text = main_qml.read_text().replace('import Quickshell\n', 'import Quickshell\nimport Quickshell.Io\nimport Quickshell.Wayland\nimport Quickshell.Services.SystemTray\nimport qs.Modules.Dock\nimport qs.Modules.Bar.Extras\n')
    text = text.replace('      OSD {}', '      OSD { Component.onCompleted: shellRoot._sequenceOsd = this }')
    text = text.replace('      Notification {}', '      Notification { Component.onCompleted: shellRoot._sequenceNotifications = this }')
    pos = text.rfind('}')
    main_qml.write_text(text[:pos] + PROBE + text[pos:])
    (shell / '.qmlls.ini').touch()
    env = dict(os.environ, QT_QPA_PLATFORM='wayland', QT_QUICK_BACKEND='software', XDG_CURRENT_DESKTOP='',
               NIRI_SOCKET='', HYPRLAND_INSTANCE_SIGNATURE='', SWAYSOCK='', LABWC_PID='', DISPLAY='')
    env['SEQUENCE_LINT_FILES'] = json.dumps(args.lint)
    for key, leaf in [('HOME', 'home'), ('XDG_CONFIG_HOME', 'config'), ('XDG_DATA_HOME', 'data'),
                      ('XDG_CACHE_HOME', 'cache'), ('XDG_STATE_HOME', 'state')]:
        directory = work / leaf
        directory.mkdir()
        env[key] = str(directory)
    settings = json.loads((shell / 'Configs/defaults.json').read_text())
    settings['settingsVersion'] = 62
    settings['general']['showChangelogOnStartup'] = False
    settings['inputMethod']['launchFcitx5'] = False
    config = work / 'config/atmosphera'
    config.mkdir()
    (config / 'settings.json').write_text(json.dumps(settings))
    result = subprocess.run(['dbus-run-session', '--', 'qs', '-p', str(shell), '--no-color'],
                            env=env, capture_output=True, text=True, timeout=375)
    log = result.stdout + result.stderr
    (work / 'shell.log').write_text(log)
    rows = [json.loads(line.split('SEQUENCE_RESULT ', 1)[1]) for line in log.splitlines() if 'SEQUENCE_RESULT ' in line]
    errors = [line for line in log.splitlines() if re.search(r'Failed to load configuration|TypeError:|ReferenceError:|SyntaxError:', line)]
    reentrant = [json.loads(line.split('SEQUENCE_REENTRANT_RESULT ', 1)[1]) for line in log.splitlines() if 'SEQUENCE_REENTRANT_RESULT ' in line]
    for row in rows:
        state = row['state']
        row['passed'] = (state['open'] and state['visible'] and state['ready'] and state['latest']) if row['wantOpen'] else (not state['open'] and not state['visible'])
        row['passed'] = row['passed'] and not row['exceptions']
        if row['wantOpen'] and 'completed' in state:
            row['passed'] = row['passed'] and state['completed'] == 1 and state['width'] > 0 and state['height'] > 0 and state['ownsSlot']
        if not row['wantOpen'] and 'ownsSlot' in state:
            row['passed'] = row['passed'] and not state['ownsSlot']
    receipt = dict(passed=result.returncode == 0 and not errors and len(rows) == 52 and all(row['passed'] for row in rows)
                   and reentrant == [dict(open=False, visible=False, ownsSlot=False)],
                   exit_code=result.returncode, cases=rows, reentrant=reentrant, qml_errors=errors)
    if args.lint:
        gates = work / 'shell-gate.json'
        receipt['shell_gate'] = json.loads(gates.read_text()) if gates.exists() else {}
        receipt['passed'] = receipt['passed'] and receipt['shell_gate'] == {'qmllint': 0, 'plugin-selftest': 0, 'plugin-audit': 0}
    (work / 'result.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps(dict(passed=receipt['passed'], exit_code=result.returncode, cases=len(rows),
                          failed=[row for row in rows if not row['passed']], qml_errors=sorted(set(errors)),
                          reentrant=reentrant, shell_gate=receipt.get('shell_gate')), indent=2))
    return 0 if receipt['passed'] else 1

if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == '--lint-worker':
        raise SystemExit(lint_worker(Path(sys.argv[2])))
    raise SystemExit(main())
