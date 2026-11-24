import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins
import qs.Widgets

ShellRoot {
  id: root
  readonly property string base: Quickshell.env("PHA_HERMES_CASE")
  readonly property string scope: Quickshell.env("PHA_HERMES_SCOPE")
  readonly property string mode: Quickshell.env("PHA_HERMES_MODE")
  readonly property string boundary: Quickshell.env("PHA_HERMES_BOUNDARY")
  property var api: null
  property var contexts: []
  readonly property var target: scope === "shared" ? api : contexts[0]
  property var main: null
  property var panel: null
  property var bar: null
  property var receipt: null
  property bool detectionSaved: false
  property var connectionBefore: null
  property string phase: "begin"
  property string next: ""
  property string effectBoundary: ""
  property double since: Date.now()
  onPhaseChanged: since = Date.now()
  FileView {
    id: manifest
    path: Settings.configDir + "plugins/hermes-agent/manifest.json"
    blockLoading: true
  }
  FileView {
    id: dictionary
    path: Settings.configDir + "plugins/hermes-agent/i18n/en.json"
    blockLoading: true
  }
  FileView {
    id: expectations
    path: root.base + "/expectations.json"
    blockLoading: true
  }
  FileView {
    id: requestLog
    path: root.base + "/requests.jsonl"
    printErrors: false
  }
  FileView {
    id: release
    path: root.base + "/release"
    printErrors: false
  }
  Process {
    id: disk
    onExited: code => {
      if (code)
        root.fail("complete Hermes native documents");
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
      anchors.fill: parent
    }
    NPluginSettingsPopup {
      id: popup
      screen: Quickshell.screens[0]
      onSettingsCompleted: result => root.receipt = result
    }
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("HERMES_NATIVE_ASSERT: " + scope + "/" + mode + "/" + phase + ": " + message);
  }
  function fail(message) {
    driver.stop();
    console.error(String(message));
    Qt.exit(2);
  }
  function find(item, predicate, seen) {
    if (!item)
      return null;
    seen = seen || new Set();
    if (seen.has(item))
      return null;
    seen.add(item);
    if (predicate(item))
      return item;
    if (item.item) {
      const found = find(item.item, predicate, seen);
      if (found)
        return found;
    }
    for (const group of [item.data, item.children, item.contentData])
      if (group && typeof group.length === "number")
        for (let i = 0; i < group.length; i++) {
          const found = find(group[i], predicate, seen);
          if (found)
            return found;
        }
    return item.contentItem ? find(item.contentItem, predicate, seen) : null;
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
    return [api].concat(contexts).every((value, i) => value.pluginSettings.defaultModel === expected[i].defaultModel);
  }
  function begin() {
    phase = "loading";
    manifest.waitForJob();
    dictionary.waitForJob();
    const descriptor = JSON.parse(manifest.text()), translations = JSON.parse(dictionary.text());
    Registry.installedPlugins = {
      "hermes-agent": descriptor
    };
    Service._openSettingsOwner("hermes-agent", owner => {
      try {
        check(owner, "native owner");
        api = Service.createPluginAPI("hermes-agent", descriptor, owner, translations, translations, {});
        Service.loadedPlugins = {
          "hermes-agent": {
            api: api
          }
        };
        if (mode === "detect")
          Service.pluginSettingsCompleted.connect(function (id, result) {
            if (id === "hermes-agent" && result.status === "saved" && result.publicationState === "known")
              root.detectionSaved = true;
          });
        const component = Qt.createComponent("file://" + api.pluginDir + "/Main.qml");
        check(component.status === Component.Ready, component.errorString());
        main = PluginLoader.createObject("hermes-agent", "main", component, content, api, {});
        check(main, "actual Main");
        api.mainInstance = main;
        contexts = [0, 1, 2].map(i => PluginInstances.apiFor("hermes-agent", {
                                                               kind: "bar",
                                                               list: "global",
                                                               section: "left",
                                                               index: i
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
    disk.command = ["python3", "-B", Quickshell.env("PHA_HERMES_DISK"), base, Quickshell.env("PHA_HERMES_OUTPUT") + "/persisted", name];
    disk.running = true;
  }
  function open(after) {
    check(scope === "shared" ? popup.openPluginSettings(api.manifest, "settings") : popup.openInstanceSettings(api.manifest, target, "settings"), "actual scoped page");
    phase = after;
  }
  function edit() {
    popup.settingsPage.showAdvanced = true;
    const control = find(popup.settingsPage, item => item.label === "Default model" && item.editCommitted);
    check(control, "actual model input");
    control.text = "selected-model";
    control.editCommitted();
    check(popup._pageApi.field("defaultModel").value === "selected-model", "actual input intent");
    check(popup.settingsPage.valueDefaultModel === "selected-model", "runtime detected model cannot mask selected field");
    for (const key of Object.keys(api.manifest.metadata.settingsSchema.fields))
      if (key !== "defaultModel" && key !== "configured")
        check(!popup._pageApi.field(key).pendingIntent, "untouched " + key);
  }
  function apply(after) {
    receipt = null;
    check(popup.applySettings(), "native Apply");
    phase = after;
  }
  function accepted() {
    return receipt && !popup.busy && ["saved", "nothing_to_save"].includes(receipt.status) && receipt.refreshState === "current";
  }
  function action(name) {
    effectBoundary = name;
    target.panelOpenScreen = Quickshell.screens[0];
    for (const entry of ["Panel", "BarWidget"]) {
      const component = Qt.createComponent("file://" + api.pluginDir + "/" + entry + ".qml");
      check(component.status === Component.Ready, component.errorString());
      const item = PluginLoader.createObject("hermes-agent", entry === "Panel" ? "panel" : "barWidget", component, content, target, entry === "Panel" ? {} : {
                                               screen: Quickshell.screens[0]
                                             });
      check(item, "actual " + entry);
      if (entry === "Panel")
        panel = item;
      else
        bar = item;
    }
    phase = "consumer-ready";
  }
  function drive() {
    check(Date.now() - since < 18000, "finite phase");
    if (phase === "begin" && Settings.isLoaded)
      begin();
    else if (phase === "runtime" && contexts.every(value => value.settingsReady) && main.connection?.ready)
      phase = mode.startsWith("detect") ? "detection" : mode === "probe" ? "open-probe" : mode === "pending" ? "pending-initial" : "initial";
    else if (phase === "pending-initial" && main.state.session?.id === "chat-shared") {
      connectionBefore = main.connection;
      probe("initial", "open-pending");
    } else if (phase === "open-pending")
      open("pending-page");
    else if (phase === "pending-page" && popup.opened && popup.settingsPage) {
      popup.settingsPage.showAdvanced = true;
      const control = find(popup.settingsPage, item => item.objectName === "settings-range-valueBridgePort");
      check(control, "actual pending connection input");
      control.submitValue(Number(Quickshell.env("PHA_HERMES_PROBE_PORT")));
      apply("pending-applied");
    } else if (phase === "pending-applied" && accepted())
      probe("edited", "pending-policy");
    else if (phase === "pending-policy" && Date.now() - since > 200) {
      check(main.pendingRestart && main.connection === connectionBefore && main.state.messages[0].text === "retained-shared", "native Apply preserves active chat/source");
      check(find(popup.settingsPage, item => item.text === popup.settingsPage.pluginApi.tr("settings.pendingRestart") && item.visible), "actual pending restart Text");
      check(main.createSession(target.settingsContext), "explicit native origin session replacement");
      phase = "pending-replaced";
    } else if (phase === "pending-replaced" && !main.pendingBoundary && main.state.session?.id === "chat-selected") {
      check(!main.pendingRestart && main.bridgePort === Number(Quickshell.env("PHA_HERMES_PROBE_PORT")), "native-origin replacement source adopted");
      probe("session-replaced", "finish");
    } else if (phase === "open-probe") {
      connectionBefore = main.connection;
      open("probe-page");
    } else if (phase === "probe-page" && popup.opened && popup.settingsPage) {
      popup.settingsPage.showAdvanced = true;
      const control = find(popup.settingsPage, item => item.objectName === "settings-range-valueBridgePort");
      check(control, "actual draft port control");
      control.submitValue(Number(Quickshell.env("PHA_HERMES_PROBE_PORT")));
      popup.settingsPage.testConnection();
      phase = "probe-held";
    } else if (phase === "probe-held") {
      requestLog.reload();
      requestLog.waitForJob();
      if (!requestLog.text().includes('"peer": "selected"'))
        return;
      const control = find(popup.settingsPage, item => item.objectName === "settings-range-valueBridgePort");
      control.submitValue(api.pluginSettings.bridgePort);
      phase = "probe-replaced";
    } else if (phase === "probe-replaced" && Date.now() - since > 100) {
      release.setText("release");
      phase = "probe-released";
    } else if (phase === "probe-released" && Date.now() - since > 300) {
      check(popup.settingsPage.testResult === "", "obsolete draft probe result fenced");
      check(main.connection === connectionBefore && !main.pendingRestart, "draft probe never selects live owner");
      const control = find(popup.settingsPage, item => item.objectName === "settings-range-valueBridgePort");
      control.submitValue(Number(Quickshell.env("PHA_HERMES_PROBE_PORT")));
      popup.settingsPage.testConnection();
      phase = "probe-success";
    } else if (phase === "probe-success" && popup.settingsPage.testResult === popup.settingsPage.pluginApi.tr("settings.testSuccess")) {
      check(!popup.requestClose(), "probe draft dirty Close refused");
      popup.confirmDiscard();
      phase = "probe-discarded";
    } else if (phase === "probe-discarded" && !popup.opened && !popup._editor)
      probe("detected", "finish");
    else if (phase === "detection" && mode === "detect" && detectionSaved && api.pluginSettings.configured)
      probe("detected", "finish");
    else if (phase === "detection" && mode === "detect-retire") {
      requestLog.reload();
      requestLog.waitForJob();
      if (!requestLog.text().includes('"path": "/detect"'))
        return;
      main.destroy();
      main = null;
      release.setText("release");
      phase = "detection-retired";
    } else if (phase === "detection-retired" && Date.now() - since > 500)
      probe("detected", "finish");
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
      check(popup._pageApi.field("defaultModel").reset(), "staged Reset");
      probe("reset-staged", "reset-apply");
    } else if (phase === "reset-apply")
      apply("reset-applied");
    else if (phase === "reset-applied" && accepted() && ready("reset"))
      probe("reset", "reset-effect");
    else if (phase === "reset-effect")
      action("reset");
    else if (phase === "change-base") {
      phase = "base-saving";
      api.pluginSettings.defaultModel = "following-model";
      api.saveSettings(result => {
        try {
          check(result.status === "saved", "native shared propagation");
          phase = "base-changed";
        } catch (error) {
          fail(error);
        }
      });
    } else if (phase === "base-changed" && ready("following"))
      probe("following", "following-effect");
    else if (phase === "following-effect")
      action("following");
    else if (phase === "consumer-ready" && main.connection?.ready) {
      // Editing/resetting must reach the model through the page's own accepted
      // completion. Only separate cold readers and a runtime base change admit
      // their already-persisted context explicitly here.
      if (mode === "cold" || mode === "follow")
        check(main.applySettings(target.settingsContext), "applied runtime origin");
      phase = "consumer";
    } else if (phase === "consumer") {
      const model = values(effectBoundary)[scope === "shared" ? 0 : 1].defaultModel;
      if (main.state.hermes?.model !== model || !find(panel, item => item.text === "fixture / " + model))
        return;
      check(panel.settingsConsumer === bar.settingsConsumer && bar.settingsConsumer === main.settingsConsumerFor(target.settingsContext), "selected client identity");
      console.log("HERMES_NATIVE_CONSUMER " + JSON.stringify({
                                                               model: model,
                                                               rendered: true,
                                                               selectedClientIdentity: true
                                                             }));
      if (popup.opened)
        popup.requestClose();
      if (mode === "edit") {
        panel.setPinned(true);
        phase = "pinning";
      } else {
        main.destroy();
        main = null;
        phase = "quiescent";
      }
    } else if (phase === "pinning" && main.pinnedPanelApi === target && main.pinnedPanelRequested) {
      check(main.pinnedPanelApi.settingsContext === target.settingsContext, "actual pinned panel native owner");
      probe("runtime-pinned", "unpin");
    } else if (phase === "unpin") {
      panel.setPinned(false);
      phase = "unpinning";
    } else if (phase === "unpinning" && !main.pinnedPanelVisible && !target.pluginSettings.panelPinned)
      probe("runtime-unpinned", "finish");
    else if (phase === "finish") {
      main?.destroy();
      main = null;
      phase = "quiescent";
    } else if (phase === "quiescent" && Date.now() - since > 400) {
      driver.stop();
      console.log("HERMES_NATIVE: PASS " + scope + " " + mode + " " + boundary);
      Qt.exit(0);
    }
  }
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
}
