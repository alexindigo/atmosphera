#!/usr/bin/env python3
"""Guest-only executable inspection, async-state and real Settings-page checks.

All locker fixtures are tripwires: executing one fails the test. No lock action
is requested. Use --baseline-page with an unmodified source for the failing leg.
"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import time

from presentation_harness import run_harness, write_receipt
from qml_probe import inject_probe
from workspace_guard import check_execution_paths


ASYNC = r'''
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Helpers
ShellRoot {
  id: root
  property int step: 0
  property int ticks: 0
  property int passes: 0
  property bool editing: false
  property bool installing: false
  property var cases: CASES
  ExternalCommandCheck { id: check; enabled: false }
  function fail(message) { console.log("CHECK_FAIL " + message); Qt.exit(1); }
  function begin() {
    const test = cases[step];
    check.checkerCommand = test.checker || ["python3", Quickshell.shellPath("Scripts/python/check-external-command.py")];
    check.commandText = test.input;
    if (test.install) {
      installing = true;
      installer.command = ["python3", "-c", "import shutil,sys; shutil.copy2(sys.argv[1],sys.argv[2])", Quickshell.env("LOCK_COMMAND_TRIPWIRE"), test.install];
      installer.running = true;
    } else check.enabled = true;
    ticks = 0;
    editing = false;
    if (!installing && check.state !== (test.input.trim() === "" ? "empty" : "pending")) fail("immediate state " + test.name);
  }
  Process {
    id: installer
    onExited: function(exitCode) {
      if (exitCode !== 0) { root.fail("fixture installation failed"); return; }
      check.enabled = true;
      root.installing = false;
      if (check.state !== "pending") root.fail("reopen did not invalidate cached result");
    }
  }
  Component.onCompleted: begin()
  Timer {
    interval: 25; repeat: true; running: true
    onTriggered: {
      root.ticks++;
      if (root.installing) return;
      const test = root.cases[root.step];
      // Change text after the old slow check started, including ABA. Its
      // available result must not turn the new missing command green.
      if (test.rapid && root.ticks === 25) {
        check.commandText = test.aba ? "atmosphera-definitely-missing-locker" : "aerial-lock";
        check.commandText = test.aba ? "aerial-lock" : "atmosphera-definitely-missing-locker";
        check.checkerCommand = ["python3", Quickshell.shellPath("Scripts/python/check-external-command.py")];
        root.editing = true;
        if (check.state !== "pending") root.fail("edit did not invalidate old result");
      }
      if (test.rapid && root.ticks < 26) return;
      if (check.state === "pending") {
        if (root.ticks > 200) root.fail("timeout " + test.name);
        return;
      }
      if (check.state !== test.expected) { root.fail(test.name + ": " + check.state); return; }
      console.log("CHECK_PASS " + test.name);
      root.passes++;
      check.enabled = false;
      root.step++;
      if (root.step === root.cases.length) {
        console.log("ASYNC_COMPLETE " + root.passes);
        Qt.quit();
      } else root.begin();
    }
  }
}
'''

PAGE = r'''
  property int _lockTicks: 0
  property int _lockStep: 0
  property var _lockPanel: null
  function _lockFind(item, name) {
    if (!item) return null;
    if (item.objectName === name) return item;
    if (item.children) for (let i = 0; i < item.children.length; i++) {
      const found = _lockFind(item.children[i], name);
      if (found) return found;
    }
    return null;
  }
  Timer {
    interval: 100; repeat: true; running: true
    onTriggered: {
      shellRoot._lockTicks++;
      if (shellRoot._lockTicks > 220) { console.log("PAGE_TIMEOUT"); Qt.exit(1); return; }
      if (!Settings.isLoaded || !Quickshell.screens[0]) return;
      Settings.shouldOpenSetupWizard = false;
      if (!shellRoot._lockPanel) {
        const panel = PanelService.getPanel("settingsPanel", Quickshell.screens[0], false);
        if (!panel) return;
        Settings.data.general.lockScreenPlugin = "external";
        Settings.data.general.externalLockCommand = "aerial-lock";
        shellRoot._lockPanel = panel;
        panel.openToTab(4, 0);
        return;
      }
      const panel = shellRoot._lockPanel;
      if (shellRoot._lockStep === 3) {
        panel.openToTab(4, 0);
        shellRoot._lockStep = 4;
        return;
      }
      const status = shellRoot._lockFind(panel, "externalCommandStatus");
      if (!status || !panel.isPanelOpen || !panel.isPanelVisible) return;
      if (shellRoot._lockStep === 0 && status.text === "") {
        console.log("PAGE_AVAILABLE");
        Settings.data.general.externalLockCommand = "atmosphera-definitely-missing-locker";
        shellRoot._lockStep = 1;
      } else if (shellRoot._lockStep === 1 && status.text.indexOf("Command not found") >= 0 && status.visible && status.width > 0 && status.height > 0) {
        console.log("PAGE_MISSING");
        Settings.data.general.externalLockCommand = "";
        shellRoot._lockStep = 2;
      } else if (shellRoot._lockStep === 2 && status.text === "") {
        console.log("PAGE_EMPTY");
        Settings.data.general.externalLockCommand = "aerial-lock";
        panel.openToTab(10, 0);
        shellRoot._lockStep = 3;
      } else if (shellRoot._lockStep === 4 && status.text === "") {
        console.log("PAGE_REOPEN_AVAILABLE");
        panel.closeImmediately();
        console.log("PAGE_COMPLETE");
        Qt.quit();
      }
    }
  }
'''

LANGUAGE = r'''
import QtQuick
import QtQuick.Window
import Quickshell
import qs.Commons
import qs.Modules.Panels.Settings.Tabs.Region
ShellRoot {
  id: root
  property int step: 0
  Window { visible: true; width: 840; height: 700; LocationSubTab { id: view; width: 800 } }
  Timer {
    interval: 100; running: true; repeat: true
    onTriggered: {
      if (!Settings.isLoaded || !I18n.isLoaded) return;
      let language = null;
      for (let i = 0; i < view.children.length; i++)
        if (view.children[i].objectName === "languageSelector") language = view.children[i];
      if (!language) return;
      if (root.step === 0) { language.selected("fr"); root.step = 1; }
      else if (root.step === 1 && I18n.langCode === "fr") { language.selected(""); root.step = 2; }
      else if (root.step === 2 && I18n.langCode === I18n.systemDetectedLangCode) {
        console.log("LANGUAGE_AUTOMATIC_COMPLETE"); Qt.quit();
      }
    }
  }
}
'''


def environment(work):
    env = dict(os.environ, QT_QPA_PLATFORM='wayland', QT_QUICK_BACKEND='software',
               XDG_RUNTIME_DIR='/run/user/1000', WAYLAND_DISPLAY='wayland-1',
               XDG_CURRENT_DESKTOP='', NIRI_SOCKET='', HYPRLAND_INSTANCE_SIGNATURE='',
               SWAYSOCK='', LABWC_PID='', DISPLAY='', ATMOSPHERA_DEBUG='0')
    for variable, name in [('HOME', 'home'), ('XDG_CONFIG_HOME', 'config'), ('XDG_DATA_HOME', 'data'),
                           ('XDG_CACHE_HOME', 'cache'), ('XDG_STATE_HOME', 'state')]:
        directory = work / name
        directory.mkdir()
        env[variable] = str(directory)
    return env


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--workspace', type=Path, required=True)
    parser.add_argument('--baseline-page', action='store_true')
    args = parser.parse_args()
    work = args.workspace.resolve()
    check_execution_paths(parser, work)
    work.mkdir()
    shell = work / 'shell'
    shutil.copytree(args.source, shell, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__', '*.bak'))
    bin_dir = work / 'bin'
    bin_dir.mkdir()
    sentinel = work / 'LOCKER_WAS_EXECUTED'
    fixture = bin_dir / 'aerial-lock'
    fixture.write_text('#!/bin/sh\ntouch ' + shlex.quote(str(sentinel)) + '\nexit 99\n')
    fixture.chmod(0o755)
    spaced = bin_dir / 'locker with spaces'
    shutil.copy2(fixture, spaced)
    not_executable = bin_dir / 'not-executable'
    not_executable.write_text('not executable\n')
    env = environment(work)
    env['PATH'] = str(bin_dir) + ':' + os.environ['PATH']
    env['LOCK_COMMAND_TRIPWIRE'] = str(fixture)
    cases = [
        dict(name='installed', input='aerial-lock', expected='available'),
        dict(name='missing', input='atmosphera-definitely-missing-locker', expected='missing'),
        dict(name='absolute', input=str(fixture), expected='available'),
        dict(name='arguments', input='aerial-lock --flag value', expected='available'),
        dict(name='quoted-arguments', input='aerial-lock --name "hello world"', expected='available'),
        dict(name='quoted-executable', input=shlex.quote(str(spaced)) + ' "arg x"', expected='available'),
        dict(name='escaped-executable', input=str(spaced).replace(' ', '\\ '), expected='available'),
        dict(name='tab', input='  aerial-lock\t--flag', expected='available'),
        dict(name='not-executable', input=str(not_executable), expected='missing'),
        dict(name='empty', input='', expected='empty'),
        dict(name='whitespace', input=' \t ', expected='empty'),
        dict(name='unclosed-quote', input='"aerial-lock', expected='unverified'),
        dict(name='shell-expression', input='aerial-lock || other-locker', expected='unverified'),
        dict(name='assignment', input='VAR=value aerial-lock', expected='unverified'),
        dict(name='substitution', input='$(touch ' + str(sentinel) + ')', expected='unverified'),
        dict(name='injection', input='missing; touch ' + str(sentinel), expected='unverified'),
    ]
    if not args.baseline_page:
        helper = shell / 'Scripts/python/check-external-command.py'
        for case in cases:
            result = subprocess.run(['python3', '-B', str(helper), case['input']], env=env,
                                    capture_output=True, text=True, timeout=5, check=True)
            assert result.stdout.strip() == case['expected'], (case, result)
        cases.extend([
            dict(name='rapid-stale-result', input='aerial-lock', expected='missing', rapid=True,
                 checker=['python3', '-c', 'import time; time.sleep(1); print("available")']),
            dict(name='rapid-stale-ABA', input='aerial-lock', expected='available', rapid=True, aba=True,
                 checker=['python3', '-c', 'import time; time.sleep(1); print("missing")']),
            dict(name='before-install', input=str(bin_dir / 'installed-later'), expected='missing'),
            dict(name='reopen-after-install', input=str(bin_dir / 'installed-later'), expected='available', install=str(bin_dir / 'installed-later')),
            dict(name='checker-start-failure', input='aerial-lock', expected='error', checker=[str(work / 'no-checker')]),
            dict(name='checker-exit-failure', input='aerial-lock', expected='error', checker=['python3', '-c', 'raise SystemExit(2)']),
            dict(name='checker-invalid-output', input='aerial-lock', expected='error', checker=['python3', '-c', 'print("garbage")']),
            dict(name='checker-timeout', input='aerial-lock', expected='error', checker=['python3', '-c', 'import time; time.sleep(30)']),
            dict(name='recovery', input='aerial-lock', expected='available'),
        ])
        entry = shell / 'command-check.qml'
        entry.write_text(ASYNC.replace('CASES', json.dumps(cases)))
        async_work = work / 'async'
        async_work.mkdir()
        execution = run_harness(['dbus-run-session', '--', 'qs', '-p', str(entry), '--no-color'], async_work, env, 45)
        log = (async_work / 'shell.log').read_text()
        passed = execution['exit_code'] == 0 and log.count('CHECK_PASS ') == len(cases) and not re.search(r'CHECK_FAIL|TypeError:|ReferenceError:', log)
        write_receipt(async_work, dict(passed=passed, cases=len(cases)), execution)
        assert passed, log
    entry = shell / 'shell.qml'
    entry.write_text(inject_probe(entry.read_text(), PAGE))
    page_work = work / 'page'
    page_work.mkdir()
    identifier = 'atmosphera-lock-command-' + work.name
    execution = run_harness(['dbus-run-session', '--', 'systemd-cat', '--identifier=' + identifier,
                             'qs', '-p', str(shell), '--no-color'], page_work, env, 35)
    # Read the actual child journal, not just a startup marker or launcher log.
    log = ''
    for _ in range(20):
        journal = subprocess.run(['journalctl', '--user', '--identifier=' + identifier, '--no-pager', '-o', 'cat'],
                                 capture_output=True, text=True, timeout=5, check=True)
        log = journal.stdout
        if 'PAGE_COMPLETE' in log or 'PAGE_TIMEOUT' in log:
            break
        time.sleep(0.1)
    (page_work / 'journal.log').write_text(log)
    errors = [line for line in log.splitlines() if re.search(r'TypeError:|ReferenceError:|SyntaxError:|Failed to load configuration', line)]
    markers = ['PAGE_AVAILABLE', 'PAGE_MISSING', 'PAGE_EMPTY', 'PAGE_REOPEN_AVAILABLE', 'PAGE_COMPLETE']
    passed = execution['exit_code'] == 0 and not errors and all(marker in log for marker in markers) and not sentinel.exists()
    write_receipt(page_work, dict(passed=passed, markers=[marker for marker in markers if marker in log], qml_errors=errors,
                                 locker_executed=sentinel.exists()), execution)
    print(json.dumps(dict(passed=passed, qml_errors=errors, locker_executed=sentinel.exists()), indent=2))
    if not passed:
        print(log[-16000:])
    if passed and not args.baseline_page:
        entry = shell / 'language-check.qml'
        entry.write_text(LANGUAGE)
        language_work = work / 'language'
        language_work.mkdir()
        execution = run_harness(['dbus-run-session', '--', 'qs', '-p', str(entry), '--no-color'], language_work, env, 15)
        text = (language_work / 'shell.log').read_text()
        passed = execution['exit_code'] == 0 and 'LANGUAGE_AUTOMATIC_COMPLETE' in text and not re.search(r'TypeError:|ReferenceError:', text)
        write_receipt(language_work, dict(passed=passed), execution)
        if not passed:
            print(text[-12000:])
    return 0 if passed else 1


if __name__ == '__main__':
    raise SystemExit(main())
