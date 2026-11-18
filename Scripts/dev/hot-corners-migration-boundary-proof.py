#!/usr/bin/env python3
"""Guest-only controlled receipts against the actual registry migration methods.

Only startup and external receipts are controlled. The planner, read commands,
settings wait, assignment and completion methods come from the supplied source.
The regular migration regression separately proves real profile persistence.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess

from presentation_harness import check_execution_paths, run_harness


CONTROLS = r'''
  property string scenario: Quickshell.env("MIGRATION_REVIEW_CASE")
  property bool completed: false
  property bool backedUp: false
  property bool removed: false
  property var written: []
  property int saves: 0
  property int reads: 0
  property bool scanned: false

  function _backupV6(plan, backupDir, done) {
    backedUp = true;
    if (scenario === "late-core")
      Settings.data.general.hotCorners.topLeft = "new core command";
    done(true);
  }
  function _saveV6Corners(paths, done) { written = paths; done(true); }
  function _removeV6Files(plan, done) { removed = true; done(true); }
  function _backupV5(plan, backupDir, done) { backedUp = true; done(true); }
  function _moveV5Files(plan, done) { removed = true; done(true); }
  function save() { saves++; }
  function runProcess(name, command, done) {
    if (name === "ReadMigrationInput") reads++;
    _nativeRunProcess(name, command, done);
  }
  function _whenSettingsLoaded(callback) {
    _nativeWhenSettingsLoaded(callback);
    // Schedule only after the actual wait has connected, not while earlier
    // input reads are still running. A second terminal signal must not re-enter.
    if (scenario === "settings-error-later")
      Qt.callLater(function () {
        Settings.store.status = ConfigStore.Error;
        Settings.isLoaded = true;
        Settings.settingsLoaded();
      });
    else if (scenario === "settings-ready-later")
      Qt.callLater(function () { Settings.isLoaded = true; Settings.settingsLoaded(); });
  }
  function finish() { completed = true; }
  function startup() {
    migratePluginData(function () {
      scanPluginFolder(function (ok) { scanned = ok; completed = ok; });
    });
  }

  Component.onCompleted: {
    pluginStates = {"builtin:hot-corners": {enabled: true, sourceUrl: "file:///old/Plugins"}};
    installedPlugins = {"builtin:hot-corners": {id: "hot-corners"}};
    _loadedVersion = 5;
    _v6Pending = true;
    if (scenario === "v5-held") {
      var plan = PluginProfileMigration.planV5({states: pluginStates, sources: [], shippedIds: [],
        builtinSourceUrl: "file:///new/builtin/plugins", currentHash: "abcdef", pluginSettingsFiles: []});
      completed = !!plan.states["builtin:hot-corners"] && plan.removals.length === 0 && plan.rekeys.length === 0;
    } else if (scenario === "unsafe-key") {
      pluginStates = {"../../outside:hot-corners": {enabled: true}};
      var rejected = PluginProfileMigration.planV6({states: pluginStates});
      if (rejected.removals.length !== 0) return;
      migrateV6(finish);
    } else if (scenario === "no-work" || scenario === "v5-pending") {
      pluginStates = {};
      _v5Pending = scenario === "v5-pending";
      migrateV6(finish);
    } else if (scenario === "late-core") {
      _applyV6({corners: {topLeft: "old plugin command", bottomRight: "plugin br"},
        removals: ["builtin:hot-corners"], files: [], warnings: []}, finish);
    } else if (scenario === "settings-error") {
      Settings.isLoaded = false;
      Settings.store.status = ConfigStore.Error;
      startup();
    } else if (scenario === "settings-error-later") {
      Settings.isLoaded = false;
      startup();
    } else if (scenario === "v5-settings-error") {
      Settings.isLoaded = false;
      Settings.store.status = ConfigStore.Error;
      pluginStates = {"builtin:clock": {enabled: true, sourceUrl: "file:///old/Plugins"}};
      _v5Pending = true;
      _planV5Migration(["clock"], [], finish);
    } else if (scenario === "settings-ready-later") {
      Settings.isLoaded = false;
      migrateV6(finish);
    } else if (scenario === "read-error") {
      startup();
    } else {
      migrateV6(finish);
    }
  }

  Timer {
    interval: 500; running: true
    onTriggered: {
      var corners = Settings.data.general.hotCorners;
      var passed;
      if (root.scenario === "v5-held")
        passed = root.completed;
      else if (root.scenario === "unsafe-key")
        passed = root.completed && !root.backedUp && !root.removed && root.reads === 0;
      else if (root.scenario === "no-work" || root.scenario === "v5-pending")
        passed = root.completed && !root._v6Pending && root.saves === (root.scenario === "no-work" ? 1 : 0);
      else if (root.scenario === "v5-settings-error")
        passed = root.completed && root._v5Pending && !root.backedUp && !root.removed;
      else if (root.scenario === "late-core")
        passed = root.completed && corners.topLeft === "new core command" && corners.bottomRight === "plugin br"
          && root.written.length === 1 && root.written[0][2] === "bottomRight" && root.removed
          && !root.installedPlugins["builtin:hot-corners"];
      else if (root.scenario.indexOf("settings-error") === 0 || root.scenario === "read-error")
        passed = root.completed && root.scanned && root._v6Pending && !root.backedUp && !root.removed
          && !!root.pluginStates["builtin:hot-corners"] && corners.topLeft === "";
      else
        passed = root.completed && !root._v6Pending && root.removed && corners.topLeft === "legacy command";
      console.log("MIGRATION_BOUNDARY|" + JSON.stringify({scenario: root.scenario, passed: !!passed,
        completed: root.completed, backedUp: root.backedUp, removed: root.removed,
        pending: root._v6Pending, scanned: root.scanned, saves: root.saves, reads: root.reads,
        corners: corners, written: root.written}));
      Qt.exit(passed ? 0 : 1);
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
    if subprocess.check_output(['id', '-un'], text=True).strip() != 'tester':
        parser.error('requires the assigned tester guest')
    actual = subprocess.check_output(['sudo', '-n', 'cat', '/sys/class/dmi/id/product_uuid'], text=True).strip().lower()
    if actual != os.environ['ACTION_TEST_VM_UUID'].lower():
        parser.error('wrong guest UUID')
    work.mkdir()
    tree = work / 'shell'
    for rel in ('Helpers/PluginProfileMigration.js', 'Helpers/sha256.js'):
        (tree / rel).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(args.source / rel, tree / rel)
    commons = tree / 'Commons'
    commons.mkdir()
    (commons / 'qmldir').write_text('module qs.Commons\nsingleton Settings 1.0 Settings.qml\nsingleton Logger 1.0 Logger.qml\n')
    (commons / 'Logger.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { function i() {} function d() {} function w() {} function e() {} }\n')
    (commons / 'Settings.qml').write_text('''pragma Singleton
import QtQuick
import Quickshell
QtObject {
  property string configDir: Quickshell.env("MIGRATION_REVIEW_PROFILE") + "/"
  property string stateDir: configDir
  property bool isLoaded: true
  property QtObject store: QtObject { property int status: 0 }
  property var data: ({general: {hotCorners: {topLeft: "", topRight: "", bottomLeft: "", bottomRight: ""}}})
  signal settingsLoaded
}
''')
    text = (args.source / 'Services/Plugins/Registry.qml').read_text()
    startup = '  Component.onCompleted: {\n    ensurePluginsDirectory();\n    bootstrap();\n  }'
    if text.count(startup) != 1:
        raise RuntimeError('registry startup boundary changed')
    text = text.replace('pragma Singleton', 'import ConfigQml 1.0', 1).replace('Singleton {', 'ShellRoot {', 1)
    text = text.replace(startup, '')
    for name in ('_backupV6', '_saveV6Corners', '_removeV6Files', '_backupV5', '_moveV5Files', 'save'):
        text = text.replace('function ' + name + '(', 'function _unused_' + name + '(', 1)
    text = text.replace('function runProcess(', 'function _nativeRunProcess(', 1)
    text = text.replace('function _whenSettingsLoaded(', 'function _nativeWhenSettingsLoaded(', 1)
    # Keep the original file depth for its relative helper imports.
    target = tree / 'Services/Plugins/RegistryProof.qml'
    target.parent.mkdir(parents=True)
    target.write_text(text.rstrip()[:-1] + CONTROLS + '\n}\n')
    (tree / 'shell.qml').write_text('import QtQuick\nimport Quickshell\nimport "Services/Plugins"\nShellRoot { RegistryProof {} }\n')
    results = []
    for scenario in ('v5-held', 'late-core', 'settings-error', 'settings-error-later', 'v5-settings-error',
                     'settings-ready-later', 'read-error', 'legacy-absent-primary', 'unsafe-key', 'no-work', 'v5-pending'):
        run = work / scenario
        run.mkdir()
        profile = run / 'profile'
        primary = profile / 'settings/plugins/builtin:hot-corners.json'
        primary.parent.mkdir(parents=True)
        legacy = profile / 'plugins/builtin:hot-corners/settings.json'
        legacy.parent.mkdir(parents=True)
        legacy.write_text(json.dumps({'corners': {'TopLeft': 'legacy command'}}))
        (legacy.parent / 'manifest.json').write_text(json.dumps(dict(id='hot-corners', name='Hot Corners', version='0.0.7',
            author='synthetic', description='Controlled migration fixture', entryPoints={})))
        if scenario == 'read-error':
            primary.write_text(json.dumps({'corners': {'TopLeft': 'unreadable command'}}))
            primary.chmod(0)
        env = dict(os.environ, QT_QPA_PLATFORM='offscreen', MIGRATION_REVIEW_CASE=scenario,
                   MIGRATION_REVIEW_PROFILE=str(profile))
        try:
            execution = run_harness(['dbus-run-session', '--', 'qs', '-p', str(tree), '--no-color'], run, env, 20)
        finally:
            if primary.exists():
                primary.chmod(0o600)
        log = (run / 'shell.log').read_text()
        marker = next((json.loads(line.split('MIGRATION_BOUNDARY|', 1)[1]) for line in log.splitlines()
                       if 'MIGRATION_BOUNDARY|' in line), {})
        row = dict(scenario=scenario, observed=marker, execution=execution,
                   passed=bool(marker.get('passed')) and execution['exit_code'] == 0 and execution['cleanup_complete'])
        results.append(row)
        print(json.dumps(row), flush=True)
    (work / 'result.json').write_text(json.dumps(dict(passed=all(row['passed'] for row in results), cases=results), indent=2))
    return 0 if all(row['passed'] for row in results) else 1


if __name__ == '__main__':
    raise SystemExit(main())
