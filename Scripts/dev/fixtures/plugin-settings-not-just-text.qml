// Actual page/native owners, Main and selected file/fortune child Bar Text.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins
import qs.Services.UI
import qs.Widgets

ShellRoot {
  id: root
  readonly property string scope: Quickshell.env("PHA_TEXT_SCOPE")
  readonly property string mode: Quickshell.env("PHA_TEXT_MODE")
  readonly property string boundary: Quickshell.env("PHA_TEXT_BOUNDARY")
  readonly property bool oldRed: Quickshell.env("PHA_TEXT_OLD_RED") === "1"
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
  property var failedEditor: null
  property var failedPage: null
  property var retiredContext: null
  property real wallpaperStarted: 0
  property string afterDisk: ""
  property int resetIndex: 0
  readonly property var keys: ["text", "fortuneEnabled", "fortuneOffensive", "fortuneEqual", "fortuneCategory", "fortuneMaxLength", "listEnabled", "textFile", "refreshOnWallpaper"]
  FileView {
    id: manifestFile
    path: Settings.configDir + "plugins/not-just-text/manifest.json"
    blockLoading: true
  }
  FileView {
    id: dictionaryFile
    path: Settings.configDir + "plugins/not-just-text/i18n/en.json"
    blockLoading: true
  }
  FileView {
    id: expectedFile
    path: Quickshell.env("PHA_TEXT_CASE") + "/expectations.json"
    blockLoading: true
  }
  FileView {
    id: heldFile
    path: Quickshell.env("PHA_TEXT_CASE") + "/held"
  }
  Process {
    id: disk
    onExited: function (code) {
      if (code !== 0)
        root.fail("TEXT_DISK " + root.phase);
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
      throw new Error("TEXT_ASSERT: " + scope + "/" + mode + "/" + phase + ": " + message);
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
    var item = PluginLoader.createObject("not-just-text", entry, component, entry === "main" ? root : content, context, {
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
      "not-just-text": manifest
    };
    Service._openSettingsOwner("not-just-text", function (owner) {
      try {
        check(owner !== null, "native owner");
        api = Service.createPluginAPI("not-just-text", manifest, owner, dictionary, dictionary, {});
        Service.loadedPlugins = {
          "not-just-text": {
            api: api
          }
        };
        api.mainInstance = create("main", api);
        var instances = [0, 1, 2].map(index => PluginInstances.apiFor("not-just-text", {
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
    expectedFile.reload();
    expectedFile.waitForJob();
    var expected = JSON.parse(expectedFile.text())[name], base = Object.assign({}, api.manifest.metadata.defaultSettings, expected.shared);
    return [base].concat(expected.bar.widgets.left.map(row => Object.assign({}, base, row.instanceSettings || {})));
  }
  function textFor(value) {
    return value.fortuneEnabled ? value.fortuneCategory === "oversized" ? api.tr("fortune.gaveUp") : "fortune-" + value.fortuneCategory : value.listEnabled ? "selected-file" : value.text;
  }
  function ready(name) {
    var expected = values(name);
    return presentations.every(function (item, index) {
      var value = expected[index];
      return keys.every(key => item.api.pluginSettings[key] === value[key]) && (oldRed || !value.fortuneEnabled && !value.listEnabled || (value.fortuneEnabled ? item.bar.main?.fortuneText?.length > 0 : item.bar.main?.listText?.length > 0));
    });
  }
  function observe(name) {
    var expected = values(name);
    for (var i = 0; i < presentations.length; i++) {
      var item = presentations[i], value = expected[i];
      if (!oldRed) {
        check(item.bar.main === api.mainInstance.settingsConsumerFor(item.api.settingsContext), "selected context owns actual Bar client");
        check(item.second.main === item.bar.main, "two views share one selected client");
      }
      for (var bar of [item.bar, item.second]) {
        var capsule = null;
        for (var itemChild of bar.children) {
          if (itemChild.radius !== undefined && itemChild.border !== undefined)
            capsule = itemChild;
        }
        check(capsule, "actual visible Bar capsule");
        var child = find(capsule, object => object !== capsule && object.font !== undefined && object.text !== undefined);
        check(child && child.text === textFor(value), "actual child Bar Text follows selected source " + JSON.stringify({
                                                                                                                          index: i,
                                                                                                                          expected: textFor(value),
                                                                                                                          displayed: bar.displayText,
                                                                                                                          child: child?.text
                                                                                                                        }));
      }
    }
    console.log("TEXT_CONSUMERS " + JSON.stringify({
                                                     scope: scope,
                                                     mode: mode,
                                                     boundary: name,
                                                     values: expected
                                                   }));
  }
  function probe(name, next) {
    afterDisk = next;
    phase = "disk";
    disk.command = ["python3", "-B", Quickshell.env("PHA_TEXT_DISK"), Quickshell.env("PHA_TEXT_CASE"), Quickshell.env("PHA_TEXT_OUTPUT") + "/persisted", name, scope];
    disk.running = true;
  }
  function open(next) {
    check(scope === "shared" ? popup.openPluginSettings(api.manifest, "settings") : popup.openInstanceSettings(api.manifest, selected, "settings"), "actual Settings opens");
    phase = next;
  }
  function edit() {
    function control(key) {
      var item = find(popup.settingsPage, child => child.label === api.tr("settings." + key + ".label"));
      check(item, "actual control " + key);
      return item;
    }
    var text = control("text");
    text.text = "";
    text.editCommitted();
    control("fortune").toggled(true);
    control("fortuneOffensive").toggled(true);
    control("fortuneEqual").toggled(true);
    var category = control("fortuneCategory");
    category.text = "following";
    category.editCommitted();
    var max = find(popup.settingsPage, child => child.objectName === "settings-range-editFortuneMaxLength");
    check(max, "actual max-length Slider");
    max.value = 30;
    max.moved();
    control("fortune").toggled(false);
    control("list").toggled(true);
    var file = control("textFile");
    file.text = Quickshell.env("PHA_TEXT_CASE") + "/selected.txt";
    file.editCommitted();
    control("refreshOnWallpaper").toggled(false);
    check(keys.every(key => popup._pageApi.field(key).pendingIntent === "set"), "all nine controls submit explicit intent");
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
        bar: create("barWidget", context),
        second: create("barWidget", context)
      }));
      phase = "initial";
    } else if (phase === "initial") {
      if (!oldRed) {
        for (var item of presentations)
          check(item.bar.main === api.mainInstance.settingsConsumerFor(item.api.settingsContext), "selected context owns actual Bar client");
      }
      var initial = mode === "single" ? "initial" : mode === "edit" ? "single" : mode === "reset" ? "edited" : mode === "follow" ? "reset" : mode === "handoff" ? "following" : mode === "retire" ? "policy" : mode === "wallpaper" || mode === "policy" ? "replaced" : boundary;
      if (!ready(initial))
        return;
      if (!oldRed)
        observe(initial);
      if (mode === "cold") {
        console.log("TEXT: COLD_PASS " + scope + " " + boundary);
        Qt.exit(0);
      } else if (mode === "single")
        probe("initial", "open-single");
      else if (mode === "edit")
        phase = "open-discard";
      else if (mode === "follow")
        phase = "change-base";
      else if (mode === "handoff" || mode === "retire")
        probe("hold", "start-held");
      else if (mode === "policy")
        open("policy-page");
      else if (mode === "wallpaper") {
        WallpaperService.wallpaperChanged("Virtual-1", "synthetic-a");
        WallpaperService.wallpaperChanged("Virtual-2", "synthetic-b");
        wallpaperStarted = Date.now();
        phase = "wallpaper-wait";
      } else
        open("reset-page");
    } else if (phase === "open-single")
      open("single-page");
    else if (phase === "single-page" && popup.opened && popup.settingsPage) {
      check(!popup.dirty && !popup._editor.dirty, "construction has no intent");
      var text = find(popup.settingsPage, child => child.label === api.tr("settings.text.label"));
      check(text, "actual single-field text control");
      text.text = "";
      text.editCommitted();
      check(popup._pageApi.field("text").pendingIntent === "set" && keys.slice(1).every(key => !popup._pageApi.field(key).pendingIntent), "untouched configuration fields carry no intent");
      apply("single-applied");
    } else if (phase === "single-applied" && accepted() && ready("single")) {
      if (!oldRed)
        observe("single");
      probe("single", "finish");
    } else if (phase === "open-discard")
      open("discard-page");
    else if (phase === "discard-page" && popup.opened && popup.settingsPage) {
      check(!popup.dirty && !popup._editor.dirty, "construction has no intent");
      edit();
      if (!oldRed)
        observe("single");
      check(!popup.requestClose(), "dirty Close refuses");
      popup.confirmDiscard();
      phase = "discarded";
    } else if (phase === "discarded" && !popup.opened && !popup._editor)
      probe("discarded", "open-edit");
    else if (phase === "open-edit")
      open("edit-page");
    else if (phase === "edit-page" && popup.opened && popup.settingsPage) {
      edit();
      failedEditor = popup._editor;
      failedPage = popup.settingsPage;
      if (oldRed)
        apply("applied");
      else
        probe("deny", "failure-apply");
    } else if (phase === "failure-apply")
      apply("failed");
    else if (phase === "failed" && receipt && !popup.busy) {
      check(receipt.status === "failed" && receipt.refreshState !== "current", "actual IO failure not acknowledged");
      check(popup._editor === failedEditor && popup.settingsPage === failedPage && popup._pageApi.field("textFile").value === Quickshell.env("PHA_TEXT_CASE") + "/selected.txt", "failed page/editor/input retained");
      if (scope === "instance")
        observe("single");
      probe("failed", "allow-retry");
    } else if (phase === "allow-retry")
      probe("allow", "retry");
    else if (phase === "retry") {
      check(popup._editor === failedEditor && popup.settingsPage === failedPage, "same-editor Retry");
      apply("applied");
    } else if (phase === "applied" && accepted() && ready("edited")) {
      console.log("TEXT_NATIVE_EDITED");
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
    else if (phase === "reset-applied" && accepted() && ready("reset")) {
      observe("reset");
      probe("reset", "finish");
    } else if (phase === "change-base") {
      var next = {
        text: "following-text",
        fortuneEnabled: true,
        fortuneOffensive: true,
        fortuneEqual: true,
        fortuneCategory: "following",
        fortuneMaxLength: 60,
        listEnabled: false,
        refreshOnWallpaper: true
      };
      for (var key in next)
        api.pluginSettings[key] = next[key];
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
    } else if (phase === "start-held") {
      presentations[scope === "shared" ? 0 : 1].bar.main.triggerFortune();
      phase = "held";
    } else if (phase === "held") {
      heldFile.reload();
      heldFile.waitForJob();
      if (!heldFile.loaded)
        return;
      if (mode === "retire") {
        retiredContext = selected.settingsContext;
        Service.loadedPlugins = ({});
        phase = "retiring";
      } else
        open("handoff-page");
    } else if (phase === "handoff-page" && popup.opened && popup.settingsPage) {
      var category = find(popup.settingsPage, child => child.label === api.tr("settings.fortuneCategory.label"));
      check(category, "actual replacement category control");
      category.text = "replacement";
      category.editCommitted();
      apply("replaced");
    } else if (phase === "replaced" && accepted() && ready("replaced")) {
      observe("replaced");
      probe("quiescent", "replaced-quiescent");
    } else if (phase === "replaced-quiescent")
      probe("replaced", "finish");
    else if (phase === "policy-page" && popup.opened && popup.settingsPage) {
      var category = find(popup.settingsPage, child => child.label === api.tr("settings.fortuneCategory.label"));
      var max = find(popup.settingsPage, child => child.objectName === "settings-range-editFortuneMaxLength");
      check(category && max, "actual finite retry policy controls");
      category.text = "oversized";
      category.editCommitted();
      max.value = 10;
      max.moved();
      apply("policy-applied");
    } else if (phase === "policy-applied" && accepted() && ready("policy")) {
      observe("policy");
      probe("policy", "finish");
    } else if (phase === "wallpaper-wait" && Date.now() - wallpaperStarted > 1200 && ready("replaced")) {
      observe("replaced");
      phase = "finish";
    } else if (phase === "retiring" && !retiredContext.current()) {
      check(api.mainInstance._settingsConsumers.size === 0 && presentations.every(item => item.bar.main === null && item.second.main === null), "retired clients/processes cannot publish");
      probe("quiescent", "finish");
    } else if (phase === "finish") {
      console.log("TEXT: PASS " + scope + " " + mode);
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
