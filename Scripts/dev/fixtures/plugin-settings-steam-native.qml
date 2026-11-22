import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins
import qs.Widgets

ShellRoot {
  id: root
  readonly property string base: Quickshell.env("PHA_STEAM_CASE")
  readonly property string scope: Quickshell.env("PHA_STEAM_SCOPE")
  readonly property string mode: Quickshell.env("PHA_STEAM_MODE")
  readonly property string boundary: Quickshell.env("PHA_STEAM_BOUNDARY")
  readonly property bool original: Quickshell.env("PHA_STEAM_ORIGINAL") === "1"
  readonly property string plugin: "hyprland-steam-overlay"
  property var api: null
  property var contexts: []
  readonly property var target: scope === "shared" ? api : contexts[0]
  property var main: null
  property var bar: null
  property var guide: null
  property var receipt: null
  property bool started: false
  property bool retried: false
  property string phase: "begin"
  property double since: Date.now()
  onPhaseChanged: since = Date.now()
  property string next: ""
  property string actionBoundary: ""
  FileView {
    id: manifest
    path: Settings.configDir + "plugins/" + root.plugin + "/manifest.json"
    blockLoading: true
  }
  FileView {
    id: dictionary
    path: Settings.configDir + "plugins/" + root.plugin + "/i18n/en.json"
    blockLoading: true
  }
  FileView {
    id: expectations
    path: root.base + "/expectations.json"
    blockLoading: true
  }
  FileView {
    id: requests
    path: root.base + "/requests.jsonl"
    blockLoading: true
  }
  Process {
    id: disk
    onExited: code => {
      if (code !== 0)
        root.fail("complete Steam native documents");
      else
        root.phase = root.next;
    }
  }
  PanelWindow {
    visible: true
    implicitWidth: 1400
    implicitHeight: 900
    Item {
      id: content
      width: 1400
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
      throw new Error("STEAM_NATIVE_ASSERT: " + scope + "/" + mode + "/" + phase + ": " + message);
  }
  function fail(error) {
    driver.stop();
    console.error(String(error));
    Qt.exit(2);
  }
  function find(object, predicate, seen) {
    if (!object)
      return null;
    seen = seen || new Set();
    if (seen.has(object))
      return null;
    seen.add(object);
    if (predicate(object))
      return object;
    if (object.item) {
      const child = find(object.item, predicate, seen);
      if (child)
        return child;
    }
    for (const list of [object.data, object.children, object.instances]) {
      if (!list || typeof list.length !== "number")
        continue;
      for (let index = 0; index < list.length; index++) {
        const child = find(list[index], predicate, seen);
        if (child)
          return child;
      }
    }
    return null;
  }
  function values(name) {
    expectations.reload();
    expectations.waitForJob();
    const document = JSON.parse(expectations.text())[name];
    const shared = Object.assign({}, api.manifest.metadata.defaultSettings, document.shared);
    return [shared].concat(document.bar.widgets.left.map(row => Object.assign({}, shared, row.instanceSettings || {})));
  }
  function ready(name) {
    const expected = values(name);
    return [api].concat(contexts).every((context, index) => context.pluginSettings.gapSize === expected[index].gapSize);
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    manifest.waitForJob();
    dictionary.waitForJob();
    const descriptor = JSON.parse(manifest.text()), translations = JSON.parse(dictionary.text());
    Registry.installedPlugins = {
      [plugin]: descriptor
    };
    Service._openSettingsOwner(plugin, owner => {
      try {
        check(owner, "native owner");
        api = Service.createPluginAPI(plugin, descriptor, owner, translations, translations, {});
        Service.loadedPlugins = {
          [plugin]: {
            api: api
          }
        };
        const component = Qt.createComponent("file://" + api.pluginDir + "/Main.qml");
        check(component.status === Component.Ready, component.errorString());
        main = PluginLoader.createObject(plugin, "main", component, content, api, {});
        check(main, "actual Main");
        api.mainInstance = main;
        contexts = [0, 1, 2].map(index => PluginInstances.apiFor(plugin, {
                                                                   kind: "bar",
                                                                   list: "global",
                                                                   section: "left",
                                                                   index: index
                                                                 }));
        phase = "runtime";
      } catch (error) {
        fail(error);
      }
    });
  }
  function probe(name, after) {
    next = after;
    phase = "disk";
    disk.command = ["python3", "-B", Quickshell.env("PHA_STEAM_DISK"), base, Quickshell.env("PHA_STEAM_OUTPUT") + "/persisted", name];
    disk.running = true;
  }
  function open(after) {
    check(scope === "shared" ? popup.openPluginSettings(api.manifest, "settings") : popup.openInstanceSettings(api.manifest, target, "settings"), "actual scoped page");
    phase = after;
  }
  function edit() {
    const control = find(popup.settingsPage, item => item.objectName === "settings-range-valueGapSize");
    check(control, "actual gap slider");
    control.value = 30;
    control.moved();
    check(popup._pageApi.field("gapSize").value === 30, "actual field intent");
    for (const key of Object.keys(api.manifest.metadata.settingsSchema.fields))
      if (key !== "gapSize")
        check(!popup._pageApi.field(key).pendingIntent, "untouched field " + key);
  }
  function apply(after) {
    receipt = null;
    check(popup.applySettings(), "native Apply");
    phase = after;
  }
  function accepted() {
    return receipt && !popup.busy && receipt.status === "saved" && receipt.refreshState === "current";
  }
  function rows() {
    requests.reload();
    requests.waitForJob();
    return requests.text().trim().split("\n").filter(line => line).map(line => JSON.parse(line));
  }
  function action(name) {
    actionBoundary = name;
    console.log("STEAM_NATIVE_ENDPOINT_OFFSET " + rows().length);
    const component = Qt.createComponent("file://" + api.pluginDir + "/BarWidget.qml");
    check(component.status === Component.Ready, component.errorString());
    bar = PluginLoader.createObject(plugin, "barWidget", component, content, target, {
                                      screen: Quickshell.screens[0]
                                    });
    check(bar, "actual originating Bar");
    const guideComponent = Qt.createComponent("file://" + api.pluginDir + "/Panel.qml");
    check(guideComponent.status === Component.Ready, guideComponent.errorString());
    guide = PluginLoader.createObject(plugin, "panel", guideComponent, content, target, {});
    check(guide, "actual guide Panel");
    phase = "consumer-ready";
  }
  function finish() {
    if (main) {
      main.destroy();
      main = null;
    }
    phase = "joined";
  }
  function drive() {
    check(Date.now() - since < 18000, "finite native Steam phase");
    if (phase === "runtime" && contexts.every(context => context.settingsReady) && main.steamRunning && main.screenWidth === 2000 && main.luaModeProbed)
      phase = "initial";
    else if (phase === "initial") {
      const name = mode === "edit" ? "initial" : mode === "reset" ? "edited" : mode === "follow" ? "reset" : boundary;
      if (!ready(name))
        return;
      if (mode === "cold")
        action(name);
      else if (mode === "edit")
        probe("initial", "open-discard");
      else
        phase = mode === "follow" ? "change-base" : "open-reset";
    } else if (phase === "open-discard")
      open("discard-page");
    else if (phase === "discard-page" && popup.opened && popup.settingsPage) {
      check(!popup.dirty && !popup._editor.dirty, "construction has no intent");
      edit();
      check(!popup.requestClose(), "dirty Close refused");
      popup.confirmDiscard();
      phase = "discarded";
    } else if (phase === "discarded" && !popup.opened && !popup._editor)
      probe("discarded", "open-edit");
    else if (phase === "open-edit")
      open("edit-page");
    else if (phase === "edit-page" && popup.opened && popup.settingsPage) {
      edit();
      apply("applied");
    } else if (phase === "applied" && accepted() && ready("edited"))
      probe("edited", "edited-effect");
    else if (phase === "edited-effect")
      action("edited");
    else if (phase === "open-reset")
      open("reset-page");
    else if (phase === "reset-page" && popup.opened && popup.settingsPage && !popup.busy) {
      check(popup._pageApi.field("gapSize").reset(), "staged Reset");
      probe("reset-staged", "reset-apply");
    } else if (phase === "reset-apply")
      apply("reset-applied");
    else if (phase === "reset-applied" && accepted() && ready("reset"))
      probe("reset", "reset-effect");
    else if (phase === "reset-effect")
      action("reset");
    else if (phase === "change-base") {
      api.pluginSettings.gapSize = 25;
      phase = "base-saving";
      api.saveSettings(result => {
        try {
          check(result.status === "saved", "native inheritance publication");
          phase = "base-changed";
        } catch (error) {
          fail(error);
        }
      });
    } else if (phase === "base-changed" && ready("following"))
      probe("following", "following-effect");
    else if (phase === "following-effect")
      action("following");
    else if (phase === "consumer-ready" && Date.now() - since > 300) {
      const expected = values(actionBoundary)[scope === "shared" ? 0 : 1];
      check(guide.friendsWidth === expected.friendsWidth && guide.mainWidth === expected.mainWidth && guide.chatWidth === expected.chatWidth, "injected guide configuration");
      bar.clicked();
      phase = "effect";
    } else if (phase === "effect" && original && !retried && !main.overlayActive && main.steamWindows.length > 0 && Date.now() - since > 1000) {
      // Original timing is separately red. Warm its old query once to isolate
      // the independent original shared-geometry error after native publication.
      retried = true;
      bar.clicked();
    } else if (phase === "effect" && main.overlayActive && Date.now() - since > 1500) {
      console.log("STEAM_NATIVE_EFFECT " + actionBoundary);
      finish();
    } else if (phase === "joined" && Date.now() - since > 400) {
      driver.stop();
      console.log("STEAM_NATIVE: PASS " + scope + " " + mode + " " + boundary);
      Qt.exit(0);
    }
  }
  Connections {
    target: Settings
    function onSettingsLoaded() {
      root.begin();
    }
  }
  SettingsBootstrap {}
  Timer {
    id: driver
    interval: 40
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
