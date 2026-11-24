// Real page/native owners and actual conversion/Timer/presentation endpoints.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins
import qs.Widgets

ShellRoot {
  id: root
  readonly property string scope: Quickshell.env("PHA_CURRENCY_SCOPE")
  readonly property string mode: Quickshell.env("PHA_CURRENCY_MODE")
  readonly property string boundary: Quickshell.env("PHA_CURRENCY_BOUNDARY")
  readonly property bool oldRed: Quickshell.env("PHA_CURRENCY_OLD_RED") === "1"
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
  property var policyClient: null
  property real policyAttempt: 0
  property real policyFetch: 0
  property int policyUpdates: 0
  property string afterDisk: ""
  property int resetIndex: 0
  readonly property var keys: ["sourceCurrency", "targetCurrency", "widgetDisplayMode", "refreshInterval"]
  FileView {
    id: manifestFile
    path: Settings.configDir + "plugins/currency-exchange/manifest.json"
    blockLoading: true
  }
  FileView {
    id: dictionaryFile
    path: Settings.configDir + "plugins/currency-exchange/i18n/en.json"
    blockLoading: true
  }
  FileView {
    id: expectedFile
    path: Quickshell.env("PHA_CURRENCY_CASE") + "/expectations.json"
    blockLoading: true
  }
  FileView {
    id: heldFile
    path: Quickshell.env("PHA_CURRENCY_CASE") + "/held"
  }
  Process {
    id: disk
    onExited: function (code) {
      if (code !== 0)
        root.fail("CURRENCY_DISK " + phase);
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
      throw new Error("CURRENCY_ASSERT: " + scope + "/" + mode + "/" + phase + ": " + message);
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
    var item = PluginLoader.createObject("currency-exchange", entry, component, entry === "main" ? root : content, context, {
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
    var manifest = JSON.parse(manifestFile.text());
    var dictionary = JSON.parse(dictionaryFile.text());
    Registry.installedPlugins = {
      "currency-exchange": manifest
    };
    Service._openSettingsOwner("currency-exchange", function (owner) {
      try {
        check(owner !== null, "native owner");
        api = Service.createPluginAPI("currency-exchange", manifest, owner, dictionary, dictionary, {});
        Service.loadedPlugins = {
          "currency-exchange": {
            api: api
          }
        };
        api.mainInstance = create("main", api);
        if (mode === "policy") {
          policyClient = api.mainInstance.settingsConsumer;
          policyClient.ratesUpdated.connect(function () {
            root.policyUpdates++;
          });
          phase = "policy-failed";
          return;
        }
        var instances = [0, 1, 2].map(function (index) {
          return PluginInstances.apiFor("currency-exchange", {
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
    var expected = JSON.parse(expectedFile.text())[name];
    var base = Object.assign({}, api.manifest.metadata.defaultSettings, expected.shared);
    return [base].concat(expected.bar.widgets.left.map(function (row) {
      return Object.assign({}, base, row.instanceSettings || {});
    }));
  }
  function observe(name) {
    var expected = values(name), rates = {
      USD: 1,
      EUR: 2,
      GBP: 4,
      JPY: 100
    };
    for (var i = 0; i < presentations.length; i++) {
      var item = presentations[i], value = expected[i];
      var client = item.panel.main;
      var timer = find(client, child => child.interval !== undefined && child.repeat === true && child.triggered !== undefined);
      check(timer && timer.interval === value.refreshInterval * 60000 && timer.running, "actual refresh Timer follows selected interval");
      if (!oldRed) {
        check(client === api.mainInstance.settingsConsumerFor(item.api.settingsContext), "selected context owns client");
        check(item.bar.main === client && item.launcher.main === client, "all views share selected client identity");
      }
      var rate = rates[value.targetCurrency] / rates[value.sourceCurrency];
      check(item.panel.fromCurrency === value.sourceCurrency && item.panel.toCurrency === value.targetCurrency && item.panel.toAmount === rate, "actual Panel conversion follows selected currencies");
      var resultText = find(item.panel, child => child !== item.panel && child.font !== undefined && child.font.weight === Style.fontWeightBold && Qt.colorEqual(child.color, AtmoColor.mOnPrimary));
      check(resultText && resultText.text === rate.toFixed(2), "actual child Panel result Text");
      var displayed = value.widgetDisplayMode === "compact" ? client.formatNumber(rate) : "1 " + value.sourceCurrency + " = " + client.formatNumber(rate) + " " + value.targetCurrency;
      var barText = find(item.bar, child => child !== item.bar && child.font !== undefined && child.text === displayed);
      check(item.bar.displayMode === value.widgetDisplayMode && barText && barText.visible === (value.widgetDisplayMode !== "icon"), "actual Bar rate Text and display mode");
      var results = item.launcher.getResults(">fx 2");
      check(results.length === 2 && results[0].name === "2 " + value.sourceCurrency + " = " + client.formatNumber(2 * rate) + " " + value.targetCurrency, "actual Launcher result follows selected currencies");
      check(client.loaded && !client.loading && client.cachedRates.USD === 1, "real rates process admitted USD base");
    }
    console.log("CURRENCY_CONSUMERS " + JSON.stringify({
                                                         scope: scope,
                                                         mode: mode,
                                                         boundary: name,
                                                         values: expected
                                                       }));
  }
  function runtimeReady(name) {
    var expected = values(name);
    return presentations.every(function (item, index) {
      return keys.every(key => item.api.pluginSettings[key] === expected[index][key]) && item.panel.loaded && !item.panel.loading;
    });
  }
  function probe(name, next) {
    afterDisk = next;
    phase = "disk";
    disk.command = ["python3", "-B", Quickshell.env("PHA_CURRENCY_DISK"), Quickshell.env("PHA_CURRENCY_CASE"), Quickshell.env("PHA_CURRENCY_OUTPUT") + "/persisted", name, scope];
    disk.running = true;
  }
  function open(next) {
    check(scope === "shared" ? popup.openPluginSettings(api.manifest, "settings") : popup.openInstanceSettings(api.manifest, selected, "settings"), "actual Settings opens");
    phase = next;
  }
  function edit() {
    var labels = ["source_currency", "target_currency", "display_mode", "refresh_interval"], data = ["GBP", "JPY", "full", "30"];
    for (var i = 0; i < labels.length; i++) {
      var control = find(popup.settingsPage, child => child.label === api.tr("settings." + labels[i]));
      check(control && control.selected, "actual combo control " + labels[i]);
      control.selected(data[i]);
    }
    check(keys.every((key, i) => popup._pageApi.field(key).value === (i === 3 ? 30 : data[i])), "four explicit field intents");
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
    if (phase === "policy-failed" && !policyClient.loading && policyClient.lastFetchAttempt > 0) {
      check(!policyClient.loaded && policyUpdates === 0, "real failed response has no rates/result");
      policyAttempt = policyClient.lastFetchAttempt;
      policyClient.fetchRates();
      check(!policyClient.loading && policyClient.lastFetchAttempt === policyAttempt, "failed-attempt automatic retry throttle");
      policyClient.fetchRates(true);
      check(policyClient.loading, "forced failed-attempt Retry starts real process");
      phase = "policy-loaded";
    } else if (phase === "policy-loaded" && policyClient.loaded && !policyClient.loading) {
      check(policyUpdates === 1 && policyClient.getRate("EUR", "GBP") === 2, "forced Retry reaches conversion consumer");
      policyAttempt = policyClient.lastFetchAttempt;
      policyFetch = policyClient.lastFetch;
      policyClient.fetchRates(true);
      check(!policyClient.loading && policyClient.lastFetchAttempt === policyAttempt && policyClient.lastFetch === policyFetch, "fresh five-minute cache even on forced Retry");
      policyClient.lastFetch = Date.now() - 300001;
      policyClient.fetchRates();
      check(policyClient.loading, "expired five-minute cache starts real request");
      phase = "policy-refreshed";
    } else if (phase === "policy-refreshed" && !policyClient.loading && policyUpdates === 2) {
      check(policyClient.convert(2, "GBP", "JPY") === 50, "refreshed real rates conversion");
      console.log("CURRENCY: PASS " + scope + " policy");
      Qt.exit(0);
    } else if (phase === "runtime" && selected.settingsReady && sibling.settingsReady && inherited.settingsReady) {
      presentations = [api, selected, sibling, inherited].map(function (context) {
        return {
          api: context,
          panel: create("panel", context),
          bar: create("barWidget", context),
          launcher: create("launcherProvider", context)
        };
      });
      phase = "initial";
    } else if (phase === "initial") {
      var initial = mode === "edit" ? "initial" : mode === "reset" ? "edited" : mode === "follow" ? "reset" : mode === "retire" ? "following" : boundary;
      if (!runtimeReady(initial))
        return;
      observe(initial);
      if (mode === "cold") {
        console.log("CURRENCY: COLD_PASS " + scope + " " + boundary);
        Qt.exit(0);
      } else if (mode === "edit")
        probe("initial", "open-discard");
      else if (mode === "follow")
        phase = "change-base";
      else if (mode === "retire")
        probe("hold", "start-held");
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
      check(popup._editor === failedEditor && popup.settingsPage === failedPage && popup._pageApi.field("refreshInterval").value === 30, "failed page/editor/input retained");
      // Shared native desired state can advance without publication; it is not rollback.
      if (scope === "instance")
        observe("initial");
      probe("failed", "allow-retry");
    } else if (phase === "allow-retry")
      probe("allow", "retry");
    else if (phase === "retry") {
      check(popup._editor === failedEditor && popup.settingsPage === failedPage, "same-editor Retry");
      apply("applied");
    } else if (phase === "applied" && accepted() && runtimeReady("edited")) {
      console.log("CURRENCY_NATIVE_EDITED");
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
    else if (phase === "reset-applied" && accepted() && runtimeReady("reset")) {
      observe("reset");
      probe("reset", "finish");
    } else if (phase === "change-base") {
      api.pluginSettings.sourceCurrency = "JPY";
      api.pluginSettings.targetCurrency = "GBP";
      api.pluginSettings.widgetDisplayMode = "full";
      api.pluginSettings.refreshInterval = 60;
      phase = "base-saving";
      api.saveSettings(function (result) {
        try {
          check(result.status === "saved", "native base publication");
          phase = "base-changed";
        } catch (error) {
          fail(error);
        }
      });
    } else if (phase === "base-changed" && runtimeReady("following")) {
      observe("following");
      probe("following", "finish");
    } else if (phase === "start-held") {
      var client = presentations[1].panel.main;
      client.lastFetch = 0;
      client.fetchRates(true);
      phase = "held";
    } else if (phase === "held") {
      heldFile.reload();
      heldFile.waitForJob();
      if (!heldFile.loaded)
        return;
      retiredContext = selected.settingsContext;
      Service.loadedPlugins = ({});
      phase = "retiring";
    } else if (phase === "retiring" && !retiredContext.current()) {
      check(api.mainInstance._settingsConsumers.size === 0, "retired contexts removed from Main cache");
      check(presentations.every(item => item.panel.main === null && item.bar.main === null && item.launcher.main === null), "retired views cannot retain clients");
      probe("release", "retired");
    } else if (phase === "retired") {
      console.log("CURRENCY: PASS " + scope + " retire");
      Qt.exit(0);
    } else if (phase === "finish") {
      console.log("CURRENCY: PASS " + scope + " " + mode);
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
