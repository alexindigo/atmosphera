import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins

ShellRoot {
  id: root
  readonly property var screen: Quickshell.screens[0]
  readonly property string mode: Quickshell.env("PHA_CLAUDE_LIFE_MODE")
  readonly property string casePath: Quickshell.env("PHA_CLAUDE_CASE")
  property bool started: false
  property string phase: "startup"
  property double since: Date.now()
  onPhaseChanged: since = Date.now()
  property var api: null
  property var selected: null
  property var sibling: null
  property var main: null
  property var panel: null
  property string permissionId: ""
  property var retainedPermission: null
  property string afterProbe: ""
  property bool nativeSaved: true
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
    id: requests
    path: root.casePath + "/requests.jsonl"
    blockLoading: true
  }
  FileView {
    id: cache
    path: Settings.cacheDir + "plugins/claude-code-panel/state.json"
    blockLoading: true
  }
  FileView {
    id: release
    path: root.casePath + "/release"
  }
  FileView {
    id: barFile
    path: Settings.configDir + "settings/bar.json"
    blockLoading: true
  }
  Process {
    id: probeProcess
    stdout: StdioCollector {
      id: probeOutput
    }
    stderr: StdioCollector {
      id: probeErrors
    }
    onExited: code => {
      try {
        root.check(code === 0, mode === "slash" ? "complete native originating writer documents " + probeErrors.text : "retired process joined before engine exit " + probeErrors.text);
        root.phase = root.afterProbe;
      } catch (error) {
        root.fail(error);
      }
    }
  }
  PanelWindow {
    visible: true
    implicitWidth: 1000
    implicitHeight: 800
    Item {
      id: content
      width: 1000
      height: 800
    }
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("CLAUDE_LIFE_ASSERT: " + mode + "/" + phase + ": " + message);
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
    check(item, "actual " + entry);
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
        check(owner, "native owner");
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
        phase = "ready";
      } catch (error) {
        fail(error);
      }
    });
  }
  function rows() {
    requests.reload();
    requests.waitForJob();
    return requests.text().trim().split("\n").filter(line => line).map(line => JSON.parse(line));
  }
  function replaceSource() {
    var next = Object.assign({}, selected.pluginSettings.claude);
    next.workingDir = casePath + "/replacement";
    selected.pluginSettings.claude = next;
    nativeSaved = false;
    selected.saveSettings(result => {
      root.check(result.status !== "failed", "native source replacement publishes");
      root.nativeSaved = true;
    });
  }
  function probe(next, excluded) {
    afterProbe = next;
    phase = "probe";
    probeProcess.command = ["python3", "-B", Quickshell.env("PHA_CLAUDE_PROBE"), casePath, Quickshell.env("PHA_CLAUDE_OUTPUT"), String(excluded || 0)];
    probeProcess.running = true;
  }
  function stopAndProbe() {
    if (main)
      main.stopAcpProcess();
    phase = "stopped";
  }
  function drive() {
    check(Date.now() - since < 15000, "finite ACP lifetime phase");
    if (phase === "ready" && selected.settingsReady && sibling.settingsReady && main.binaryChecked) {
      panel = create("panel", selected);
      if (mode === "start-failure") {
        phase = "failed-start";
        return;
      }
      if (mode === "cache") {
        main.messages = [
              {
                role: "user",
                text: "first"
              },
              {
                role: "user",
                text: "last"
              }
            ];
        main.saveState(selected.settingsContext);
        selected.pluginSettings.maxHistoryLength = 9;
        selected.saveSettings();
        phase = "cached";
      } else if (mode === "slash") {
        check(main.handleSlashCommand("/cwd " + casePath + "/replacement", selected), "actual slash command");
        phase = "slash-written";
      } else {
        check(main.sendMessage("request-one", selected.settingsContext), "admitted originating prompt");
        phase = "sent";
      }
    } else if (phase === "failed-start") {
      if (main.acpPhase !== "idle" || main.acpProcess || Date.now() - since < 300)
        return;
      check(!main.isGenerating && main.errorMessage !== "", "failed process start settles with visible error");
      stopAndProbe();
    } else if (phase === "cached" && Date.now() - since > 800) {
      cache.reload();
      cache.waitForJob();
      check(JSON.parse(cache.text()).messages.length === 1 && main.messages.length === 2, "debounced history keeps captured originating limit");
      stopAndProbe();
    } else if (phase === "slash-written" && main.acpPhase === "ready" && selected._pendingSettingsSaves === 0) {
      if (!rows().some(row => row.event.method === "session/new" && row.cwd === casePath + "/replacement" && row.event.params.cwd === row.cwd))
        return;
      stopAndProbe();
    } else if (phase === "sent") {
      if (mode === "handshake") {
        if (!rows().some(row => row.cwd === casePath + "/selected" && row.event.method === "initialize"))
          return;
        replaceSource();
        phase = "retiring";
      } else if (mode.startsWith("permission")) {
        permissionId = Object.keys(main._pendingPermissions)[0] || "";
        if (!permissionId)
          return;
        retainedPermission = main._pendingPermissions[permissionId];
        check(retainedPermission.worker === main.acpProcess && retainedPermission.sessionId === main.sessionId && retainedPermission.rpcId === 900, "exact permission process/session/RPC identity");
        if (mode === "permission-retired") {
          replaceSource();
          phase = "retiring-permission";
        } else if (mode === "permission-new-session") {
          main.newSession(sibling.settingsContext);
          phase = "new-permission";
        } else {
          var bubble = find(panel, item => item.entry?.id === permissionId && item.mainInstance === main);
          var button = find(bubble, item => item.numeral === (mode === "permission-allow" ? "1." : "3.") && item.clicked !== undefined);
          if (!button)
            return;
          button.clicked();
          phase = "permission-replied";
        }
      } else if (mode === "queued") {
        if (!main.messages.some(message => message.text === "queued-partial"))
          return;
        check(main.sendMessage("request-two", sibling.settingsContext), "second captured origin queues");
        check(main._pendingPrompts.length === 1 && main._pendingPrompts[0].policy.context === sibling.settingsContext, "queue keeps originating context");
        release.setText("release");
        phase = "queued-replies";
      } else if (["replace", "native-retired", "destroyed", "stop"].indexOf(mode) !== -1) {
        if (!main.messages.some(message => message.text === "partial"))
          return;
        if (mode === "replace")
          replaceSource();
        else if (mode === "native-retired") {
          nativeSaved = false;
          Settings.data.bar.widgets.left = Settings.store.copyValue(Settings.data.bar.widgets.left).slice(1);
          Settings.store.saveSelected([["bar", "widgets", "left"]], result => {
            root.check(result.status !== "failed", "native placement removal publishes");
            root.nativeSaved = true;
          });
        } else if (mode === "destroyed") {
          panel.destroy();
          panel = null;
          main.destroy();
          main = null;
        } else {
          main.stopGeneration();
          main.stopAcpProcess();
        }
        phase = "retiring";
      } else if (!main.isGenerating && main.messages.some(message => message.role === "assistant" && (message.text || "").startsWith("reply:"))) {
        var request = rows().find(row => row.event.method === "session/prompt");
        check(request?.cwd === casePath + "/selected" && request.event.params.prompt[0].text === "<system>\nselected prefix\n</system>\n\nrequest-one", "selected ACP prefix/cwd reaches common conversation");
        check(!main.messages.some(message => (message.text || "").indexOf("FOREIGN") !== -1), "foreign-session notification rejected");
        if (!find(panel, item => typeof item.getText === "function" && item.getText(0, item.length) === "reply:" + casePath + "/selected"))
          return;
        stopAndProbe();
      }
    } else if (phase === "queued-replies" && !main.isGenerating && main.messages.some(message => message.text === "reply:" + casePath + "/sibling")) {
      check(main.messages.some(message => message.text === "queued-partialreply:" + casePath + "/selected"), "common conversation retains first originating turn");
      probe("queued-joined", main.acpProcess.processId);
    } else if (phase === "queued-joined")
      stopAndProbe();
    else if (phase === "permission-replied" && !main.isGenerating && main.messages.some(message => message.text === "permission-settled")) {
      check(!main._pendingPermissions[permissionId], "manual permission settles once");
      stopAndProbe();
    } else if (phase === "new-permission" && main.acpPhase === "ready") {
      // Reinject only a retained test capability to exercise the independent guard.
      var map = Object.assign({}, main._pendingPermissions);
      map[permissionId] = retainedPermission;
      main._pendingPermissions = map;
      check(main.respondToPermission(permissionId, "allow_once") === false, "stale permission refused");
      main._pendingPermissions = ({});
      stopAndProbe();
    } else if (phase === "retiring-permission" && !main.acpProcess && Date.now() - since > 300) {
      check(main.respondToPermission(permissionId, "allow_once") === false, "stale permission refused");
      phase = "retiring";
    } else if (phase === "retiring" && nativeSaved && Date.now() - since > 400) {
      check(!main || (!main.isGenerating && !main.acpProcess), "request generation settled after source/owner/action change");
      probe("finished");
    } else if (phase === "stopped" && Date.now() - since > 300)
      probe("finished");
    else if (phase === "finished") {
      console.log("CLAUDE_LIFETIME: PASS " + mode);
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
    interval: 40
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
