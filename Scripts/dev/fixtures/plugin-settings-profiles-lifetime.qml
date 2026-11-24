import QtQuick
import Quickshell
import Quickshell.Io
import "../../../Services/Plugins/PluginSettingsRead.js" as Read
import qs.Commons
import qs.Services.Plugins

ShellRoot {
  id: root
  readonly property string casePath: Quickshell.env("PHA_PROFILES_CASE")
  readonly property string mode: Quickshell.env("PHA_PROFILES_LIFE_MODE")
  property string phase: "startup"
  property double since: Date.now()
  onPhaseChanged: since = Date.now()
  property bool started: false
  property var api: null
  property var selected: null
  property var main: null
  property var panel: null
  property var client: null
  property var retainedContext: null
  property int completions: 0
  property int callbacks: 0
  property var result: null
  property bool busyRefused: false
  property bool fakeAlive: true
  property var fakeCfg: ({})
  property int fakeWrites: 0
  QtObject {
    id: fake
    property bool settingsReady: true
    property var pluginSettings: root.fakeCfg
    property var settingsContext: null
    property var manifest: ({
                              metadata: {
                                defaultSettings: {}
                              }
                            })
    property var tr: function (key) {
      return key;
    }
    property var settingsHandle: ({
                                    info: function () {
                                      return {
                                        latestInput: "fake1"
                                      };
                                    }
                                  })
    property var saveSettings: function (callback) {
      ++root.fakeWrites;
      Qt.callLater(function () {
        callback({
                   status: "saved",
                   unresolvedGroups: []
                 });
      });
    }
  }
  FileView {
    id: manifest
    path: Settings.configDir + "plugins/shell-profiles/manifest.json"
    blockLoading: true
  }
  FileView {
    id: dictionary
    path: Settings.configDir + "plugins/shell-profiles/i18n/en.json"
    blockLoading: true
  }
  FileView {
    id: requests
    path: root.casePath + "/requests.jsonl"
    blockLoading: true
  }
  Process {
    id: command
    property var callback: null
    onExited: code => {
      var cb = callback;
      callback = null;
      if (code !== 0)
        root.fail("fixture disk command");
      else if (cb)
        cb();
    }
  }
  PanelWindow {
    visible: true
    implicitWidth: 900
    implicitHeight: 850
    Item {
      id: content
      width: 900
      height: 850
    }
  }
  function check(ok, label) {
    if (!ok)
      throw new Error("PROFILES_LIFE_ASSERT: " + mode + "/" + phase + ": " + label);
  }
  function fail(error) {
    console.error(String(error) + "\n" + (error.stack || ""));
    Qt.exit(2);
  }
  function disk(argv, callback) {
    command.callback = callback;
    command.command = argv;
    command.running = true;
  }
  function find(object, predicate) {
    if (object && predicate(object))
      return object;
    for (var list of [object?.data, object?.children]) {
      if (!list || typeof list === "function" || typeof list.length !== "number")
        continue;
      for (var child of list) {
        var found = find(child, predicate);
        if (found)
          return found;
      }
    }
    return null;
  }
  function create(entry, context) {
    var component = Qt.createComponent("file://" + api.pluginDir + "/" + api.manifest.entryPoints[entry]);
    check(component.status === Component.Ready, component.errorString());
    var item = PluginLoader.createObject("shell-profiles", entry, component, content, context, {});
    check(item, "actual " + entry + " constructs");
    return item;
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    manifest.waitForJob();
    dictionary.waitForJob();
    var descriptor = JSON.parse(manifest.text()), dict = JSON.parse(dictionary.text());
    Registry.installedPlugins = {
      "shell-profiles": descriptor
    };
    Service._openSettingsOwner("shell-profiles", function (owner) {
      try {
        check(owner, "actual native profile owner");
        api = Service.createPluginAPI("shell-profiles", descriptor, owner, dict, dict, {});
        Service.loadedPlugins = {
          "shell-profiles": {
            api: api
          }
        };
        main = create("main", api);
        api.mainInstance = main;
        main.operationCompleted.connect(function (value) {
          ++root.completions;
          root.result = value;
        });
        selected = PluginInstances.apiFor("shell-profiles", {
                                            kind: "bar",
                                            list: "global",
                                            section: "left",
                                            index: 0
                                          });
        phase = "runtime";
      } catch (error) {
        fail(error);
      }
    });
  }
  function finish() {
    console.log("PROFILES_LIFETIME: PASS " + mode);
    Qt.exit(0);
  }
  function held(stage) {
    requests.reload();
    requests.waitForJob();
    return requests.text().trim().split('\n').filter(line => line.trim()).map(line => JSON.parse(line)).some(row => row.stage === stage);
  }
  function save() {
    if (mode === "native" || mode === "native-retired") {
      var input = find(panel, item => item.placeholderText === api.tr("panel.save-placeholder"));
      var button = find(panel, item => item.text === api.tr("panel.save-button") && item.clicked !== undefined);
      check(input && button, "actual Panel save controls");
      input.text = "saved";
      button.clicked();
    } else
      client.saveProfile("saved", function () {
        ++root.callbacks;
      }, fake);
    phase = "saved";
  }
  function drive() {
    check(Date.now() - since < 22000, "finite profile lifetime phase");
    if (phase === "runtime" && selected.settingsReady) {
      if (mode === "native" || mode === "native-retired") {
        panel = create("panel", selected);
        client = panel.service;
      } else {
        fakeCfg = Object.assign({}, selected.pluginSettings, {
                                  profilesDir: casePath + "/selected",
                                  backupEnabled: true,
                                  backupCount: 2
                                });
        fake.settingsContext = Read.context({
                                              alive: true
                                            }, function () {
                                              return root.fakeCfg;
                                            }, function () {
                                              return root.fakeAlive;
                                            });
        client = main.settingsConsumerFor(fake.settingsContext);
      }
      retainedContext = client.settingsContext;
      check(main.settingsConsumerFor(retainedContext) === client, "same-context listing/action identity");
      save();
    } else if (phase === "saved" && mode === "start-failure" && Date.now() - since > 800) {
      check(completions === 1 && !main.isBusy && result.status === "failed" && callbacks === 1, "failed-start settles one action and clears busy");
      finish();
    } else if (phase === "saved" && mode !== "start-failure" && completions === 1 && !main.isBusy) {
      check(result.status === "completed", "real selected raw snapshot completed");
      Settings.data.bar.position = "top";
      phase = "save-top";
      Service.synchronizePreferences("save", function (receipt) {
        try {
          check(receipt.status === "current", "raw current preimage before Apply");
          if (mode === "native-retired") {
            disk(["python3", "-c",
                  "import json,hashlib,sys;from pathlib import Path;p=Path(sys.argv[1]);b=p/'settings/bar.json';d=json.loads(b.read_bytes());d['widgets']['left']=d['widgets']['left'][1:];b.write_text(json.dumps(d));m=p/'_config-files.json';d=json.loads(m.read_bytes());d['entries']['settings/bar.json']['sha256']=hashlib.sha256(b.read_bytes()).hexdigest();m.write_text(json.dumps(d))",
                  casePath + "/selected/saved"], function () {
                    phase = "apply-ready";
                  });
          } else
            phase = "apply-ready";
        } catch (error) {
          fail(error);
        }
      });
    } else if (phase === "apply-ready") {
      if (mode === "native" || mode === "native-retired") {
        var row = find(panel, item => item.profileName === "saved" && item.service !== undefined);
        if (!row)
          return;
        var button = find(row, item => item.text === api.tr("panel.action-apply") && item.clicked !== undefined);
        check(button, "actual selected row Apply control");
        button.clicked();
        phase = "applied";
      } else {
        phase = "gate-setup";
        disk(["python3", "-c", "import sys;open(sys.argv[1],'w').write(sys.argv[2])", casePath + "/hold", mode === "pre-retired" || mode === "destroyed" ? "backup-configs.sh" : "apply-profile.sh"], function () {
          client.applyProfile("saved", false, function () {
            ++root.callbacks;
          }, fake);
          phase = "held";
          main.saveProfile("must-refuse", function (ok, message) {
            root.busyRefused = !ok && message === "profile-busy";
          }, selected);
        });
      }
    } else if (phase === "held" && held(mode === "pre-retired" || mode === "destroyed" ? "backup-configs.sh" : "apply-profile.sh")) {
      check(busyRefused, "one common serial effect owner");
      fakeCfg = Object.assign({}, fakeCfg, {
                                profilesDir: casePath + "/later",
                                backupCount: 1,
                                backupEnabled: false
                              });
      if (mode !== "held")
        fakeAlive = false;
      if (mode === "destroyed") {
        main.destroy();
        main = null;
        phase = "destroyed";
      } else {
        phase = "gate-release";
        disk(["rm", casePath + "/hold"], function () {
          phase = "applied";
        });
      }
    } else if (phase === "applied" && completions === 2 && !main.isBusy) {
      check(Settings.data.bar.position === "bottom", "real raw profile data reached isolated settings consumer");
      if (mode === "native-retired") {
        check(!selected.settingsContext.current() && result.status === "failed" && result.outcomes.files.status === "applied" && result.outcomes.lastApplied.error.code === "profile-origin-retired", "actual removed native origin refuses marker without rolling back published files");
        check(api.pluginSettings.lastAppliedProfile === "previous", "retired native action never borrows shared marker writer");
        finish();
      } else if (mode === "native") {
        check(result.status === "completed" && selected.pluginSettings.lastAppliedProfile === "saved" && api.pluginSettings.lastAppliedProfile === "previous", "originating native marker, never shared writer");
        phase = "rename";
        client.renameProfile("saved", "renamed", function (ok) {
          try {
            check(ok, "selected rename");
            phase = "renamed";
          } catch (error) {
            fail(error);
          }
        }, selected);
      } else {
        check(fakeWrites === (mode === "held" ? 1 : 0), "retired action cannot publish marker through another owner");
        check(callbacks === (mode === "held" ? 2 : 1), "retired origin cannot receive late feedback");
        check(result.status === (mode === "held" ? "completed" : "failed"), "truthful marker outcome after published raw files");
        phase = "settled";
      }
    } else if (phase === "renamed" && !main.isBusy && selected.pluginSettings.lastAppliedProfile === "renamed") {
      phase = "delete";
      client.deleteProfile("renamed", function (ok) {
        try {
          check(ok, "selected delete");
          phase = "deleted";
        } catch (error) {
          fail(error);
        }
      }, selected);
    } else if (phase === "deleted" && !main.isBusy && selected.pluginSettings.lastAppliedProfile === "") {
      check(completions === 4 && api.pluginSettings.lastAppliedProfile === "previous", "all native runtime operations preserve shared marker");
      phase = "settled";
    } else if (phase === "destroyed" && Date.now() - since > 300) {
      disk(["python3", "-c", "import json,sys;from pathlib import Path;c=Path(sys.argv[1]);rows=[json.loads(x) for x in (c/'requests.jsonl').read_text().splitlines()];assert all(not (p:=Path('/proc')/str(r['pid'])/'stat').exists() or p.read_text().split(') ',1)[1].split()[19]!=r['start'] for r in rows)", casePath], function () {
        finish();
      });
      phase = "join";
    } else if (phase === "settled") {
      if (mode !== "native" && mode !== "held") {
        check(main.settingsConsumerFor(retainedContext) === null, "retired listing cannot be reacquired");
        check(!main._settingsConsumers.has(retainedContext) && client === null, "retired listing leaves exact Main map");
        check(!main._capture(fake), "new retired action refused");
      }
      finish();
    }
  }
  Connections {
    target: Settings
    function onSettingsLoaded() {
      root.begin();
    }
  }
  Timer {
    interval: 50
    repeat: true
    running: true
    onTriggered: {
      try {
        root.drive();
      } catch (error) {
        root.fail(error);
      }
    }
  }
  Component.onCompleted: begin()
}
