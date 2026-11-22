import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins
import qs.Widgets

ShellRoot {
  id: root
  readonly property var screen: Quickshell.screens[0]
  readonly property string scope: Quickshell.env("PHA_ASSISTANT_SCOPE")
  readonly property string mode: Quickshell.env("PHA_ASSISTANT_MODE")
  readonly property string boundary: Quickshell.env("PHA_ASSISTANT_BOUNDARY")
  readonly property string casePath: Quickshell.env("PHA_ASSISTANT_CASE")
  readonly property bool oldRed: Quickshell.env("PHA_ASSISTANT_RED") === "1"
  property bool started: false
  property string phase: "startup"
  property double since: Date.now()
  onPhaseChanged: since = Date.now()
  property var api: null
  property var selected: null
  property var sibling: null
  property var inherited: null
  property var main: null
  property var bar: null
  property var panel: null
  property var receipt: null
  property string afterDisk: ""
  property string diskBoundary: ""
  property string observedBoundary: ""
  FileView {
    id: manifest
    path: Settings.configDir + "plugins/assistant-panel/manifest.json"
    blockLoading: true
  }
  FileView {
    id: dictionary
    path: Settings.configDir + "plugins/assistant-panel/i18n/en.json"
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
        root.fail("independent complete Assistant documents " + root.diskBoundary);
      else
        root.phase = root.afterDisk;
    }
  }
  PanelWindow {
    visible: true
    implicitWidth: 1100
    implicitHeight: 900
    Item {
      id: content
      width: 1100
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
      throw new Error("ASSISTANT_ASSERT: " + scope + "/" + mode + "/" + phase + ": " + message);
  }
  function fail(error) {
    console.error(String(error) + "\n" + (error.stack || ""));
    Qt.exit(2);
  }
  function find(object, predicate, seen) {
    seen = seen || new Set();
    if (!object || seen.has(object))
      return null;
    seen.add(object);
    if (object && predicate(object))
      return object;
    for (var list of [object?.data, object?.children]) {
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
  function create(entry, context) {
    var component = Qt.createComponent("file://" + api.pluginDir + "/" + api.manifest.entryPoints[entry]);
    check(component.status === Component.Ready, component.errorString());
    var item = PluginLoader.createObject("assistant-panel", entry, component, content, context, {});
    check(item, "actual " + entry + " constructs");
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
      "assistant-panel": descriptor
    };
    Service._openSettingsOwner("assistant-panel", function (owner) {
      try {
        check(owner, "actual native owner");
        api = Service.createPluginAPI("assistant-panel", descriptor, owner, dict, dict, {});
        Service.loadedPlugins = {
          "assistant-panel": {
            api: api
          }
        };
        main = create("main", api);
        api.mainInstance = main;
        selected = PluginInstances.apiFor("assistant-panel", {
                                            kind: "bar",
                                            list: "global",
                                            section: "left",
                                            index: 0
                                          });
        sibling = PluginInstances.apiFor("assistant-panel", {
                                           kind: "bar",
                                           list: "global",
                                           section: "left",
                                           index: 1
                                         });
        inherited = PluginInstances.apiFor("assistant-panel", {
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
  function values(name) {
    expectations.reload();
    expectations.waitForJob();
    var expected = JSON.parse(expectations.text())[name];
    return Object.assign({}, api.manifest.metadata.defaultSettings, expected.shared, scope === "instance" ? expected.bar.widgets.left[0].instanceSettings : {});
  }
  function ready(name) {
    var cfg = values(name), target = scope === "instance" ? selected : api;
    var actual = target.pluginSettings.ai;
    return target.pluginSettings.maxHistoryLength === cfg.maxHistoryLength && actual.provider === cfg.ai.provider && actual.temperature === cfg.ai.temperature && actual.models?.[actual.provider] === cfg.ai.models?.[cfg.ai.provider];
  }
  function probe(name, next) {
    diskBoundary = name;
    afterDisk = next;
    phase = "disk";
    disk.command = ["python3", "-B", Quickshell.env("PHA_ASSISTANT_DISK"), casePath, Quickshell.env("PHA_ASSISTANT_OUTPUT") + "/persisted", name];
    disk.running = true;
  }
  function open(next) {
    check(scope === "shared" ? popup.openPluginSettings(api.manifest, "settings") : popup.openInstanceSettings(api.manifest, selected, "settings"), "actual scoped page opens");
    phase = next;
  }
  function edit() {
    var model = find(popup.settingsPage, item => item.objectName === "assistant-model");
    var temperature = find(popup.settingsPage, item => item.objectName === "settings-range-editTemperature");
    var history = find(popup.settingsPage, item => item.objectName === "settings-range-editMaxHistoryLength");
    check(model && temperature && history, "actual model/zero-temperature/history controls");
    model.text = "selected-model";
    model.editCommitted();
    temperature.value = 0;
    temperature.moved();
    history.value = 20;
    history.moved();
  }
  function apply(next) {
    receipt = null;
    check(popup.applySettings(), "native Apply");
    phase = next;
  }
  function accepted() {
    return receipt && !popup.busy && receipt.status === "saved" && receipt.refreshState === "current";
  }
  function consumers(name) {
    var cfg = values(name), target = scope === "instance" ? selected : api;
    var chat = find(panel, item => item.regenerateLastResponse === undefined && item.provider !== undefined && item.initialInputText !== undefined);
    check(chat, "actual AiChatView");
    var model = cfg.ai.models?.[cfg.ai.provider] || (cfg.ai.provider === "google" ? "gemini-2.5-flash" : "gpt-4o-mini");
    check(chat.model === model, oldRed ? "original model consumes saved selected configuration" : "selected chat model");
    check(find(chat, item => item.text === model), "actual model child Text");
    if (!oldRed) {
      var client = main.settingsConsumerFor(target.settingsContext);
      check(chat.settingsConsumer === client, "actual chat uses exact selected policy client");
      check(main.settingsConsumerFor(target.settingsContext) === client, "same API shares selected policy");
      check(main.settingsConsumerFor(sibling.settingsContext).model === "sibling-model", "overridden sibling policy");
      if (main.settingsConsumerFor(inherited.settingsContext).model !== (name === "following" ? "following-model" : scope === "shared" ? model : "shared-model"))
        return;
      check(bar.mainInstance === main && chat.mainInstance === main, "one common conversation owner");
    }
    if (mode === "cold" || cfg.ai.provider !== "openai_compatible")
      finish(name);
    else {
      observedBoundary = name;
      var input = find(chat, item => item.placeholderText === api.tr("chat.placeholder") && item.insert !== undefined);
      check(input, "actual runtime chat input");
      input.text = "native request";
      chat.sendMessage();
      phase = "reply";
    }
  }
  function finish(name) {
    console.log("ASSISTANT_NATIVE: PASS " + scope + " " + mode + " " + boundary + " " + name);
    Qt.exit(0);
  }
  function drive() {
    check(Date.now() - since < 18000, "finite native Assistant phase");
    if (phase === "runtime" && selected.settingsReady && sibling.settingsReady && inherited.settingsReady) {
      var context = scope === "instance" ? selected : api;
      bar = create("barWidget", context);
      panel = create("panel", context);
      phase = "initial";
    } else if (phase === "initial") {
      var name = mode === "edit" ? "initial" : mode === "reset" ? "edited" : mode === "follow" ? "reset" : boundary;
      if (!ready(name))
        return;
      if (mode === "cold")
        consumers(boundary);
      else if (mode === "edit")
        probe("initial", "open-discard");
      else if (mode === "follow")
        phase = "change-base";
      else
        open("reset-page");
    } else if (phase === "open-discard")
      open("discard-page");
    else if (phase === "discard-page" && popup.opened && popup.settingsPage) {
      check(!popup.dirty, "construction has no intent");
      edit();
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
    } else if (phase === "applied" && accepted() && ready("edited"))
      probe("edited", "edited-consumers");
    else if (phase === "edited-consumers")
      consumers("edited");
    else if (phase === "reply" && !main.isGenerating && main.messages.some(item => item.content === "reply-" + values(observedBoundary).ai.models.openai_compatible)) {
      if (!find(panel, item => typeof item.getText === "function" && item.getText(0, item.length) === "reply-" + values(observedBoundary).ai.models.openai_compatible)) {
        check(Date.now() - since < 3000, "actual assistant response child Text");
        return;
      }
      finish(observedBoundary);
    } else if (phase === "reset-page" && popup.opened && popup.settingsPage && !popup.busy) {
      check(popup._pageApi.resetFields(["ai", "maxHistoryLength"]), "one staged native Reset");
      phase = "reset-staging";
    } else if (phase === "reset-staging" && !popup.busy && ["ai", "maxHistoryLength"].every(key => popup._pageApi.field(key).pendingIntent === "reset"))
      probe("reset-staged", "reset-apply");
    else if (phase === "reset-apply")
      apply("reset-applied");
    else if (phase === "reset-applied" && accepted() && ready("reset"))
      probe("reset", "reset-consumers");
    else if (phase === "reset-consumers")
      consumers("reset");
    else if (phase === "change-base") {
      var cfg = JSON.parse(expectations.text()).following.shared;
      api.pluginSettings.ai = cfg.ai;
      api.pluginSettings.maxHistoryLength = cfg.maxHistoryLength;
      phase = "base-saving";
      api.saveSettings(result => {
        try {
          check(result.status === "saved", "shared native propagation");
          phase = "base-changed";
        } catch (error) {
          fail(error);
        }
      });
    } else if (phase === "base-changed" && ready("following"))
      probe("following", "following-consumers");
    else if (phase === "following-consumers")
      consumers("following");
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
