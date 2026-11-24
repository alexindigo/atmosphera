import QtQuick
import Quickshell
import Quickshell.Io
import "../../../Services/Plugins/PluginSettingsRead.js" as Read
import qs.Commons
import qs.Services.Plugins

ShellRoot {
  id: root
  readonly property string casePath: Quickshell.env("PHA_ASSISTANT_CASE")
  readonly property string mode: Quickshell.env("PHA_ASSISTANT_LIFE_MODE")
  property string phase: "startup"
  property double since: Date.now()
  onPhaseChanged: since = Date.now()
  property bool started: false
  property bool alive: true
  property var cfg: ({})
  property var api: null
  property var selected: null
  property var main: null
  property var context: null
  property bool nativeSaved: false
  property int step: 0
  FileView {
    id: manifest
    path: Settings.configDir + "plugins/assistant-panel/manifest.json"
    blockLoading: true
  }
  FileView {
    id: requests
    path: root.casePath + "/requests.jsonl"
    blockLoading: true
  }
  FileView {
    id: cache
    path: root.casePath + "/cache/plugins/assistant-panel/state.json"
    blockLoading: true
  }
  Process {
    id: join
    onExited: code => {
      if (code !== 0)
        root.fail("request identity still alive before engine exit");
      else
        root.finish();
    }
  }
  Item {
    id: content
  }
  function check(ok, label) {
    if (!ok)
      throw new Error("ASSISTANT_LIFE_ASSERT: " + mode + "/" + phase + ": " + label);
  }
  function fail(error) {
    console.error(String(error) + "\n" + (error.stack || ""));
    Qt.exit(2);
  }
  function finish() {
    console.log("ASSISTANT_LIFETIME: PASS " + mode);
    Qt.exit(0);
  }
  function joinChildren() {
    phase = "join";
    join.command = ["python3", "-c", "import json,sys;from pathlib import Path;p=Path(sys.argv[1]);rows=[json.loads(x) for x in p.read_text().splitlines()] if p.exists() else [];assert all(not (s:=Path('/proc')/str(r['pid'])/'stat').exists() or s.read_text().split(') ',1)[1].split()[19]!=r['start'] for r in rows)", casePath + "/requests.jsonl"];
    join.running = true;
  }
  function records() {
    requests.reload();
    requests.waitForJob();
    return requests.text().trim().split('\n').filter(line => line.trim()).map(line => JSON.parse(line));
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    manifest.waitForJob();
    var descriptor = JSON.parse(manifest.text());
    Registry.installedPlugins = {
      "assistant-panel": descriptor
    };
    Service._openSettingsOwner("assistant-panel", function (owner) {
      try {
        check(owner, "actual native owner");
        api = Service.createPluginAPI("assistant-panel", descriptor, owner, {}, {}, {});
        Service.loadedPlugins = {
          "assistant-panel": {
            api: api
          }
        };
        var component = Qt.createComponent("file://" + api.pluginDir + "/Main.qml");
        check(component.status === Component.Ready, component.errorString());
        main = PluginLoader.createObject("assistant-panel", "main", component, content, api, {});
        api.mainInstance = main;
        selected = PluginInstances.apiFor("assistant-panel", {
                                            kind: "bar",
                                            list: "global",
                                            section: "left",
                                            index: 0
                                          });
        phase = "runtime";
      } catch (error) {
        fail(error);
      }
    });
  }
  function drive() {
    check(Date.now() - since < 16000, "finite Assistant lifetime phase");
    if (phase === "runtime" && selected.settingsReady) {
      cfg = Object.assign({}, selected.pluginSettings);
      context = mode === "native-retired" ? selected.settingsContext : Read.context({
                                                                                      alive: true
                                                                                    }, function () {
                                                                                      return root.cfg;
                                                                                    }, function () {
                                                                                      return root.cfg;
                                                                                    }, function () {
                                                                                      return root.alive;
                                                                                    });
      var client = main.settingsConsumerFor(context);
      check(client === main.settingsConsumerFor(context), "one policy client per captured API");
      if (mode === "cache") {
        main.addMessage("user", "old", client.maxHistoryLength);
        main.addMessage("assistant", "middle", client.maxHistoryLength);
        main.addMessage("user", "last", client.maxHistoryLength);
        cfg = Object.assign({}, cfg, {
                              maxHistoryLength: 99
                            });
        main.activeTab = "translate";
        main.chatInputText = "new draft";
        main.chatInputCursorPosition = 3;
        check(main.saveState(api.settingsContext), "sibling UI save admission");
        phase = "cache";
      } else if (mode.startsWith("translation")) {
        check(main.translate("synthetic", "de", "fr", context), "selected translation admission");
        phase = "translation";
      } else {
        if (mode.startsWith("http-"))
          main.chatInputText = "keep draft";
        check(main.sendMessage("synthetic", context), "selected chat admission");
        check(!main.sendMessage("must refuse", api.settingsContext), "one common chat admission");
        phase = "chat";
      }
    } else if (phase === "cache" && Date.now() - since > 700) {
      cache.reload();
      cache.waitForJob();
      var saved = JSON.parse(cache.text());
      check(saved.messages.length === 1 && saved.messages[0].content === "last" && main.messages.length === 3, "debounced cache retains captured limit, common content not truncated");
      check(saved.activeTab === "translate" && saved.chatInputText === "new draft" && saved.chatInputCursorPosition === 3, "UI save persists without owning history policy");
      joinChildren();
    } else if (phase === "chat" && mode.startsWith("http-") && !main.isGenerating) {
      check(main.errorMessage !== "" && main.messages.length === 1 && main.chatInputText === "keep draft", "HTTP rejection does not settle as successful chat");
      if (mode === "http-provider-error")
        check(main.errorMessage === "synthetic rejection", "HTTP error body retained");
      joinChildren();
    } else if (phase === "chat" && mode === "start-failure" && !main.isGenerating) {
      check(main.errorMessage !== "" && main.messages.length === 1, "failed start settles without invented assistant response");
      joinChildren();
    } else if (phase === "chat" && (mode === "chat" || mode === "chat-http" || mode === "gemini" || mode === "environment" || mode === "edit") && !main.isGenerating && main.messages.length >= 2) {
      check(main.messages[main.messages.length - 1].content === (mode === "gemini" || mode === "environment" ? "gemini-reply" : "reply-selected-model"), "captured provider stream reaches common conversation");
      if (mode !== "edit" || step === 2)
        joinChildren();
      else if (step === 0) {
        ++step;
        check(main.editMessage(main.messages[0].id, "edited", context), "originating edit dispatch");
      } else {
        ++step;
        check(main.regenerateLastResponse(context), "originating regenerate dispatch");
      }
    } else if (phase === "chat" && records().length && main.currentResponse === "partial") {
      if (mode === "stop") {
        main.stopGeneration();
        check(main.messages.length === 2 && main.messages[1].content === "partial", "manual stop preserves originating partial content");
        phase = "cancelled";
      } else if (mode === "clear") {
        check(main.clearMessages(context), "common clear admitted");
        check(main.messages.length === 0, "clear removes common content");
        phase = "cancelled";
      } else if (mode === "destroyed") {
        main.destroy();
        main = null;
        phase = "cancelled";
      } else if (mode === "native-retired") {
        Settings.data.bar.widgets.left = Settings.store.copyValue(Settings.data.bar.widgets.left).slice(1);
        Settings.store.saveSelected([["bar", "widgets", "left"]], function (result) {
          root.nativeSaved = result.status !== "failed";
        });
        phase = "native-retired";
      } else {
        if (mode === "retired")
          alive = false;
        else
          cfg = Object.assign({}, cfg, {
                                ai: Object.assign({}, cfg.ai, {
                                                    models: {
                                                      openai_compatible: "replacement-model"
                                                    }
                                                  })
                              });
        phase = "cancelled";
      }
    } else if (phase === "native-retired" && nativeSaved && !context.current() && !main.isGenerating) {
      check(main.messages.length === 1 && main.currentResponse === "", "native removal cancels stream before sibling retargeting");
      phase = "cancelled";
    } else if (phase === "cancelled" && Date.now() - since > 250) {
      if (main) {
        check(!main.isGenerating && main._chatRequest === null, "request generation settled after source/owner/action change");
        if (mode === "retired")
          check(main.settingsConsumerFor(context) === null && !main.sendMessage("late", context), "retired context cannot dispatch again");
      }
      joinChildren();
    } else if (phase === "translation" && mode === "translation-replace" && records().length) {
      cfg = Object.assign({}, cfg, {
                            translator: Object.assign({}, cfg.translator, {
                                                        backend: "google"
                                                      })
                          });
      phase = "translation-cancelled";
    } else if (phase === "translation-cancelled" && Date.now() - since > 250) {
      check(!main.isTranslating && main._translationRequest === null && main.translatedText === "", "replacement fences translation parser/result generation");
      joinChildren();
    } else if (phase === "translation" && !main.isTranslating) {
      if (mode === "translation-http")
        check(main.translatedText === "" && main.translationError === api.tr("errors.translationFailed"), "HTTP rejection settles as translation transport failure");
      else
        check(main.translatedText === (mode === "translation-google" ? "google-reply" : "deepl-reply") && main.translationError === "", "captured selected translation backend/parser");
      joinChildren();
    }
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
