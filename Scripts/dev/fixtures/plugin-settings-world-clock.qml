// Real Main, generic page/native owners and selected rendered Bar clocks.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins
import qs.Widgets

ShellRoot {
  id: root
  readonly property string scope: Quickshell.env("PHA_WORLD_SCOPE")
  readonly property string mode: Quickshell.env("PHA_WORLD_MODE")
  readonly property string boundary: Quickshell.env("PHA_WORLD_BOUNDARY")
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
  property int rotationIndex: -1
  property int siblingRotationIndex: -1
  readonly property var keys: ["rotationInterval", "timeFormat"]
  FileView {
    id: manifestFile
    path: Settings.configDir + "plugins/world-clock/manifest.json"
    blockLoading: true
  }
  FileView {
    id: dictionaryFile
    path: Settings.configDir + "plugins/world-clock/i18n/en.json"
    blockLoading: true
  }
  FileView {
    id: expectedFile
    path: Quickshell.env("PHA_WORLD_CASE") + "/expectations.json"
    blockLoading: true
  }
  Process {
    id: disk
    onExited: function (code) {
      if (code !== 0)
        root.fail("WORLD_DISK " + root.phase);
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
      throw new Error("WORLD_ASSERT: " + scope + "/" + mode + "/" + phase + ": " + message);
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
    var item = PluginLoader.createObject("world-clock", entry, component, entry === "main" ? root : content, context, {
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
      "world-clock": manifest
    };
    Service._openSettingsOwner("world-clock", function (owner) {
      try {
        check(owner !== null, "native owner");
        api = Service.createPluginAPI("world-clock", manifest, owner, dictionary, dictionary, {});
        Service.loadedPlugins = {
          "world-clock": {
            api: api
          }
        };
        api.mainInstance = create("main", api);
        var instances = [0, 1, 2].map(function (index) {
          return PluginInstances.apiFor("world-clock", {
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
    var expected = JSON.parse(expectedFile.text())[name], base = Object.assign({}, api.manifest.metadata.defaultSettings, expected.shared);
    return [base].concat(expected.bar.widgets.left.map(row => Object.assign({}, base, row.instanceSettings || {})));
  }
  function timeFor(zone, format) {
    var hours = {
      "America/New_York": "01:11",
      "Europe/London": "02:22",
      "Asia/Tokyo": "03:33",
      "Australia/Sydney": "04:44"
    };
    return hours[zone] + (format.indexOf("ss") !== -1 ? ":33" : "") + (format.indexOf("A") !== -1 ? " AM" : "");
  }
  function ready(name) {
    var expected = values(name);
    return presentations.every(function (item, index) {
      return keys.every(key => item.api.pluginSettings[key] === expected[index][key]) && item.bar.currentTime.length > 0;
    });
  }
  function settled(name) {
    var expected = values(name);
    return presentations.every(function (item, index) {
      var timezone = expected[index].timezones[item.bar.currentIndex];
      return timezone && item.bar.currentCity === timezone.name && item.bar.currentTime === timeFor(timezone.timezone, expected[index].timeFormat);
    });
  }
  function observe(name) {
    var expected = values(name);
    for (var i = 0; i < presentations.length; i++) {
      var item = presentations[i], value = expected[i];
      var timer = find(item.bar, child => child.interval !== undefined && child.repeat === true && child.triggered !== undefined);
      check(timer && timer.interval === value.rotationInterval && timer.running, "actual rotation Timer follows selected interval");
      check(item.bar.pluginApi === item.api && item.bar.timezones.length === value.timezones.length && item.bar.timezones.every((zone, index) => ["name", "timezone", "enabled"].every(key => zone[key] === value.timezones[index][key])), "actual selected timezone collection preserved");
      var timeText = find(item.bar, child => child !== item.bar && child.font !== undefined && child.font.weight === Font.Bold);
      check(timeText && timeText.text === item.bar.currentTime, "actual child time Text follows selected result");
      var cityText = find(item.bar, child => child !== item.bar && child.font !== undefined && child.text === item.bar.currentCity);
      check(cityText !== null, "actual child city Text follows selected result");
    }
    console.log("WORLD_CONSUMERS " + JSON.stringify({
                                                      scope: scope,
                                                      mode: mode,
                                                      boundary: name,
                                                      values: expected
                                                    }));
  }
  function probe(name, next) {
    afterDisk = next;
    phase = "disk";
    disk.command = ["python3", "-B", Quickshell.env("PHA_WORLD_DISK"), Quickshell.env("PHA_WORLD_CASE"), Quickshell.env("PHA_WORLD_OUTPUT") + "/persisted", name];
    disk.running = true;
  }
  function open(next) {
    check(scope === "shared" ? popup.openPluginSettings(api.manifest, "settings") : popup.openInstanceSettings(api.manifest, selected, "settings"), "actual Settings opens");
    phase = next;
  }
  function edit() {
    var spin = find(popup.settingsPage, child => child.suffix === " s" && typeof child.submitValue === "function");
    var format = find(popup.settingsPage, child => child.selected !== undefined && child.currentKey === popup.settingsPage.timeFormat);
    check(spin && format, "actual seconds SpinBox and time format combo");
    spin.submitValue(1);
    format.selected("HH:mm:ss");
    check(popup._pageApi.field("rotationInterval").value === 1000 && popup._pageApi.field("timeFormat").value === "HH:mm:ss", "explicit finite intents and seconds conversion");
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
      var initial = mode === "edit" ? "initial" : mode === "reset" ? "edited" : mode === "follow" ? "reset" : boundary;
      if (!ready(initial))
        return;
      observe(initial);
      if (!settled(initial))
        return;
      if (mode === "cold") {
        console.log("WORLD: COLD_PASS " + scope + " " + boundary);
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
    } else if (phase === "applied" && accepted() && ready("edited")) {
      observe("edited");
      if (!settled("edited"))
        return;
      rotationIndex = presentations[scope === "shared" ? 0 : 1].bar.currentIndex;
      siblingRotationIndex = presentations[2].bar.currentIndex;
      probe("edited", "wait-rotation");
    } else if (phase === "wait-rotation" && presentations[scope === "shared" ? 0 : 1].bar.currentIndex !== rotationIndex && settled("edited")) {
      observe("edited");
      console.log("WORLD_ROTATION " + JSON.stringify({
                                                       before: rotationIndex,
                                                       after: presentations[scope === "shared" ? 0 : 1].bar.currentIndex
                                                     }));
      phase = "wait-sibling-rotation";
    } else if (phase === "wait-sibling-rotation" && presentations[2].bar.currentIndex !== siblingRotationIndex && settled("edited")) {
      observe("edited");
      console.log("WORLD_SIBLING_ROTATION " + JSON.stringify({
                                                               before: siblingRotationIndex,
                                                               after: presentations[2].bar.currentIndex
                                                             }));
      phase = "finish";
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
    else if (phase === "reset-applied" && accepted() && ready("reset")) {
      observe("reset");
      if (settled("reset"))
        probe("reset", "finish");
    } else if (phase === "change-base") {
      api.pluginSettings.rotationInterval = 2000;
      api.pluginSettings.timeFormat = "h:mm:ss A";
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
      if (settled("following"))
        probe("following", "finish");
    } else if (phase === "finish") {
      console.log("WORLD: PASS " + scope + " " + mode);
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
