// Selected Git consumers: real page signals/native publication, inert processes.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins
import qs.Widgets

ShellRoot {
  id: root
  readonly property string scenario: Quickshell.env("PHA_GIT_SCENARIO")
  readonly property bool cold: Quickshell.env("PHA_GIT_COLD") === "1"
  readonly property string output: Quickshell.env("PHA_GIT_OUTPUT")
  property bool started: false
  property string phase: "startup"
  property string afterDisk: ""
  property string actorNext: ""
  property var api: null
  property var main: null
  property var selected: null
  property var sibling: null
  property var inherited: null
  property var client: null
  property var other: null
  property var follower: null
  property var panel: null
  property var otherPanel: null
  property var inheritedPanel: null
  property var receipt: null
  property var failedPage: null
  property var failedEditor: null
  property var oldWorker: null
  property int stable: 0
  FileView {
    id: manifestFile
    path: Settings.configDir + "plugins/git-companion/manifest.json"
    blockLoading: true
    printErrors: false
  }
  FileView {
    id: entered
    path: root.output + "/entered"
    printErrors: false
  }
  FileView {
    id: expectedFile
    path: Quickshell.env("PHA_GIT_CASE") + "/cold.json"
    blockLoading: true
    printErrors: false
  }
  Process {
    id: actor
    onExited: function (code) {
      if (code !== 0)
        root.fail("fixture actor failed: " + code);
      else
        root.phase = root.actorNext;
    }
  }
  Process {
    id: disk
    onExited: function (code) {
      if (code !== 0) {
        root.fail("independent native-file boundary failed");
        return;
      }
      root.phase = root.afterDisk;
    }
  }
  PanelWindow {
    id: host
    visible: true
    implicitWidth: 1280
    implicitHeight: 800
    Item {
      id: selectedHost
      width: 400
      height: 700
    }
    Item {
      id: siblingHost
      x: 410
      width: 400
      height: 700
    }
    Item {
      id: inheritedHost
      x: 820
      width: 400
      height: 700
    }
    NPluginSettingsPopup {
      id: popup
      screen: Quickshell.screens[0]
      onSettingsCompleted: result => root.receipt = result
    }
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("GIT_MATRIX_ASSERT: " + scenario + "/" + phase + ": " + message);
  }
  function fail(error) {
    console.error(String(error) + "\n" + (error.stack || ""));
    Qt.exit(2);
  }
  function find(object, predicate) {
    if (object && predicate(object))
      return object;
    for (var list of [object?.data, object?.children, object?.resources]) {
      if (!list)
        continue;
      for (var i = 0; i < list.length; i++) {
        var found = find(list[i], predicate);
        if (found)
          return found;
      }
    }
    return null;
  }
  function row(object, repo) {
    return find(object, item => item.text === "result for " + repo) !== null;
  }
  function create(entry, parent, context) {
    var component = Qt.createComponent("file://" + api.pluginDir + "/" + api.manifest.entryPoints[entry]);
    check(component.status === Component.Ready, component.errorString());
    var item = PluginLoader.createObject("git-companion", entry, component, parent, context, {});
    check(item !== null, "actual " + entry);
    return item;
  }
  function control(label) {
    var found = find(popup.settingsPage, item => item.label === api.tr(label));
    check(found !== null, "actual control " + label);
    return found;
  }
  function repo(value) {
    var input = control("settings.repo.label");
    input.text = value;
    input.editCommitted();
    check(popup._pageApi.field("repo").value === value, "actual committed repository intent");
  }
  function apply(next) {
    receipt = null;
    check(popup.applySettings(), "native selected Apply admitted");
    phase = next;
  }
  function accepted() {
    return receipt && !popup.busy && receipt.status === "saved" && receipt.refreshState === "current";
  }
  function probe(boundary, next) {
    afterDisk = next;
    phase = "disk";
    disk.command = ["python3", "-B", Quickshell.env("PHA_GIT_DISK"), Settings.configDir.replace(/\/$/, ""), boundary];
    disk.running = true;
  }
  function action(command, next) {
    actorNext = next;
    actor.command = command;
    actor.running = true;
    phase = "actor";
  }
  function publishBase(value, next) {
    api.pluginSettings.repo = value;
    phase = "base-saving";
    api.saveSettings(function (result) {
      try {
        // Runtime store.saveSelected receipts do not carry overlay refreshState.
        check(result.status === "saved", "actual shared publication");
        root.phase = next;
      } catch (error) {
        fail(error);
      }
    });
  }
  function invariant() {
    check(other.repo === "synthetic/other" && row(otherPanel, "synthetic/other"), "sibling scope/result unchanged");
    check(client === main.settingsConsumerFor(selected.settingsContext) && client !== other && client !== follower, "one stable selected client per API");
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    manifestFile.waitForJob();
    var manifest = JSON.parse(manifestFile.text());
    Registry.installedPlugins = {
      "git-companion": manifest
    };
    Service._openSettingsOwner("git-companion", function (owner) {
      try {
        check(owner !== null, "native plugin owner");
        api = Service.createPluginAPI("git-companion", manifest, owner, {}, {}, {});
        Service.loadedPlugins = {
          "git-companion": {
            api: api
          }
        };
        main = create("main", root, api);
        api.mainInstance = main;
        selected = PluginInstances.apiFor("git-companion", {
                                            kind: "bar",
                                            list: "global",
                                            section: "left",
                                            index: 0
                                          });
        sibling = PluginInstances.apiFor("git-companion", {
                                           kind: "bar",
                                           list: "global",
                                           section: "left",
                                           index: 1
                                         });
        inherited = PluginInstances.apiFor("git-companion", {
                                             kind: "bar",
                                             list: "global",
                                             section: "left",
                                             index: 2
                                           });
        phase = "runtime";
      } catch (error) {
        fail(error);
      }
    });
  }
  function drive() {
    if (phase === "runtime" && selected.settingsReady && sibling.settingsReady && inherited.settingsReady) {
      client = main.settingsConsumerFor(selected.settingsContext);
      other = main.settingsConsumerFor(sibling.settingsContext);
      follower = main.settingsConsumerFor(inherited.settingsContext);
      check(other.repo === "synthetic/other" && other !== client, "selected client must not use shared Main configuration");
      panel = create("panel", selectedHost, selected);
      otherPanel = create("panel", siblingHost, sibling);
      inheritedPanel = create("panel", inheritedHost, inherited);
      phase = cold ? "cold" : "initial";
    } else if (phase === "cold") {
      expectedFile.waitForJob();
      var expected = JSON.parse(expectedFile.text());
      if (client.loading || follower.loading || other.loading || !row(otherPanel, "synthetic/other"))
        return;
      check(client.platform === expected.platform && client.repo === expected.repo && client.group === expected.group && client.refreshInterval === expected.interval, "cold selected query configuration");
      check(expected.scope === "" ? client.issuesCount === 0 && !client.hasScope : row(panel, expected.scope), "cold actual selected Panel result");
      check(row(inheritedPanel, expected.base) && main.repo === expected.base, "cold inherited and shared consumers");
      invariant();
      console.log("GIT_MATRIX: COLD_PASS " + scenario);
      Qt.exit(0);
    } else if (phase === "initial" && row(panel, "synthetic/alpha") && row(otherPanel, "synthetic/other") && row(inheritedPanel, "synthetic/alpha")) {
      invariant();
      check(popup.openInstanceSettings(api.manifest, selected, "settings"), "actual selected Settings opens");
      phase = "page";
    } else if (phase === "page" && popup.opened && popup.settingsPage) {
      check(!popup.dirty && !popup._editor.dirty, "construction creates no intent");
      repo("synthetic/beta");
      check(row(panel, "synthetic/alpha") && client.repo === "synthetic/alpha", "staged input cannot publish/query");
      failedPage = popup.settingsPage;
      failedEditor = popup._editor;
      if (scenario === "io-retry") {
        action(["chmod", "500", Settings.configDir + "settings"], "submit-failed");
      } else if (scenario === "stale-base") {
        publishBase("synthetic/gamma", "stale-ready");
      } else if (scenario === "source-replacement") {
        action(["python3", "-B", Quickshell.env("PHA_GIT_REPLACE"), Settings.configDir + "settings/plugins/git-companion.json"], "stale-ready");
      } else if (scenario === "held-response") {
        action(["touch", output + "/hold"], "submit-held");
      } else if (scenario === "platform-group" || scenario === "unconfigured") {
        control("settings.platform.label").selected("gitlab");
        repo(scenario === "unconfigured" ? "" : "synthetic/beta");
        if (scenario === "platform-group") {
          var groupInput = control("settings.group.label");
          groupInput.text = "synthetic-team";
          groupInput.editCommitted();
          control("settings.refreshInterval.label").valueModified(90);
        }
        apply("selected-applied");
      } else {
        apply("selected-applied");
      }
    } else if (phase === "submit-failed") {
      apply("failed");
    } else if (phase === "failed" && receipt && !popup.busy) {
      check(receipt.status === "failed" && popup.saveFailed, "real IO failure not acknowledged");
      check(client.repo === "synthetic/alpha" && row(panel, "synthetic/alpha"), "failed persistence cannot refresh selected query");
      check(popup.settingsPage === failedPage && popup._editor === failedEditor, "failure retains exact page/editor");
      invariant();
      probe("failed", "restore-permissions");
    } else if (phase === "restore-permissions") {
      action(["chmod", "700", Settings.configDir + "settings"], "retry");
    } else if (phase === "retry") {
      check(popup.settingsPage === failedPage && popup._editor === failedEditor, "Retry retains selected capture");
      apply("selected-applied");
    } else if (phase === "stale-ready" && client.repo === "synthetic/gamma" && row(panel, "synthetic/gamma")) {
      check(popup.settingsPage === failedPage && popup._pageApi.field("repo").value === "synthetic/beta", "external source preserves readable local input");
      apply("stale-refused");
    } else if (phase === "stale-refused" && receipt && !popup.busy) {
      check(receipt.status === "failed" || receipt.refreshState !== "current", "stale capture cannot acknowledge");
      check(client.repo === "synthetic/gamma" && row(panel, "synthetic/gamma"), "stale Apply cannot query local beta");
      invariant();
      probe("stale", "finish");
    } else if (phase === "submit-held") {
      apply("held");
    } else if (phase === "held" && accepted()) {
      entered.reload();
      entered.waitForJob();
      if (entered.text().trim() !== "entered")
        return;
      check(client.loading, "actual beta endpoint response held");
      oldWorker = client._worker;
      probe("held", "replace-held");
    } else if (phase === "replace-held") {
      repo("synthetic/gamma");
      apply("replacement");
    } else if (phase === "replacement" && accepted() && row(panel, "synthetic/gamma") && !client.loading) {
      check(!oldWorker || !oldWorker.active, "old query generation retired");
      action(["touch", output + "/release"], "old-released");
    } else if (phase === "old-released") {
      check(client.repo === "synthetic/gamma" && row(panel, "synthetic/gamma") && !row(panel, "synthetic/beta"), "old held response cannot repopulate replacement");
      if (++stable < 12)
        return;
      invariant();
      probe("replacement", "finish");
    } else if (phase === "selected-applied" && accepted() && !client.loading && (scenario === "unconfigured" ? client.issuesCount === 0 && !client.hasScope : row(panel, scenario === "platform-group" ? "synthetic-team" : "synthetic/beta"))) {
      invariant();
      check(main.repo === "synthetic/alpha" && row(inheritedPanel, "synthetic/alpha"), "selected publication cannot refresh shared/inherited scopes");
      probe("edited", scenario === "inheritance" ? "base-change" : "finish");
    } else if (phase === "base-change") {
      check(popup.requestClose(), "close accepted editor before base replacement");
      publishBase("synthetic/gamma", "base-changed");
    } else if (phase === "base-changed" && row(inheritedPanel, "synthetic/gamma") && row(panel, "synthetic/beta")) {
      invariant();
      probe("base-changed", "reset-open");
    } else if (phase === "reset-open") {
      check(popup.openInstanceSettings(api.manifest, selected, "settings"), "reopen captured current base");
      phase = "reset-page";
    } else if (phase === "reset-page" && popup.opened && popup.settingsPage) {
      check(popup._pageApi.field("repo").overridden, "stored repo override");
      check(popup._pageApi.field("repo").reset(), "staged native field Reset");
      check(popup._pageApi.field("repo").value === "synthetic/gamma" && client.repo === "synthetic/beta", "Reset shows inherited without publication");
      probe("reset-staged", "reset-apply");
    } else if (phase === "reset-apply") {
      apply("reset-applied");
    } else if (phase === "reset-applied" && accepted() && row(panel, "synthetic/gamma")) {
      probe("reset", "later-base");
    } else if (phase === "later-base") {
      check(popup.requestClose(), "clean Reset Close");
      publishBase("synthetic/delta", "later-inherited");
    } else if (phase === "later-inherited" && row(panel, "synthetic/delta") && row(inheritedPanel, "synthetic/delta")) {
      invariant();
      probe("inherited", "finish");
    } else if (phase === "finish") {
      if (popup.visible) {
        if (!popup.requestClose())
          check(popup.confirmDiscard(), "explicit discard of refused stale input");
      }
      Service.loadedPlugins = ({});
      phase = "retired";
    } else if (phase === "retired" && main._settingsConsumers.size === 0) {
      check(!row(panel, "synthetic/beta") && !row(otherPanel, "synthetic/other"), "retired clients cannot present stale result rows");
      console.log("GIT_MATRIX: PASS " + scenario);
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
  Timer {
    interval: 90000
    running: true
    onTriggered: root.fail("Git matrix watchdog " + phase)
  }
  Component.onCompleted: begin()
}
