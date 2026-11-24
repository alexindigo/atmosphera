// Real provider page -> native documents -> actual Bar/Panel, separate cold engines.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins
import qs.Widgets

ShellRoot {
  id: root
  readonly property string scope: Quickshell.env("PHA_PROVIDER_SCOPE")
  readonly property string mode: Quickshell.env("PHA_PROVIDER_MODE")
  readonly property string boundary: Quickshell.env("PHA_PROVIDER_BOUNDARY")
  readonly property bool oldRed: Quickshell.env("PHA_PROVIDER_OLD_RED") === "1"
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
    path: Settings.configDir + "plugins/github-feed/manifest.json"
    blockLoading: true
  }
  FileView {
    id: dictionaryFile
    path: Settings.configDir + "plugins/github-feed/i18n/en.json"
    blockLoading: true
  }
  FileView {
    id: expectedFile
    path: Quickshell.env("PHA_PROVIDER_CASE") + "/expectations.json"
    blockLoading: true
  }
  Process {
    id: disk
    onExited: code => {
      if (code !== 0)
        root.fail("independent complete provider readback: " + root.diskBoundary);
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
      throw new Error("PROVIDER_ASSERT: " + scope + "/" + mode + "/" + phase + ": " + message);
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
    if (predicate(object))
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
    var item = PluginLoader.createObject("github-feed", entry, component, content, context, {
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
    Registry.installedPlugins = {
      "github-feed": manifest
    };
    Service._openSettingsOwner("github-feed", function (owner) {
      try {
        check(owner !== null, "actual native plugin owner");
        api = Service.createPluginAPI("github-feed", manifest, owner, dictionary, dictionary, {});
        Service.loadedPlugins = {
          "github-feed": {
            api: api
          }
        };
        main = create("main", api);
        api.mainInstance = main;
        var contexts = [0, 1, 2].map(index => PluginInstances.apiFor("github-feed", {
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
  function ready(name) {
    var expected = values(name);
    if (!oldRed) {
      for (var item of presentations) {
        var client = main.settingsConsumerFor(item.api.settingsContext);
        check(item.bar.settingsConsumer === client && item.second.settingsConsumer === client && item.panel.settingsConsumer === client, "actual views share exact selected provider client");
      }
    }
    return presentations.every((item, i) => item.api.pluginSettings.username === expected[i].username && (oldRed || (!item.bar.isLoading && (expected[i].username ? find(item.panel, child => child.text === expected[i].username + "/controlled") : item.panel.events.length === 0))));
  }
  function observe(name) {
    if (oldRed)
      return;
    var expected = values(name);
    for (var i = 0; i < presentations.length; i++) {
      var item = presentations[i], client = main.settingsConsumerFor(item.api.settingsContext), user = expected[i].username;
      check(item.bar.settingsConsumer === client && item.second.settingsConsumer === client && item.panel.settingsConsumer === client, "actual views share exact selected provider client");
      check(user ? find(item.panel, child => child.text === user + "/controlled") : item.panel.events.length === 0, "actual Panel child renders selected account");
      var count = user === "selected" ? 2 : user ? 1 : 0;
      check(item.bar.tooltipText.indexOf(count + " events") >= 0 || (!user && item.bar.tooltipText.indexOf("Click to configure") >= 0), "actual Bar tooltip renders selected result count");
    }
    check(main._settingsConsumers.size === 4, "one provider client per API not per view");
    console.log("PROVIDER_CONSUMERS " + JSON.stringify({
                                                         scope: scope,
                                                         mode: mode,
                                                         boundary: name,
                                                         values: expected.map(value => value.username)
                                                       }));
  }
  function probe(name, next) {
    afterDisk = next;
    diskBoundary = name;
    phase = "disk";
    disk.command = ["python3", "-B", Quickshell.env("PHA_PROVIDER_DISK"), Quickshell.env("PHA_PROVIDER_CASE"), Quickshell.env("PHA_PROVIDER_OUTPUT") + "/persisted", name];
    disk.running = true;
  }
  function open(next) {
    check(scope === "shared" ? popup.openPluginSettings(api.manifest, "settings") : popup.openInstanceSettings(api.manifest, selected, "settings"), "actual scoped Settings opens");
    phase = next;
  }
  function edit() {
    var control = find(popup.settingsPage, item => item.label === "GitHub Username" && item.editCommitted !== undefined);
    check(control, "actual username control");
    control.text = "selected";
    control.editCommitted();
    check(popup._pageApi.field("username").value === "selected", "actual username control stages field");
    for (var key of Object.keys(api.manifest.metadata.settingsSchema.fields)) {
      if (api.manifest.metadata.settingsSchema.fields[key].editorUsage !== "configuration")
        continue;
      var handle = popup._pageApi.field(key);
      if (key !== "username" && handle)
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
      var name = mode === "edit" ? "initial" : mode === "reset" ? "edited" : mode === "follow" ? "reset" : boundary;
      if (!ready(name))
        return;
      observe(name);
      if (mode === "cold")
        finish();
      else if (mode === "edit")
        probe("initial", "open-discard");
      else if (mode === "follow")
        phase = "change-base";
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
      main.fetchFromGitHub();
      phase = "old-red";
    } else if (phase === "old-red" && !main.isLoading) {
      check(find(presentations[1].panel, child => child.text === "selected/controlled"), "original shared provider result does not render saved selected source");
      throw new Error("original shared provider defect did not reproduce");
    } else if (phase === "reset-page" && popup.opened && popup.settingsPage && !popup.busy) {
      check(popup._pageApi.field("username").reset(), "native staged Reset");
      observe("edited");
      probe("reset-staged", "reset-apply");
    } else if (phase === "reset-apply")
      apply("reset-applied");
    else if (phase === "reset-applied" && accepted() && ready("reset")) {
      observe("reset");
      probe("reset", "finish");
    } else if (phase === "change-base") {
      api.pluginSettings.username = "selected";
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
    } else if (phase === "retire") {
      Service.loadedPlugins = ({});
      phase = "retired";
    } else if (phase === "retired" && !selected.settingsContext.current()) {
      check(main._settingsConsumers.size === 0 && presentations.every(item => item.bar.settingsConsumer === null), "retirement releases all provider clients");
      phase = "finish";
    } else if (phase === "finish")
      finish();
  }
  function finish() {
    console.log("PROVIDER_NATIVE: PASS " + scope + " " + mode);
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
