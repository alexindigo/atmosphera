import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins
import qs.Widgets

ShellRoot {
  id: root
  readonly property var screen: Quickshell.screens[0]
  readonly property string scope: Quickshell.env("PHA_CLAUDE_SCOPE")
  readonly property string mode: Quickshell.env("PHA_CLAUDE_MODE")
  readonly property string boundary: Quickshell.env("PHA_CLAUDE_BOUNDARY")
  readonly property string casePath: Quickshell.env("PHA_CLAUDE_CASE")
  readonly property bool oldRed: Quickshell.env("PHA_CLAUDE_RED") === "1"
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
    path: Settings.configDir + "plugins/claude-code-panel/manifest.json"
    blockLoading: true
  }
  FileView {
    id: dictionary
    path: Settings.configDir + "plugins/claude-code-panel/i18n/en.json"
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
        root.fail("independent complete Claude documents " + root.diskBoundary);
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
      throw new Error("CLAUDE_ASSERT: " + scope + "/" + mode + "/" + phase + ": " + message);
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
    if (predicate(object))
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
    var item = PluginLoader.createObject("claude-code-panel", entry, component, content, context, {});
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
      "claude-code-panel": descriptor
    };
    Service._openSettingsOwner("claude-code-panel", function (owner) {
      try {
        check(owner, "actual native owner");
        api = Service.createPluginAPI("claude-code-panel", descriptor, owner, dict, dict, {});
        Service.loadedPlugins = {
          "claude-code-panel": {
            api: api
          }
        };
        main = create("main", api);
        api.mainInstance = main;
        selected = PluginInstances.apiFor("claude-code-panel", {
                                            kind: "bar",
                                            list: "global",
                                            section: "left",
                                            index: 0
                                          });
        sibling = PluginInstances.apiFor("claude-code-panel", {
                                           kind: "bar",
                                           list: "global",
                                           section: "left",
                                           index: 1
                                         });
        inherited = PluginInstances.apiFor("claude-code-panel", {
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
  function cwd(name) {
    return values(name).claude.workingDir || Quickshell.env("HOME");
  }
  function ready(name) {
    var cfg = values(name), target = scope === "instance" ? selected : api;
    var expected = JSON.parse(expectations.text())[name];
    var base = Object.assign({}, api.manifest.metadata.defaultSettings, expected.shared);
    return target.pluginSettings.panelWidth === cfg.panelWidth && (target.pluginSettings.claude.workingDir || "") === (cfg.claude.workingDir || "") && (inherited.pluginSettings.claude.workingDir || "") === (base.claude.workingDir || "");
  }
  function probe(name, next) {
    diskBoundary = name;
    afterDisk = next;
    phase = "disk";
    disk.command = ["python3", "-B", Quickshell.env("PHA_CLAUDE_DISK"), casePath, Quickshell.env("PHA_CLAUDE_OUTPUT") + "/persisted", name];
    disk.running = true;
  }
  function open(next) {
    check(scope === "shared" ? popup.openPluginSettings(api.manifest, "settings") : popup.openInstanceSettings(api.manifest, selected, "settings"), "actual scoped page opens");
    phase = next;
  }
  function edit() {
    var input = find(popup.settingsPage, item => item.label === api.tr("settings.workingDir") && item.editCommitted !== undefined);
    check(input, "actual working-directory control");
    input.text = casePath + "/selected";
    input.editCommitted();
    var width = find(popup.settingsPage, item => item.objectName === "settings-range-editPanelWidth");
    check(width, "actual width control");
    width.submitValue(700);
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
    check((oldRed ? main.workingDir : panel.settingsConsumer?.workingDir) === (cfg.claude.workingDir || ""), oldRed ? "original Panel consumes saved selected working directory" : "selected Panel working directory");
    var heading = find(panel, item => typeof item.text === "string" && (cfg.claude.workingDir ? item.text.indexOf(cwd(name)) !== -1 : item.text.indexOf(api.tr("panel.noSession")) !== -1 || item.text.indexOf("inert-") !== -1));
    check(heading && (cfg.claude.workingDir || heading.text.indexOf("Working dir:") === -1), "actual cwd child Text");
    check(panel.contentPreferredWidth === cfg.panelWidth, "selected actual Panel width");
    if (!oldRed) {
      var client = main.settingsConsumerFor(target.settingsContext);
      check(panel.settingsConsumer === client && bar.settingsConsumer === client, "same-context exact policy client");
      check(main.settingsConsumerFor(sibling.settingsContext).workingDir === casePath + "/sibling", "overridden sibling policy");
      check(main.settingsConsumerFor(inherited.settingsContext).workingDir === (JSON.parse(expectations.text())[name].shared.claude?.workingDir || ""), "inherited policy");
      check(bar.mainInstance === main && panel.mainInstance === main, "common conversation owner");
    }
    observedBoundary = name;
    if (mode === "cold")
      finish(name);
    else {
      var input = find(panel, item => item.placeholderText === api.tr("panel.inputPlaceholder") && item.insert !== undefined);
      check(input, "actual runtime input");
      input.text = "native request";
      panel.submit();
      phase = "reply";
    }
  }
  function finish(name) {
    console.log("CLAUDE_NATIVE: PASS " + scope + " " + mode + " " + boundary + " " + name);
    Qt.exit(0);
  }
  function drive() {
    check(Date.now() - since < 18000, "finite native Claude phase");
    if (phase === "runtime" && selected.settingsReady && sibling.settingsReady && inherited.settingsReady && main.binaryChecked) {
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
    else if (phase === "reply" && !main.isGenerating && main.messages.some(item => item.text === "reply:" + cwd(observedBoundary))) {
      if (!find(panel, item => typeof item.getText === "function" && item.getText(0, item.length) === "reply:" + cwd(observedBoundary))) {
        check(Date.now() - since < 3000, "actual reply child Text");
        return;
      }
      finish(observedBoundary);
    } else if (phase === "reset-page" && popup.opened && popup.settingsPage && !popup.busy) {
      check(popup._pageApi.resetFields(["claude", "panelWidth"]), "one staged native Reset");
      phase = "reset-staging";
    } else if (phase === "reset-staging" && !popup.busy && ["claude", "panelWidth"].every(key => popup._pageApi.field(key).pendingIntent === "reset"))
      probe("reset-staged", "reset-apply");
    else if (phase === "reset-apply")
      apply("reset-applied");
    else if (phase === "reset-applied" && accepted() && ready("reset"))
      probe("reset", "reset-consumers");
    else if (phase === "reset-consumers")
      consumers("reset");
    else if (phase === "change-base") {
      var cfg = JSON.parse(expectations.text()).following.shared;
      api.pluginSettings.claude = cfg.claude;
      api.pluginSettings.panelWidth = cfg.panelWidth;
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
