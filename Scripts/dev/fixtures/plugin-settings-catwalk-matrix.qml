import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins
import qs.Widgets

ShellRoot {
  id: root
  readonly property string casePath: Quickshell.env("CAT_MATRIX_CASE")
  readonly property string scope: Quickshell.env("CAT_MATRIX_SCOPE")
  readonly property string leg: Quickshell.env("CAT_MATRIX_LEG")
  readonly property bool cold: leg !== "warm"
  property bool started: false
  property string phase: "startup"
  property double since: Date.now()
  onPhaseChanged: since = Date.now()
  property var api: null
  property var main: null
  property var selected: null
  property var sibling: null
  property var inherited: null
  property var presentations: []
  property var receipt: null
  property var failedPage: null
  property var failedEditor: null
  property int callbacks: 0
  property var retiredContext: null
  property var retiredClient: null
  property string afterDisk: ""
  property string afterPermissions: ""
  FileView {
    id: manifest
    path: Settings.configDir + "plugins/catwalk/manifest.json"
    blockLoading: true
  }
  FileView {
    id: dictionary
    path: Settings.configDir + "plugins/catwalk/i18n/en.json"
    blockLoading: true
  }
  FileView {
    id: expectations
    path: root.casePath + "/expectations.json"
    blockLoading: true
  }
  Process {
    id: disk
    onExited: code => {
      if (code !== 0)
        root.fail("complete independent documents");
      else
        root.phase = root.afterDisk;
    }
  }
  Process {
    id: permissions
    onExited: code => {
      if (code !== 0)
        root.fail("permission boundary");
      else
        root.phase = root.afterPermissions;
    }
  }
  PanelWindow {
    visible: true
    implicitWidth: 1280
    implicitHeight: 800
    Item {
      id: scene
      width: 1280
      height: 800
    }
    NPluginSettingsPopup {
      id: popup
      screen: Quickshell.screens[0]
      onSettingsCompleted: result => root.receipt = result
    }
  }
  function check(ok, label) {
    if (!ok)
      throw new Error("CAT_MATRIX_ASSERT: " + phase + ": " + label);
    console.log("CAT_MATRIX_CHECK: " + label);
  }
  function fail(error) {
    console.error(String(error) + "\n" + (error.stack || ""));
    Qt.exit(2);
  }
  function find(item, predicate, seen) {
    seen = seen || new Set();
    if (!item || seen.has(item))
      return null;
    seen.add(item);
    if (predicate(item))
      return item;
    for (var list of [item.data, item.children]) {
      if (!list || typeof list === "function" || typeof list.length !== "number")
        continue;
      for (var child of list) {
        var found = find(child, predicate, seen);
        if (found)
          return found;
      }
    }
    return null;
  }
  function create(entry, runtime) {
    var component = Qt.createComponent("file://" + api.pluginDir + "/" + api.manifest.entryPoints[entry]);
    check(component.status === Component.Ready, component.errorString());
    var props = {
      pluginApi: runtime,
      screen: Quickshell.screens[0]
    };
    if (entry === "desktopWidget") {
      props.widgetData = {
        id: "plugin:catwalk"
      };
      props.widgetIndex = 0;
    }
    var item = component.createObject(scene, props);
    check(item, "actual " + entry);
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
      catwalk: descriptor
    };
    Service._openSettingsOwner("catwalk", function (owner) {
      try {
        check(owner, "actual native shared owner");
        api = Service.createPluginAPI("catwalk", descriptor, owner, dict, dict, {});
        Service.loadedPlugins = {
          catwalk: {
            api: api
          }
        };
        var component = Qt.createComponent("file://" + api.pluginDir + "/Main.qml");
        check(component.status === Component.Ready, component.errorString());
        main = component.createObject(scene, {
                                        pluginApi: api
                                      });
        api.mainInstance = main;
        main.cpuUsage = 15;
        selected = PluginInstances.apiFor("catwalk", {
                                            kind: "bar",
                                            list: "global",
                                            section: "left",
                                            index: 0
                                          });
        sibling = PluginInstances.apiFor("catwalk", {
                                           kind: "bar",
                                           list: "global",
                                           section: "left",
                                           index: 1
                                         });
        inherited = PluginInstances.apiFor("catwalk", {
                                             kind: "bar",
                                             list: "global",
                                             section: "left",
                                             index: 2
                                           });
        phase = "ready";
      } catch (error) {
        fail(error);
      }
    });
  }
  function probe(name, next) {
    afterDisk = next;
    phase = "disk";
    disk.command = ["/usr/bin/python3", "-B", Quickshell.env("CAT_MATRIX_DISK"), casePath, Quickshell.env("CAT_MATRIX_OUTPUT") + "/persisted", name];
    disk.running = true;
  }
  function permission(mode, next) {
    afterPermissions = next;
    phase = "permissions";
    permissions.command = ["chmod", mode, Settings.configDir + (scope === "shared" ? "settings/plugins" : "settings")];
    permissions.running = true;
  }
  function values(name, index) {
    expectations.waitForJob();
    var docs = JSON.parse(expectations.text())[name];
    return Object.assign({}, api.manifest.metadata.defaultSettings, docs.shared, index < 0 ? {} : docs.bar.widgets.left[index].instanceSettings);
  }
  function consumers(name) {
    for (var i = 0; i < presentations.length; i++) {
      var row = presentations[i], cfg = values(name, i - 1), client = main.settingsConsumerFor(row.api.settingsContext), running = 15 >= cfg.minimumThreshold;
      if (!client || client.minimumThreshold !== cfg.minimumThreshold || client.hideBackground !== cfg.hideBackground)
        return false;
      check(row.bar.settingsConsumer === client && row.desktop.settingsConsumer === client, "exact context client shared by native Bar/Desktop");
      if (row.bar.isRunning !== running || row.desktop.isRunning !== running || row.desktop.showBackground === cfg.hideBackground)
        return false;
      var suffix = running ? "my-active-" : "my-idle-", image = find(row.desktop, item => item.source !== undefined && String(item.source).includes("/icons/"));
      check(image && String(image.source).includes(suffix), "actual selected desktop Image source");
      var barImage = find(row.bar, item => item.source !== undefined && String(item.source).includes("/icons/"));
      check(barImage && String(barImage.source).includes(suffix), "actual selected Bar Image source");
      check(find(row.desktop, item => item.text === "15%"), "actual shared CPU child Text");
      check(row.desktop.settingsConsumer !== presentations[(i + 1) % presentations.length].desktop.settingsConsumer, "distinct context projections");
    }
    return true;
  }
  function open(next) {
    check(scope === "shared" ? popup.openPluginSettings(api.manifest, "settings") : popup.openInstanceSettings(api.manifest, selected, "settings"), "actual scoped page opens");
    phase = next;
  }
  function edit() {
    var slider = find(popup.settingsPage, item => item.objectName === "settings-range-valueMinimumThreshold"), toggle = find(popup.settingsPage, item => item.toggled !== undefined);
    check(slider && toggle, "both real controls");
    slider.value = 18;
    slider.moved();
    toggle.toggled(true);
  }
  function apply(next) {
    receipt = null;
    popup._pageApi.saveSettings(result => {
      check(receipt && receipt.status === result.status, "completion signal precedes callback");
      callbacks++;
    });
    check(popup.applySettings(), "native Apply");
    phase = next;
  }
  function accepted() {
    return receipt && !popup.busy && ["saved", "nothing_to_save"].includes(receipt.status) && receipt.refreshState === "current";
  }
  function changeBase(threshold, background, next) {
    api.pluginSettings.minimumThreshold = threshold;
    api.pluginSettings.hideBackground = background;
    phase = "base-save";
    api.saveSettings(result => {
      try {
        check(["saved", "nothing_to_save"].includes(result.status), "actual native plugin publication");
        phase = next;
      } catch (error) {
        fail(error);
      }
    });
  }
  function drive() {
    if (Date.now() - since >= 18000)
      throw new Error("CAT_MATRIX_ASSERT: " + phase + ": finite phase");
    // Each timer tick dispatches exactly one phase group. Keep bounded control
    // flow in each function so the path-sensitive settings checker can inspect
    // every assertion without multiplying all unrelated waiting conditions.
    if (["ready", "initial", "open-discard", "discard-page", "discarded"].includes(phase)) {
      driveOpening();
      return;
    }
    if (["open-edit", "edit-page", "blocked", "failed", "unblock", "retry", "applied"].includes(phase)) {
      driveEdit();
      return;
    }
    if (["close-edit", "closed", "base-changed", "open-reset", "reset-page", "reset-staged", "reset-apply", "reset-applied"].includes(phase)) {
      driveReset();
      return;
    }
    if (["close-reset", "reset-closed", "inherited", "open-stale", "stale-page", "stale-base", "stale-result", "stale-discarded"].includes(phase)) {
      driveStale();
      return;
    }
    driveRetire();
  }
  function driveOpening() {
    if (phase === "ready" && selected.settingsReady && sibling.settingsReady && inherited.settingsReady) {
      var views = [];
      for (var runtime of [api, selected, sibling, inherited])
        views.push({
                     api: runtime,
                     bar: create("barWidget", runtime),
                     desktop: create("desktopWidget", runtime)
                   });
      presentations = views;
      phase = "initial";
    } else if (phase === "initial" && consumers(cold ? "stale" : "initial")) {
      if (cold)
        probe("stale", leg === "retire" ? "retire" : "finish");
      else
        probe("initial", "open-discard");
    } else if (phase === "open-discard")
      open("discard-page");
    else if (phase === "discard-page" && popup.opened && popup.settingsPage) {
      check(!popup.dirty, "construction submits no intent");
      edit();
      check(!popup.requestClose(), "dirty Close refuses");
      popup.confirmDiscard();
      phase = "discarded";
    } else if (phase === "discarded" && !popup.opened && !popup._editor && consumers("initial"))
      probe("initial", "open-edit");
  }
  function driveEdit() {
    if (phase === "open-edit")
      open("edit-page");
    else if (phase === "edit-page" && popup.opened && popup.settingsPage) {
      edit();
      failedPage = popup.settingsPage;
      failedEditor = popup._editor;
      permission("500", "blocked");
    } else if (phase === "blocked")
      apply("failed");
    else if (phase === "failed" && receipt && !popup.busy) {
      check(receipt.status === "failed" && popup.settingsPage === failedPage && popup._editor === failedEditor, "failed native save retains exact page/editor");
      check(!popup.requestClose(), "failed Close refuses");
      popup.keepEditing();
      probe("initial", "unblock");
    } else if (phase === "unblock")
      permission("700", "retry");
    else if (phase === "retry")
      apply("applied");
    else if (phase === "applied" && accepted() && consumers("edited")) {
      check(callbacks === 2, "failure and Retry callbacks delivered after signals");
      probe("edited", "close-edit");
    }
  }
  function driveReset() {
    if (phase === "close-edit") {
      check(popup.requestClose(), "successful clean Close");
      phase = "closed";
    } else if (phase === "closed" && !popup._editor)
      changeBase(8, false, "base-changed");
    else if (phase === "base-changed" && consumers("base"))
      probe("base", "open-reset");
    else if (phase === "open-reset")
      open("reset-page");
    else if (phase === "reset-page" && popup.opened && popup.settingsPage) {
      check(popup._pageApi.resetFields(["minimumThreshold", "hideBackground"]), "both native staged field Resets");
      phase = "reset-staged";
    } else if (phase === "reset-staged" && !popup._editor.busy && ["minimumThreshold", "hideBackground"].every(key => popup._pageApi.field(key).pendingIntent === "reset"))
      probe("base", "reset-apply");
    else if (phase === "reset-apply")
      apply("reset-applied");
    else if (phase === "reset-applied" && accepted() && consumers("reset"))
      probe("reset", "close-reset");
  }
  function driveStale() {
    if (phase === "close-reset") {
      check(popup.requestClose(), "Reset clean Close");
      phase = "reset-closed";
    } else if (phase === "reset-closed" && !popup._editor)
      changeBase(19, true, "inherited");
    else if (phase === "inherited" && consumers("following"))
      probe("following", "open-stale");
    else if (phase === "open-stale")
      open("stale-page");
    else if (phase === "stale-page" && popup.opened && popup.settingsPage) {
      var slider = find(popup.settingsPage, item => item.objectName === "settings-range-valueMinimumThreshold");
      slider.value = 14;
      slider.moved();
      failedPage = popup.settingsPage;
      failedEditor = popup._editor;
      changeBase(11, false, "stale-base");
    } else if (phase === "stale-base" && consumers("stale"))
      apply("stale-result");
    else if (phase === "stale-result" && receipt && !popup.busy) {
      check(receipt.status === "failed" && popup.settingsPage === failedPage && popup._editor === failedEditor, "base change refuses old editor without retargeting");
      check(!popup.requestClose(), "stale unsaved page Close refuses");
      popup.keepEditing();
      check(popup.confirmDiscard(), "explicit stale discard");
      phase = "stale-discarded";
    } else if (phase === "stale-discarded" && !popup._editor && consumers("stale"))
      probe("stale", "finish");
  }
  function driveRetire() {
    if (phase === "retire") {
      retiredContext = selected.settingsContext;
      retiredClient = main.settingsConsumerFor(retiredContext);
      Settings.data.bar.widgets.left = Settings.data.bar.widgets.left.slice(1);
      phase = "retired";
    } else if (phase === "retired" && !retiredContext.current()) {
      check(retiredClient === null && !main._settingsConsumers.has(retiredContext), "actual native retirement removes exact projection");
      check(presentations[1].bar.settingsConsumer === null && presentations[1].desktop.settingsConsumer === null, "retired native views release projection");
      phase = "retire-save";
      Settings.store.saveSelected([["bar", "widgets", "left"]], result => {
        try {
          check(["saved", "nothing_to_save"].includes(result.status), "test owning-list publication");
          phase = "retire-saved";
        } catch (error) {
          fail(error);
        }
      });
    } else if (phase === "retire-saved")
      probe("retired", "finish");
    else if (phase === "finish") {
      console.log("CATWALK_MATRIX: PASS " + scope + " " + leg);
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
