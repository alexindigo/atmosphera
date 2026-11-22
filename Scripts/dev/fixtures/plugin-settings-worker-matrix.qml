// Existing selected worker clients: native scopes, documents and final children.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins
import qs.Widgets

ShellRoot {
  id: root
  readonly property string plugin: Quickshell.env("WORKER_MATRIX_PLUGIN")
  readonly property string scope: Quickshell.env("WORKER_MATRIX_SCOPE")
  readonly property string leg: Quickshell.env("WORKER_MATRIX_LEG")
  readonly property string casePath: Quickshell.env("WORKER_MATRIX_CASE")
  readonly property bool air: plugin === "air-quality"
  readonly property bool contributions: plugin === "github-contributions"
  property var spec: null
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
  property var oldWorker: null
  property var retiredContext: null
  property var retiredClient: null
  property int stableTicks: 0
  property int edgeIndex: 0
  property string afterDisk: ""
  property string afterAction: ""
  FileView {
    id: input
    path: root.casePath + "/input.json"
    blockLoading: true
  }
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
    path: root.casePath + "/expectations.json"
    blockLoading: true
  }
  FileView {
    id: barrier
    path: root.casePath + "/hold/entered"
    printErrors: false
  }
  Process {
    id: disk
    onExited: code => {
      if (code !== 0)
        root.fail("independent complete documents");
      else
        root.phase = root.afterDisk;
    }
  }
  Process {
    id: actor
    onExited: code => {
      if (code !== 0)
        root.fail("controlled action");
      else
        root.phase = root.afterAction;
    }
  }
  PanelWindow {
    visible: true
    implicitWidth: 1280
    implicitHeight: 900
    Item {
      id: scene
      width: 1280
      height: 900
    }
    NPluginSettingsPopup {
      id: popup
      screen: Quickshell.screens[0]
      onSettingsCompleted: result => root.receipt = result
    }
  }
  function check(ok, label) {
    if (!ok)
      throw new Error("WORKER_MATRIX_ASSERT: " + plugin + "/" + scope + "/" + leg + "/" + phase + ": " + label);
    console.log("WORKER_MATRIX_CHECK: " + label);
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
        id: "plugin:" + plugin
      };
      props.widgetIndex = 0;
    }
    var view = component.createObject(scene, props);
    check(view, "actual " + entry);
    return view;
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    input.waitForJob();
    spec = JSON.parse(input.text());
    manifest.waitForJob();
    dictionary.waitForJob();
    var descriptor = JSON.parse(manifest.text()), dict = JSON.parse(dictionary.text()), registry = {};
    registry[plugin] = descriptor;
    Registry.installedPlugins = registry;
    Service._openSettingsOwner(plugin, function (owner) {
      try {
        check(owner, "native owner");
        api = Service.createPluginAPI(plugin, descriptor, owner, dict, dict, {});
        var loaded = {};
        loaded[plugin] = {
          api: api
        };
        Service.loadedPlugins = loaded;
        main = create("main", api);
        api.mainInstance = main;
        selected = PluginInstances.apiFor(plugin, {
                                            kind: "bar",
                                            list: "global",
                                            section: "left",
                                            index: 0
                                          });
        sibling = PluginInstances.apiFor(plugin, {
                                           kind: "bar",
                                           list: "global",
                                           section: "left",
                                           index: 1
                                         });
        inherited = PluginInstances.apiFor(plugin, {
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
    disk.command = ["python3", "-B", Quickshell.env("WORKER_MATRIX_DISK"), casePath, Quickshell.env("WORKER_MATRIX_OUTPUT") + "/persisted", name];
    disk.running = true;
  }
  function action(command, next) {
    afterAction = next;
    phase = "action";
    actor.command = command;
    actor.running = true;
  }
  function permission(mode, next) {
    action(["chmod", mode, Settings.configDir + (scope === "shared" ? "settings/plugins" : "settings")], next);
  }
  function values(name, index) {
    expectations.waitForJob();
    var docs = JSON.parse(expectations.text())[name];
    return Object.assign({}, api.manifest.metadata.defaultSettings, docs.shared, index < 0 ? {} : docs.bar.widgets.left[index].instanceSettings);
  }
  function readyClient(client, cfg) {
    if (client.cfg[spec.field] !== cfg[spec.field])
      return false;
    if (air) {
      var valid = String(cfg.customLatitude) !== "";
      return !client.loading && client.hasData === valid && (valid ? client.getAqi() === (cfg.customLatitude === "3" ? 151 : 17) : client.errorMessage.length > 0);
    }
    if (contributions) {
      var valid = String(cfg.username).trim() !== "";
      return !client.loading && client.hasData === valid && (valid ? client.totalContributions === (cfg.username === "synthetic-beta" ? 29 : 7) : client.errorMessage.length > 0);
    }
    return !client.refreshing && client.updates.map(row => row.name).join(",") === (String(cfg.systemCmd).endsWith(" beta") ? "beta-pkg" : "alpha-pkg");
  }
  function observeRow(row, client, cfg) {
    var linked = air || contributions ? row.desktop.mainInstance : row.desktop.updater;
    check(linked === client, "Desktop exact selected worker client");
    check((air || contributions ? row.second.mainInstance : row.second.updater) === client, "multiple views share exact context client");
    if (air) {
      check(row.bar.mainInstance === client, "Bar exact selected worker client");
      check(row.desktop.hasData === client.hasData && row.desktop.aqi === (client.hasData ? client.getAqi() : 0), "selected AQI presentation");
      check(find(row.desktop, child => child.text === (client.hasData ? String(client.getAqi()) : "--")), "actual Desktop AQI Text");
    } else if (contributions) {
      check(row.desktop.hasData === client.hasData, "selected contribution presentation");
      check(client.hasData ? row.desktop.columns === cfg.weeksShown : row.desktop.slicedDays.length === 0, "actual selected graph extent or empty generation");
      check(find(row.desktop, child => child.text === "@" + String(cfg.username).trim()), "actual Desktop account Text");
    } else {
      var pkg = String(cfg.systemCmd).endsWith(" beta") ? "beta-pkg" : "alpha-pkg";
      check(find(row.desktop, child => child.text === pkg && child.visible), "actual Desktop update row Text");
    }
  }
  function consumers(name, unconfirmedShared) {
    for (var i = 0; i < presentations.length; i++) {
      var row = presentations[i], cfg = values(name, i - 1), client = main.settingsConsumerFor(row.api.settingsContext);
      // A failed shared Apply keeps the unconfirmed shared value; inherited
      // contexts equal it, as a successful save would. Overrides stay.
      if (unconfirmedShared)
        cfg[spec.field] = values("edited", i - 1)[spec.field];
      if (!client || !readyClient(client, cfg))
        return false;
      // Wait for the actual view binding before comparing rendered descendants.
      if ((air || contributions) && row.desktop.hasData !== client.hasData)
        return false;
      observeRow(row, client, cfg);
      if (i > 0)
        check(client !== main.settingsConsumerFor(api.settingsContext), "independent native contexts");
    }
    check(main._settingsConsumers.size === 4, "one worker client per captured API");
    return true;
  }
  function open(next) {
    check(scope === "shared" ? popup.openPluginSettings(api.manifest, "settings") : popup.openInstanceSettings(api.manifest, selected, "settings"), "actual scoped page");
    phase = next;
  }
  function edit(value) {
    var control = find(popup.settingsPage, child => child.label === api.tr(spec.label) && child.editCommitted !== undefined);
    check(control, "actual representative text control");
    control.text = value;
    control.editCommitted();
    check(popup._pageApi.field(spec.field).value === value, "real control submits field intent");
    for (var key of Object.keys(api.manifest.metadata.settingsSchema.fields))
      if (key !== spec.field)
        check(!popup._pageApi.field(key).pendingIntent, "untouched field " + key);
  }
  function apply(next) {
    receipt = null;
    popup._pageApi.saveSettings(result => {
      check(receipt && receipt.status === result.status, "signal precedes callback");
      callbacks++;
    });
    check(popup.applySettings(), "native Apply");
    phase = next;
  }
  function accepted() {
    return receipt && !popup.busy && ["saved", "nothing_to_save"].includes(receipt.status) && receipt.refreshState === "current";
  }
  function changeBase(value, next) {
    api.pluginSettings[spec.field] = value;
    phase = "base-save";
    api.saveSettings(result => {
      try {
        check(["saved", "nothing_to_save"].includes(result.status), "native base publication");
        phase = next;
      } catch (error) {
        fail(error);
      }
    });
  }
  function driveOpening() {
    if (phase === "ready" && selected.settingsReady && sibling.settingsReady && inherited.settingsReady) {
      presentations = [api, selected, sibling, inherited].map(runtime => ({
        api: runtime,
        desktop: create("desktopWidget", runtime),
        second: create("desktopWidget", runtime),
        bar: air ? create("barWidget", runtime) : null
      }));
      phase = leg === "edges" ? "edge-next" : "initial";
    } else if (phase === "initial" && consumers(leg === "warm" ? "initial" : "stale"))
      probe(leg === "warm" ? "initial" : "stale", leg === "warm" ? "open-discard" : leg === "cold" ? "finish" : "hold");
    else if (phase === "open-discard")
      open("discard-page");
    else if (phase === "discard-page" && popup.opened && popup.settingsPage) {
      check(!popup.dirty, "construction has no intent");
      edit(spec.edit);
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
      edit(spec.edit);
      failedPage = popup.settingsPage;
      failedEditor = popup._editor;
      permission("500", "blocked");
    } else if (phase === "blocked")
      apply("failed");
    else if (phase === "failed" && receipt && !popup.busy) {
      check(receipt.status === "failed" && popup.settingsPage === failedPage && popup._editor === failedEditor, "IO failure retains exact page/editor");
      check(!popup.requestClose(), "failed Close refuses");
      popup.keepEditing();
      phase = "failed-converge";
    } else if (phase === "failed-converge" && consumers("initial", scope === "shared")) {
      check(popup.saveFailed && popup.settingsPage === failedPage && popup._editor === failedEditor, "failed state retained while consumers converge");
      probe("initial", "unblock");
    } else if (phase === "unblock")
      permission("700", "retry");
    else if (phase === "retry")
      apply("applied");
    else if (phase === "applied" && accepted() && consumers("edited")) {
      check(callbacks === 2, "failure and Retry callbacks");
      probe("edited", "close-edit");
    }
  }
  function driveReset() {
    if (phase === "close-edit") {
      check(popup.requestClose(), "clean Close");
      phase = "closed";
    } else if (phase === "closed" && !popup._editor)
      changeBase(spec.base, "base-changed");
    else if (phase === "base-changed" && consumers("base"))
      probe("base", "open-reset");
    else if (phase === "open-reset")
      open("reset-page");
    else if (phase === "reset-page" && popup.opened && popup.settingsPage) {
      check(popup._pageApi.field(spec.field).reset(), "native staged Reset");
      phase = "reset-staged";
    } else if (phase === "reset-staged" && !popup._editor.busy && popup._pageApi.field(spec.field).pendingIntent === "reset")
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
      changeBase(spec.edit, "inherited");
    else if (phase === "inherited" && consumers("following"))
      probe("following", "open-stale");
    else if (phase === "open-stale")
      open("stale-page");
    else if (phase === "stale-page" && popup.opened && popup.settingsPage) {
      edit(spec.base);
      failedPage = popup.settingsPage;
      failedEditor = popup._editor;
      changeBase(spec.base, "stale-base");
    } else if (phase === "stale-base" && consumers("stale"))
      apply("stale-result");
    else if (phase === "stale-result" && receipt && !popup.busy) {
      check(receipt.status === "failed" && popup.settingsPage === failedPage && popup._editor === failedEditor, "stale editor retained without retargeting");
      check(!popup.requestClose(), "stale Close refuses");
      popup.keepEditing();
      check(popup.confirmDiscard(), "explicit stale discard");
      phase = "stale-discarded";
    } else if (phase === "stale-discarded" && !popup._editor && consumers("stale"))
      probe("stale", "finish");
  }
  function driveHeld() {
    if (phase === "hold")
      action(["touch", casePath + "/hold/hold"], "refresh-held");
    else if (phase === "refresh-held") {
      main.settingsConsumerFor(selected.settingsContext).refresh();
      phase = "held";
    } else if (phase === "held") {
      barrier.reload();
      barrier.waitForJob();
      if (barrier.text().trim() !== "entered")
        return;
      oldWorker = main.settingsConsumerFor(selected.settingsContext)._worker;
      selected.pluginSettings[spec.field] = spec.lifetime;
      phase = "lifetime-save";
      selected.saveSettings(result => {
        try {
          check(["saved", "nothing_to_save"].includes(result.status), "originating runtime publication");
          phase = "replaced";
        } catch (error) {
          fail(error);
        }
      });
    } else if (phase === "replaced" && consumers("replacement")) {
      check(oldWorker === null, "old worker destroyed on source replacement");
      action(["touch", casePath + "/hold/release"], "released");
    } else if (phase === "released" && consumers("replacement")) {
      if (++stableTicks < 12)
        return;
      probe("replacement", "retire");
    }
  }
  function driveRetire() {
    if (phase === "retire") {
      retiredContext = selected.settingsContext;
      retiredClient = main.settingsConsumerFor(retiredContext);
      Settings.data.bar.widgets.left = Settings.data.bar.widgets.left.slice(1);
      phase = "retired";
    } else if (phase === "retired" && !retiredContext.current()) {
      check(retiredClient === null && !main._settingsConsumers.has(retiredContext), "native retirement destroys exact client");
      check((air || contributions ? presentations[1].desktop.mainInstance : presentations[1].desktop.updater) === null, "retired Desktop releases client");
      phase = "retire-save";
      Settings.store.saveSelected([["bar", "widgets", "left"]], result => {
        try {
          check(["saved", "nothing_to_save"].includes(result.status), "owning-list publication");
          phase = "retire-saved";
        } catch (error) {
          fail(error);
        }
      });
    } else if (phase === "retire-saved")
      probe("retired", "finish");
    else if (phase === "finish") {
      console.log("WORKER_MATRIX: PASS " + plugin + " " + scope + " " + leg);
      Qt.exit(0);
    }
  }
  function driveEdges() {
    if (phase === "edge-next") {
      if (edgeIndex === spec.edges.length) {
        phase = "finish";
        return;
      }
      var patch = spec.edges[edgeIndex].patch;
      for (var key of Object.keys(patch))
        selected.pluginSettings[key] = patch[key];
      phase = "edge-save";
      selected.saveSettings(result => {
        try {
          check(["saved", "nothing_to_save"].includes(result.status), "edge originating native publication");
          phase = "edge-observe";
        } catch (error) {
          fail(error);
        }
      });
    } else if (phase === "edge-observe") {
      var edge = spec.edges[edgeIndex], client = main.settingsConsumerFor(selected.settingsContext), view = presentations[1].desktop;
      if (Object.keys(edge.patch).some(key => client.cfg[key] !== edge.patch[key]))
        return;
      if (air || contributions) {
        if (client.loading || client.hasData !== edge.hasData || view.hasData !== edge.hasData)
          return;
        if (!edge.hasData && !client.errorMessage.length)
          return;
        if (air) {
          if (client.hasData && client.getAqi() !== edge.value)
            return;
          check(find(view, child => child.text === (edge.hasData ? String(edge.value) : "--")), "source-mode actual AQI Text");
          if (edge.station)
            check(find(view, child => child.text === edge.station), "actual provider station Text");
        } else {
          if (client.hasData && client.totalContributions !== edge.value)
            return;
          check(edge.hasData ? view.columns === edge.columns : view.slicedDays.length === 0, "source-mode actual graph extent or empty result");
          check(find(view, child => child.text === "@" + client.username), "source-mode actual account Text");
        }
      } else {
        if (client.refreshing || client.updates.map(row => row.name).join(",") !== edge.names.join(","))
          return;
        for (var name of edge.names)
          check(find(view, child => child.text === name && child.visible), "actual multi-stage update Text " + name);
        check(client._worker !== null, "multi-stage worker remains selected");
      }
      for (var i of [0, 2, 3]) {
        var row = presentations[i], cfg = values("initial", i - 1), other = main.settingsConsumerFor(row.api.settingsContext);
        if (!readyClient(other, cfg))
          return;
        observeRow(row, other, cfg);
      }
      check((air || contributions ? view.mainInstance : view.updater) === client, "source-mode exact selected client");
      probe(edge.name, "edge-next");
      edgeIndex++;
    }
  }
  function drive() {
    check(Date.now() - since < 22000, "finite phase");
    if (["ready", "initial", "open-discard", "discard-page", "discarded"].includes(phase)) {
      driveOpening();
      return;
    }
    if (["open-edit", "edit-page", "blocked", "failed", "failed-converge", "unblock", "retry", "applied"].includes(phase)) {
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
    if (["hold", "refresh-held", "held", "replaced", "released"].includes(phase)) {
      driveHeld();
      return;
    }
    if (["edge-next", "edge-observe"].includes(phase)) {
      driveEdges();
      return;
    }
    driveRetire();
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
