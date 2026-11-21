// Real Main/Bar/window with native preferences; compositor actions are inert.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins
import qs.Widgets

ShellRoot {
  id: root
  readonly property string plugin: Quickshell.env("PHA_WINDOW_PLUGIN")
  readonly property string scope: Quickshell.env("PHA_WINDOW_SCOPE")
  readonly property string mode: Quickshell.env("PHA_WINDOW_MODE")
  readonly property string boundary: Quickshell.env("PHA_WINDOW_BOUNDARY")
  readonly property bool wall: plugin === "wallcards"
  readonly property bool oldRed: Quickshell.env("PHA_WINDOW_OLD_RED") === "1"
  readonly property string field: wall ? "card_height" : "buttonWidth"
  property bool started: false
  property string phase: "startup"
  property double phaseStarted: Date.now()
  onPhaseChanged: phaseStarted = Date.now()
  property var api: null
  property var contexts: []
  property var bars: []
  property var main: null
  property var receipt: null
  property string afterDisk: ""
  property string diskBoundary: ""
  property string observation: ""
  property string afterObservation: ""
  property int viewIndex: 0
  property var openedWindow: null
  property var actionObservations: []
  FileView {
    id: manifestFile
    path: Settings.configDir + "plugins/" + root.plugin + "/manifest.json"
    blockLoading: true
  }
  FileView {
    id: dictionaryFile
    path: Settings.configDir + "plugins/" + root.plugin + "/i18n/en.json"
    blockLoading: true
  }
  FileView {
    id: expectedFile
    path: Quickshell.env("PHA_WINDOW_CASE") + "/expectations.json"
    blockLoading: true
  }
  Process {
    id: disk
    onExited: code => {
      if (code !== 0)
        root.fail("independent complete window readback: " + root.diskBoundary);
      else
        root.phase = root.afterDisk;
    }
  }
  PanelWindow {
    visible: true
    implicitWidth: 1280
    implicitHeight: 900
    Item {
      id: content
      width: 1280
      height: 900
    }
    NPluginSettingsPopup {
      id: popup
      screen: Quickshell.screens[0]
      onSettingsCompleted: result => root.receipt = result
    }
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("WINDOW_NATIVE_ASSERT: " + plugin + "/" + scope + "/" + mode + "/" + phase + ": " + message);
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
    var item = PluginLoader.createObject(plugin, entry, component, content, context, {
                                           screen: Quickshell.screens[0]
                                         });
    check(item !== null, "actual " + entry + " constructs");
    return item;
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    manifestFile.waitForJob();
    dictionaryFile.waitForJob();
    var manifest = JSON.parse(manifestFile.text()), dictionary = JSON.parse(dictionaryFile.text());
    var registry = {};
    registry[plugin] = manifest;
    Registry.installedPlugins = registry;
    Service._openSettingsOwner(plugin, function (owner) {
      try {
        check(owner !== null, "actual native plugin owner");
        api = Service.createPluginAPI(plugin, manifest, owner, dictionary, dictionary, {});
        api.panelOpenScreen = Quickshell.screens[0];
        var loaded = {};
        loaded[plugin] = {
          api: api
        };
        Service.loadedPlugins = loaded;
        main = create("main", api);
        api.mainInstance = main;
        contexts = [api].concat([0, 1, 2].map(index => PluginInstances.apiFor(plugin, {
                                                                                kind: "bar",
                                                                                list: "global",
                                                                                section: "left",
                                                                                index: index
                                                                              })));
        phase = "runtime";
      } catch (error) {
        fail(error);
      }
    });
  }
  function values(name) {
    expectedFile.waitForJob();
    var expected = JSON.parse(expectedFile.text())[name];
    var base = Object.assign({}, api.manifest.metadata.defaultSettings, expected.shared);
    return [base].concat(expected.bar.widgets.left.map(row => Object.assign({}, base, row.instanceSettings || {})));
  }
  function ready(name) {
    var expected = values(name);
    return contexts.every((item, index) => item.pluginSettings[field] === expected[index][field]);
  }
  function probe(name, next) {
    afterDisk = next;
    diskBoundary = name;
    phase = "disk";
    disk.command = ["python3", "-B", Quickshell.env("PHA_WINDOW_DISK"), Quickshell.env("PHA_WINDOW_CASE"), Quickshell.env("PHA_WINDOW_OUTPUT") + "/persisted", name];
    disk.running = true;
  }
  function observe(name, next) {
    observation = name;
    afterObservation = next;
    viewIndex = 0;
    phase = "window-open";
  }
  function loader() {
    return find(main, item => item.setSource !== undefined && item.active !== undefined);
  }
  function closeWindow() {
    if (wall)
      main.hide();
    else
      main.closePanel();
  }
  function openPage(next) {
    check(scope === "shared" ? popup.openPluginSettings(api.manifest, "settings") : popup.openInstanceSettings(api.manifest, contexts[1], "settings"), "actual scoped Settings opens");
    phase = next;
  }
  function edit() {
    var control = find(popup.settingsPage, item => item.objectName === (wall ? "settings-range-editCardHeight" : "settings-range-editBtnWidth"));
    check(control, "actual window size slider");
    control.value = 400;
    control.moved(400);
    check(popup._pageApi.field(field).value === 400, "actual control stages selected field");
    for (var key of Object.keys(api.manifest.metadata.settingsSchema.fields))
      if (key !== field)
        check(!popup._pageApi.field(key).pendingIntent, "untouched field has no intent: " + key);
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
    check(Date.now() - phaseStarted < 22000, "finite operation deadline");
    if (phase === "runtime" && contexts.length === 4 && contexts.every(item => item.settingsReady)) {
      bars = contexts.map(context => create("barWidget", context));
      phase = "initial";
    } else if (phase === "initial") {
      var name = mode === "edit" ? "initial" : mode === "reset" ? "edited" : mode === "follow" ? "reset" : mode === "writer" ? "following" : boundary;
      if (!ready(name))
        return;
      if (oldRed && mode === "edit")
        probe("initial", "open-discard");
      else
        observe(name, mode === "cold" ? "finish" : mode === "edit" ? "initial-observed" : mode === "reset" ? "reset-open" : mode === "writer" ? "writer-open" : "change-base");
    } else if (phase === "window-open") {
      check(!loader()?.active, "previous window fully unloaded");
      bars[viewIndex].clicked();
      phase = "window-loaded";
    } else if (phase === "window-loaded" && loader()?.item) {
      openedWindow = loader().item;
      check(openedWindow.pluginApi === contexts[viewIndex], "captured originating window API");
      var expected = values(observation)[viewIndex];
      check((wall ? openedWindow.cardHeight : openedWindow.btnW) === expected[field], "selected window size");
      var child = find(openedWindow.contentItem, item => wall ? item.filteredCount !== undefined && item.cardSpacing !== undefined : item.desaturateColor !== undefined);
      check(child && (wall ? child.height : child.width) === expected[field], "actual card/button child geometry");
      if (!wall) {
        openedWindow.executeActionByIndex(2);
        actionObservations.push({
                                  index: viewIndex,
                                  expected: expected.lockOnSuspend ? "lockAndSuspend" : "suspend"
                                });
      } else
        closeWindow();
      phase = "window-closed";
    } else if (phase === "window-closed" && !loader()?.active) {
      viewIndex++;
      if (viewIndex < 4)
        phase = "window-open";
      else {
        console.log("WINDOW_CONSUMERS " + JSON.stringify({
                                                           plugin: plugin,
                                                           scope: scope,
                                                           mode: mode,
                                                           boundary: observation,
                                                           values: values(observation).map(value => value[field]),
                                                           actions: actionObservations
                                                         }));
        phase = afterObservation;
      }
    } else if (phase === "initial-observed")
      probe("initial", "open-discard");
    else if (phase === "open-discard")
      openPage("discard-page");
    else if (phase === "discard-page" && popup.opened && popup.settingsPage) {
      check(!popup.dirty && !popup._editor.dirty, "page construction nonpublishing");
      edit();
      check(!popup.requestClose(), "dirty Close refuses");
      popup.confirmDiscard();
      phase = "discarded";
    } else if (phase === "discarded" && !popup.opened && !popup._editor)
      probe("discarded", "open-edit");
    else if (phase === "open-edit")
      openPage("edit-page");
    else if (phase === "edit-page" && popup.opened && popup.settingsPage) {
      edit();
      apply("applied");
    } else if (phase === "applied" && accepted() && ready("edited"))
      probe("edited", "edited-observe");
    else if (phase === "edited-observe")
      observe("edited", "finish");
    else if (phase === "reset-open")
      openPage("reset-page");
    else if (phase === "reset-page" && popup.opened && popup.settingsPage && !popup.busy) {
      check(popup._pageApi.field(field).reset(), "native staged Reset");
      probe("reset-staged", "reset-apply");
    } else if (phase === "reset-apply")
      apply("reset-applied");
    else if (phase === "reset-applied" && accepted() && ready("reset"))
      observe("reset", "reset-observed");
    else if (phase === "reset-observed")
      probe("reset", "finish");
    else if (phase === "change-base") {
      api.pluginSettings[field] = 400;
      phase = "base-saving";
      api.saveSettings(function (result) {
        try {
          check(result.status === "saved", "native shared propagation");
          phase = "base-changed";
        } catch (error) {
          fail(error);
        }
      });
    } else if (phase === "base-changed" && ready("following"))
      observe("following", "following-observed");
    else if (phase === "following-observed")
      probe("following", "retire-open");
    else if (phase === "writer-open") {
      bars[1].clicked();
      phase = "writer-loaded";
    } else if (phase === "writer-loaded" && loader()?.item) {
      openedWindow = loader().item;
      check(openedWindow.pluginApi === contexts[1], "runtime layout writer captures selected owner");
      openedWindow.cardHeight = 410;
      phase = "writer-saving";
      openedWindow.saveLayout(function (result) {
        try {
          check(result.status === "saved", "runtime layout save accepted: " + JSON.stringify(result));
          phase = "writer-saved";
        } catch (error) {
          fail(error);
        }
      });
    } else if (phase === "writer-saved") {
      closeWindow();
      probe("writer", "writer-observe");
    } else if (phase === "writer-observe" && ready("writer"))
      observe("writer", "finish");
    else if (phase === "retire-open") {
      bars[1].clicked();
      phase = "collision-loaded";
    } else if (phase === "collision-loaded" && loader()?.item) {
      openedWindow = loader().item;
      bars[2].clicked();
      check(!loader().active || (loader().item === openedWindow && openedWindow.pluginApi === contexts[1]), "other opener closes instead of retargeting");
      phase = "collision-closed";
    } else if (phase === "collision-closed" && !loader()?.active) {
      bars[1].clicked();
      phase = "retire-loaded";
    } else if (phase === "retire-loaded" && loader()?.item) {
      Service.loadedPlugins = ({});
      phase = "retired";
    } else if (phase === "retired") {
      if (contexts[1].settingsContext.current())
        return;
      check(!loader()?.active, "retired context unloads its window");
      phase = "finish";
    } else if (phase === "finish") {
      console.log("WINDOW_NATIVE: PASS " + plugin + " " + scope + " " + mode);
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
