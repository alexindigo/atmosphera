// Real generic page, native owners, Main and rendered Panel/Bar consumers.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins
import qs.Widgets

ShellRoot {
  id: root
  readonly property string scope: Quickshell.env("PHA_HELLO_SCOPE")
  readonly property string mode: Quickshell.env("PHA_HELLO_MODE")
  readonly property string boundary: Quickshell.env("PHA_HELLO_BOUNDARY")
  property bool started: false
  property string phase: "startup"
  property double phaseStarted: Date.now()
  onPhaseChanged: phaseStarted = Date.now()
  property var api: null
  property var selected: null
  property var sibling: null
  property var inherited: null
  property var presentations: []
  property var receipt: null
  property string afterDisk: ""
  property int resetIndex: 0
  readonly property var keys: ["message", "iconColor"]
  FileView {
    id: manifestFile
    path: Settings.configDir + "plugins/hello-world/manifest.json"
    blockLoading: true
  }
  FileView {
    id: dictionaryFile
    path: Settings.configDir + "plugins/hello-world/i18n/en.json"
    blockLoading: true
  }
  FileView {
    id: expectedFile
    path: Quickshell.env("PHA_HELLO_CASE") + "/expectations.json"
    blockLoading: true
  }
  Process {
    id: disk
    onExited: function (code) {
      if (code !== 0)
        root.fail("HELLO_DISK " + phase);
      else
        root.phase = root.afterDisk;
    }
  }
  PanelWindow {
    id: host
    visible: true
    implicitWidth: 1280
    implicitHeight: 800
    Item {
      id: content
      width: 1280
      height: 800
    }
    NPluginSettingsPopup {
      id: popup
      screen: Quickshell.screens[0]
      onSettingsCompleted: result => root.receipt = result
    }
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("HELLO_ASSERT: " + scope + "/" + mode + "/" + phase + ": " + message);
  }
  function fail(error) {
    console.error(String(error) + "\n" + (error.stack || ""));
    Qt.exit(2);
  }
  function find(object, predicate) {
    if (object && predicate(object))
      return object;
    for (var list of [object?.data, object?.children]) {
      if (!list)
        continue;
      for (var child of list) {
        var result = find(child, predicate);
        if (result)
          return result;
      }
    }
    return null;
  }
  function create(entry, context) {
    var component = Qt.createComponent("file://" + api.pluginDir + "/" + api.manifest.entryPoints[entry]);
    check(component.status === Component.Ready, component.errorString());
    var item = PluginLoader.createObject("hello-world", entry, component, entry === "main" ? root : content, context, {
                                           screen: Quickshell.screens[0]
                                         });
    check(item !== null, "actual " + entry + " created");
    return item;
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    manifestFile.waitForJob();
    dictionaryFile.waitForJob();
    var manifest = JSON.parse(manifestFile.text());
    var dictionary = JSON.parse(dictionaryFile.text());
    Registry.installedPlugins = {
      "hello-world": manifest
    };
    Service._openSettingsOwner("hello-world", function (owner) {
      try {
        check(owner !== null, "native owner");
        api = Service.createPluginAPI("hello-world", manifest, owner, dictionary, dictionary, {});
        Service.loadedPlugins = {
          "hello-world": {
            api: api
          }
        };
        api.mainInstance = create("main", api);
        var instances = [0, 1, 2].map(function (index) {
          return PluginInstances.apiFor("hello-world", {
                                          kind: "bar",
                                          list: "global",
                                          section: "left",
                                          index: index
                                        });
        });
        selected = instances[0];
        sibling = instances[1];
        inherited = instances[2];
        phase = "runtime";
      } catch (error) {
        fail(error);
      }
    });
  }
  function values(name) {
    expectedFile.reload();
    expectedFile.waitForJob();
    var expected = JSON.parse(expectedFile.text())[name];
    var base = Object.assign({}, api.manifest.metadata.defaultSettings, expected.shared);
    return [base].concat(expected.bar.widgets.left.map(function (row) {
      return Object.assign({}, base, row.instanceSettings || {});
    }));
  }
  function observe(name) {
    var expected = values(name);
    for (var i = 0; i < presentations.length; i++) {
      var item = presentations[i], value = expected[i];
      check(item.panel.pluginApi === item.api && item.bar.pluginApi === item.api, "runtime selected API identity");
      check(item.bar.iconColorKey === value.iconColor && Qt.colorEqual(item.bar.colorFg, AtmoColor.resolveColorKey(value.iconColor)), "actual Bar foreground follows selected field");
      var messageText = find(item.panel, child => child !== item.panel && child.font !== undefined && child.font.weight === Font.Bold && Qt.colorEqual(child.color, AtmoColor.mPrimary));
      check(messageText !== null && messageText.text === value.message, "actual child Panel Text follows selected field");
    }
    console.log("HELLO_CONSUMERS " + JSON.stringify({
                                                      scope: scope,
                                                      mode: mode,
                                                      boundary: name,
                                                      values: expected
                                                    }));
  }
  function runtimeReady(name) {
    var expected = values(name);
    return presentations.every(function (item, index) {
      return item.api.pluginSettings.message === expected[index].message && item.api.pluginSettings.iconColor === expected[index].iconColor;
    });
  }
  function probe(name, next) {
    afterDisk = next;
    phase = "disk";
    disk.command = ["python3", "-B", Quickshell.env("PHA_HELLO_DISK"), Quickshell.env("PHA_HELLO_CASE"), Quickshell.env("PHA_HELLO_OUTPUT") + "/persisted", name];
    disk.running = true;
  }
  function open(next) {
    check(scope === "shared" ? popup.openPluginSettings(api.manifest, "settings") : popup.openInstanceSettings(api.manifest, selected, "settings"), "actual Settings opens");
    phase = next;
  }
  function edit() {
    var message = find(popup.settingsPage, child => child.label === api.tr("settings.message.label"));
    var color = find(popup.settingsPage, child => child.label === api.tr("settings.iconColor.label"));
    check(message && color, "actual two controls");
    message.text = "";
    message.editCommitted();
    color.selected("tertiary");
    check(popup._pageApi.field("message").value === "" && popup._pageApi.field("iconColor").value === "tertiary", "explicit two field intents");
  }
  function apply(next) {
    receipt = null;
    check(popup.applySettings(), "native Apply");
    phase = next;
  }
  function accepted() {
    return receipt && !popup.busy && receipt.status === "saved" && receipt.refreshState === "current";
  }
  function drive() {
    check(Date.now() - phaseStarted < 18000, "finite operation deadline");
    if (phase === "runtime" && selected.settingsReady && sibling.settingsReady && inherited.settingsReady) {
      presentations = [api, selected, sibling, inherited].map(function (context) {
        return {
          api: context,
          panel: create("panel", context),
          bar: create("barWidget", context)
        };
      });
      phase = "initial";
    } else if (phase === "initial") {
      var initial = mode === "edit" ? "initial" : mode === "reset" ? "edited" : mode === "follow" ? "reset" : boundary;
      if (!runtimeReady(initial))
        return;
      observe(initial);
      if (mode === "cold") {
        console.log("HELLO: COLD_PASS " + scope + " " + boundary);
        Qt.exit(0);
      } else if (mode === "edit")
        probe("initial", "open-discard");
      else if (mode === "follow")
        phase = "change-base";
      else
        open("reset-page");
    } else if (phase === "open-discard")
      open("discard-page");
    else if (phase === "discard-page" && popup.opened && popup.settingsPage) {
      check(!popup.dirty && !popup._editor.dirty, "construction has no intent");
      edit();
      observe("initial");
      check(!popup.requestClose(), "dirty Close refuses");
      popup.confirmDiscard();
      phase = "discarded";
    } else if (phase === "discarded" && !popup.opened && !popup._editor) {
      observe("initial");
      probe("discarded", "open-edit");
    } else if (phase === "open-edit")
      open("edit-page");
    else if (phase === "edit-page" && popup.opened && popup.settingsPage) {
      edit();
      apply("applied");
    } else if (phase === "applied" && accepted() && runtimeReady("edited")) {
      observe("edited");
      probe("edited", "finish");
    } else if (phase === "reset-page" && popup.opened && popup.settingsPage && !popup.busy) {
      if (resetIndex < keys.length) {
        check(popup._pageApi.field(keys[resetIndex]).reset(), "staged field Reset");
        resetIndex++;
        return;
      }
      observe("edited");
      probe("reset-staged", "reset-apply");
    } else if (phase === "reset-apply")
      apply("reset-applied");
    else if (phase === "reset-applied" && accepted() && runtimeReady("reset")) {
      observe("reset");
      probe("reset", "finish");
    } else if (phase === "change-base") {
      check(!popup.opened && !popup._editor, "no open page during base change");
      api.pluginSettings.message = "next";
      api.pluginSettings.iconColor = "secondary";
      phase = "base-saving";
      api.saveSettings(function (result) {
        try {
          check(result.status === "saved", "native base publication");
          phase = "base-changed";
        } catch (error) {
          fail(error);
        }
      });
    } else if (phase === "base-changed" && runtimeReady("following")) {
      observe("following");
      probe("following", "finish");
    } else if (phase === "finish") {
      console.log("HELLO: PASS " + scope + " " + mode);
      Qt.exit(0);
    }
  }
  Connections {
    target: Settings
    function onSettingsLoaded() {
      root.begin();
    }
  }
  Timer {
    interval: 80
    running: true
    repeat: true
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
