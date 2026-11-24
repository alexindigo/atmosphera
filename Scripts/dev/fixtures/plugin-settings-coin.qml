// Actual page/native owner, direct timing/color and real operational result writes.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins
import qs.Widgets

ShellRoot {
  id: root
  readonly property string scope: Quickshell.env("PHA_COIN_SCOPE")
  readonly property string mode: Quickshell.env("PHA_COIN_MODE")
  readonly property string boundary: Quickshell.env("PHA_COIN_BOUNDARY")
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
  property string diskBoundary: ""
  property var operationPanel: null
  property int operationIndex: 0
  FileView {
    id: manifestFile
    path: Settings.configDir + "plugins/coin-flip/manifest.json"
    blockLoading: true
  }
  FileView {
    id: dictionaryFile
    path: Settings.configDir + "plugins/coin-flip/i18n/en.json"
    blockLoading: true
  }
  FileView {
    id: expectedFile
    path: Quickshell.env("PHA_COIN_CASE") + "/expectations.json"
    blockLoading: true
  }
  FileView {
    id: operationFile
    path: root.boundary === "operation-3" ? Quickshell.env("PHA_COIN_OUTPUT") + "/persisted/operation-3.json" : ""
    blockLoading: true
  }
  Process {
    id: disk
    onExited: function (code) {
      if (code !== 0)
        root.fail("COIN_DISK " + root.diskBoundary);
      else
        root.phase = root.afterDisk;
    }
  }
  PanelWindow {
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
      throw new Error("COIN_ASSERT: " + scope + "/" + mode + "/" + phase + ": " + message);
  }
  function fail(error) {
    console.error(String(error) + "\n" + (error.stack || ""));
    Qt.exit(2);
  }
  function find(object, predicate) {
    if (object && predicate(object))
      return object;
    for (var list of [object?.data, object?.children]) {
      if (!list || typeof list === "function" || typeof list.length !== "number")
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
    var item = PluginLoader.createObject("coin-flip", entry, component, content, context, {
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
    var manifest = JSON.parse(manifestFile.text()), dictionary = JSON.parse(dictionaryFile.text());
    Registry.installedPlugins = {
      "coin-flip": manifest
    };
    Service._openSettingsOwner("coin-flip", function (owner) {
      try {
        check(owner !== null, "native owner");
        api = Service.createPluginAPI("coin-flip", manifest, owner, dictionary, dictionary, {});
        Service.loadedPlugins = {
          "coin-flip": {
            api: api
          }
        };
        var instances = [0, 1, 2].map(index => PluginInstances.apiFor("coin-flip", {
                                                                        kind: "bar",
                                                                        list: "global",
                                                                        section: "left",
                                                                        index: index
                                                                      }));
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
    var expected;
    if (name === "operation-3") {
      operationFile.reload();
      operationFile.waitForJob();
      expected = JSON.parse(operationFile.text()).values;
    } else {
      expectedFile.reload();
      expectedFile.waitForJob();
      expected = JSON.parse(expectedFile.text())[name];
    }
    var base = Object.assign({}, api.manifest.metadata.defaultSettings, expected.shared);
    return [base].concat(expected.bar.widgets.left.map(row => Object.assign({}, base, row.instanceSettings || {})));
  }
  function ready(name) {
    var expected = values(name);
    return presentations.every((item, index) => ["delay", "iconColor", "lastResult"].every(key => item.api.pluginSettings[key] === expected[index][key]));
  }
  function observe(name) {
    var expected = values(name);
    for (var i = 0; i < presentations.length; i++) {
      var item = presentations[i], value = expected[i], panel = create("panel", item.api);
      var timer = find(panel, child => child.repeat === true && child.triggered !== undefined);
      check(panel.pluginApi === item.api && timer && timer.interval === value.delay && timer.running, "actual animation Timer follows selected delay");
      check(item.bar.iconColorKey === value.iconColor && Qt.colorEqual(item.bar.colorFg, AtmoColor.resolveColorKey(value.iconColor)), "actual Bar foreground follows selected configuration");
      var text = find(panel, child => child.font !== undefined && child.font.weight === Font.Bold && child.font.pointSize === Style.fontSizeXL);
      check(text && text.text === "", "nonediting Panel reader precedes unrequested initial result");
      panel.destroy();
    }
    console.log("COIN_CONSUMERS " + JSON.stringify({
                                                     scope: scope,
                                                     mode: mode,
                                                     boundary: name,
                                                     values: expected
                                                   }));
  }
  function probe(name, next, result) {
    afterDisk = next;
    diskBoundary = name;
    phase = "disk";
    disk.command = ["python3", "-B", Quickshell.env("PHA_COIN_DISK"), Quickshell.env("PHA_COIN_CASE"), Quickshell.env("PHA_COIN_OUTPUT") + "/persisted", name, result || ""];
    disk.running = true;
  }
  function open(next) {
    check(scope === "shared" ? popup.openPluginSettings(api.manifest, "settings") : popup.openInstanceSettings(api.manifest, selected, "settings"), "actual Settings opens");
    phase = next;
  }
  function edit() {
    var slider = find(popup.settingsPage, child => child.objectName === "settings-range-delay");
    check(slider, "actual delay Slider");
    slider.value = 6;
    slider.moved();
    check(popup._pageApi.field("delay").value === 6 && !popup._pageApi.field("iconColor").pendingIntent, "single explicit delay intent leaves undisplayed color untouched");
    check(popup._pageApi.pluginSettings.lastResult.indexOf("seed-") === 0, "operational result remains readable without configuration intent");
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
      presentations = [api, selected, sibling, inherited].map(context => ({
        api: context,
        bar: create("barWidget", context)
      }));
      phase = "initial";
    } else if (phase === "initial") {
      var initial = mode === "edit" ? "initial" : mode === "reset" ? "edited" : mode === "follow" ? "reset" : mode === "operation" ? "following" : boundary;
      if (!ready(initial))
        return;
      observe(initial);
      if (mode === "cold") {
        console.log("COIN: COLD_PASS " + scope + " " + boundary);
        Qt.exit(0);
      } else if (mode === "edit")
        probe("initial", "open-discard");
      else if (mode === "follow")
        phase = "change-base";
      else if (mode === "operation")
        phase = "operation-start";
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
    } else if (phase === "discarded" && !popup.opened && !popup._editor)
      probe("discarded", "open-edit");
    else if (phase === "open-edit")
      open("edit-page");
    else if (phase === "edit-page" && popup.opened && popup.settingsPage) {
      edit();
      apply("applied");
    } else if (phase === "applied" && accepted() && ready("edited")) {
      observe("edited");
      probe("edited", "finish");
    } else if (phase === "reset-page" && popup.opened && popup.settingsPage && !popup.busy) {
      check(popup._pageApi.field("delay").reset(), "staged delay Reset");
      observe("edited");
      probe("reset-staged", "reset-apply");
    } else if (phase === "reset-apply")
      apply("reset-applied");
    else if (phase === "reset-applied" && accepted() && ready("reset")) {
      observe("reset");
      probe("reset", "finish");
    } else if (phase === "change-base") {
      api.pluginSettings.delay = 31;
      api.pluginSettings.iconColor = "mTertiary";
      phase = "base-saving";
      api.saveSettings(function (result) {
        try {
          check(result.status === "saved", "native base publication");
          phase = "base-changed";
        } catch (error) {
          fail(error);
        }
      });
    } else if (phase === "base-changed" && ready("following")) {
      observe("following");
      probe("following", "finish");
    } else if (phase === "operation-start") {
      if (operationIndex === 4) {
        phase = "finish";
        return;
      }
      operationPanel = create("panel", presentations[operationIndex].api);
      phase = "operation-running";
    } else if (phase === "operation-running") {
      var coin = find(operationPanel, child => child.frameIndex !== undefined && child.flipFrames !== undefined);
      check(coin, "actual animation owner");
      if (!coin.showResult)
        return;
      check(!coin.flipping && coin.frameIndex === 36 && ["Heads", "Tails"].indexOf(coin.resultString) !== -1, "real Timer completes all animation frames");
      var text = find(operationPanel, child => child.font !== undefined && child.font.weight === Font.Bold && child.font.pointSize === Style.fontSizeXL);
      check(text && text.text === coin.resultString, "actual child result Text follows finished animation");
      var image = find(coin, child => child.source !== undefined && child.fillMode !== undefined);
      check(image && String(image.source).endsWith(coin.resultString === "Heads" ? "/heads.svg" : "/tails.svg"), "actual result Image follows finished animation");
      probe("operation-" + operationIndex, "operation-saved", coin.resultString);
    } else if (phase === "operation-saved") {
      console.log("COIN_OPERATION " + operationIndex);
      operationPanel.destroy();
      operationPanel = null;
      operationIndex++;
      phase = "operation-start";
    } else if (phase === "finish") {
      console.log("COIN: PASS " + scope + " " + mode);
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
