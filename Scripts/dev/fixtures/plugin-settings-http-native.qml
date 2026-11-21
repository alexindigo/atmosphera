// Real pages/native owners, live HTTP result children, independent cold readers.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins
import qs.Widgets

ShellRoot {
  id: root
  readonly property string plugin: Quickshell.env("PHA_HTTP_PLUGIN")
  readonly property string scope: Quickshell.env("PHA_HTTP_SCOPE")
  readonly property string mode: Quickshell.env("PHA_HTTP_MODE")
  readonly property string boundary: Quickshell.env("PHA_HTTP_BOUNDARY")
  readonly property bool news: plugin === "news"
  readonly property bool oldRed: Quickshell.env("PHA_HTTP_OLD_RED") === "1"
  readonly property string field: news ? "category" : "topics"
  readonly property string editedValue: news ? "technology" : "selected"
  property bool started: false
  property string phase: "startup"
  property double phaseStarted: Date.now()
  onPhaseChanged: phaseStarted = Date.now()
  property var api: null
  property var selected: null
  property var sibling: null
  property var inherited: null
  property var main: null
  property var presentations: []
  property var receipt: null
  property string afterDisk: ""
  property string diskBoundary: ""
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
    path: Quickshell.env("PHA_HTTP_CASE") + "/expectations.json"
    blockLoading: true
  }
  Process {
    id: disk
    onExited: code => {
      if (code !== 0)
        root.fail("independent complete HTTP readback: " + root.diskBoundary);
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
      throw new Error("HTTP_NATIVE_ASSERT: " + plugin + "/" + scope + "/" + mode + "/" + phase + ": " + message);
  }
  function fail(error) {
    console.error(String(error) + "\n" + (error.stack || ""));
    Qt.exit(2);
  }
  function find(object, predicate, visited) {
    var seen = visited || new Set();
    if (!object || seen.has(object))
      return null;
    seen.add(object);
    if (object && predicate(object))
      return object;
    for (var list of [object?.data, object?.children]) {
      if (!list || typeof list === "function" || typeof list.length !== "number")
        continue;
      for (var child of list) {
        var result = find(child, predicate, seen);
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
    var manifest = JSON.parse(manifestFile.text()), dictionary = JSON.parse(dictionaryFile.text()), registry = {};
    registry[plugin] = manifest;
    Registry.installedPlugins = registry;
    Service._openSettingsOwner(plugin, function (owner) {
      try {
        check(owner !== null, "actual native plugin owner");
        api = Service.createPluginAPI(plugin, manifest, owner, dictionary, dictionary, {});
        var loaded = {};
        loaded[plugin] = {
          api: api
        };
        Service.loadedPlugins = loaded;
        main = create("main", api);
        api.mainInstance = main;
        var contexts = [0, 1, 2].map(index => PluginInstances.apiFor(plugin, {
                                                                       kind: "bar",
                                                                       list: "global",
                                                                       section: "left",
                                                                       index: index
                                                                     }));
        selected = contexts[0];
        sibling = contexts[1];
        inherited = contexts[2];
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
    return [base].concat(expected.bar.widgets.left.map(row => Object.assign({}, base, row.instanceSettings || {})));
  }
  function title(value) {
    if (!news && !value[field])
      return api.tr("panel.noTopics");
    return "headline-" + (news && value[field] === "general" ? "news OR headlines" : value[field]);
  }
  function ready(name) {
    var expected = values(name);
    if (!oldRed) {
      for (var item of presentations) {
        var client = main.settingsConsumerFor(item.api.settingsContext);
        check(item.bar.settingsConsumer === client && item.second.settingsConsumer === client && item.panel.settingsConsumer === client, "actual views share exact selected HTTP client");
      }
    }
    return presentations.every((item, index) => item.api.pluginSettings[field] === expected[index][field] && (oldRed || (find(item.panel, child => child.text === title(expected[index])) && !item.bar.main?.isLoading)));
  }
  function observe(name) {
    if (oldRed)
      return;
    var expected = values(name);
    for (var i = 0; i < presentations.length; i++) {
      var item = presentations[i], client = main.settingsConsumerFor(item.api.settingsContext);
      check(item.bar.settingsConsumer === client && item.second.settingsConsumer === client && item.panel.settingsConsumer === client, "actual views share exact selected HTTP client");
      check(find(item.panel, child => child.text === title(expected[i])), "actual Panel child renders selected source");
      var read = !news && (expected[i].readMessageIds ?? []).indexOf("message-" + expected[i][field]) >= 0;
      check(find(item.bar, child => news ? child.text && child.text.indexOf(title(expected[i])) >= 0 : child.text === (expected[i][field] && !read ? "1" : "0")), "actual Bar child renders selected result");
    }
    check(main._settingsConsumers.size === 4, "one HTTP client per API, not per view");
    console.log("HTTP_CONSUMERS " + JSON.stringify({
                                                     plugin: plugin,
                                                     scope: scope,
                                                     mode: mode,
                                                     boundary: name,
                                                     values: expected.map(value => value[field])
                                                   }));
  }
  function probe(name, next) {
    afterDisk = next;
    diskBoundary = name;
    phase = "disk";
    disk.command = ["python3", "-B", Quickshell.env("PHA_HTTP_DISK"), Quickshell.env("PHA_HTTP_CASE"), Quickshell.env("PHA_HTTP_OUTPUT") + "/persisted", name];
    disk.running = true;
  }
  function open(next) {
    check(scope === "shared" ? popup.openPluginSettings(api.manifest, "settings") : popup.openInstanceSettings(api.manifest, selected, "settings"), "actual scoped Settings opens");
    phase = next;
  }
  function edit() {
    var control = find(popup.settingsPage, item => item.label === (news ? "Category" : api.tr("settings.topics.label")) && (news ? item.selected !== undefined : item.editCommitted !== undefined));
    check(control, "actual source control");
    if (news)
      control.selected(editedValue);
    else {
      control.text = editedValue;
      control.editCommitted();
    }
    check(popup._pageApi.field(field).value === editedValue, "actual source control stages field");
    for (var key of Object.keys(api.manifest.metadata.settingsSchema.fields)) {
      if (api.manifest.metadata.settingsSchema.fields[key].editorUsage !== "configuration")
        continue;
      var handle = popup._pageApi.field(key);
      if (key !== field && handle)
        check(!handle.pendingIntent, "untouched field has no intent: " + key);
    }
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
    if (phase === "runtime" && selected.settingsReady && sibling.settingsReady && inherited.settingsReady) {
      presentations = [api, selected, sibling, inherited].map(context => ({
        api: context,
        bar: create("barWidget", context),
        second: create("barWidget", context),
        panel: create("panel", context)
      }));
      phase = "initial";
    } else if (phase === "initial") {
      var name = mode === "edit" ? "initial" : mode === "reset" ? "edited" : mode === "follow" ? "reset" : mode === "actions" ? "following" : boundary;
      if (!ready(name))
        return;
      observe(name);
      if (mode === "cold")
        finish();
      else if (mode === "edit")
        probe("initial", "open-discard");
      else if (mode === "follow")
        phase = "change-base";
      else if (mode === "actions")
        phase = "read-action";
      else
        open("reset-page");
    } else if (phase === "open-discard")
      open("discard-page");
    else if (phase === "discard-page" && popup.opened && popup.settingsPage) {
      check(!popup.dirty && !popup._editor.dirty, "page construction nonpublishing");
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
      probe("edited", oldRed ? "old-red-refresh" : "finish");
    } else if (phase === "old-red-refresh") {
      if (news)
        presentations[0].bar.fetchNews();
      else
        main.pollMessages();
      phase = "old-red";
    } else if (phase === "old-red" && !main.isLoading) {
      check(find(presentations[1].panel, child => child.text === title(values("edited")[1])), "original shared HTTP result does not render saved selected source");
      throw new Error("original shared HTTP defect did not reproduce");
    } else if (phase === "reset-page" && popup.opened && popup.settingsPage && !popup.busy) {
      check(popup._pageApi.field(field).reset(), "native staged Reset");
      observe("edited");
      probe("reset-staged", "reset-apply");
    } else if (phase === "reset-apply")
      apply("reset-applied");
    else if (phase === "reset-applied" && accepted() && ready("reset")) {
      observe("reset");
      probe("reset", "finish");
    } else if (phase === "change-base") {
      api.pluginSettings[field] = editedValue;
      phase = "base-saving";
      api.saveSettings(function (result) {
        try {
          check(result.status === "saved", "native shared propagation");
          phase = "base-changed";
        } catch (error) {
          fail(error);
        }
      });
    } else if (phase === "base-changed" && ready("following")) {
      observe("following");
      probe("following", "retire");
    } else if (phase === "read-action") {
      var button = find(presentations[1].panel, item => item.tooltipText === api.tr("panel.markAllRead") && item.clicked !== undefined);
      check(button, "actual selected Panel read action");
      button.clicked();
      phase = "read-saved";
    } else if (phase === "read-saved" && main.readMessageIds.indexOf("message-selected") >= 0) {
      observe("actions");
      probe("actions", "finish");
    } else if (phase === "retire") {
      Service.loadedPlugins = ({});
      phase = "retired";
    } else if (phase === "retired" && !selected.settingsContext.current()) {
      check(main._settingsConsumers.size === 0 && presentations.every(item => item.bar.settingsConsumer === null), "retirement releases every HTTP client");
      phase = "finish";
    } else if (phase === "finish")
      finish();
  }
  function finish() {
    console.log("HTTP_NATIVE: PASS " + plugin + " " + scope + " " + mode);
    Qt.exit(0);
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
