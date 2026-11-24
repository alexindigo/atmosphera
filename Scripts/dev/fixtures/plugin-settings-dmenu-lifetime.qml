// File completion and screen detection are gated inert collaborators.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins
import qs.Services.UI

ShellRoot {
  id: root
  readonly property string caseDir: Quickshell.env("PHA_DMENU_CASE")
  property bool started: false
  property string phase: "startup"
  property double phaseStarted: Date.now()
  onPhaseChanged: phaseStarted = Date.now()
  property var api: null
  property var main: null
  property var panel: null
  property var screens: []
  property var heldFile: null
  property int opens: 0
  property int closes: 0
  property int toggles: 0
  property int notices: 0
  property int savedOpens: 0
  property int savedCloses: 0
  property int savedSid: 0
  property string actorNext: ""
  property var receipt: null
  FileView {
    id: manifestFile
    path: Settings.configDir + "plugins/dmenu/manifest.json"
    blockLoading: true
  }
  FileView {
    id: dictionaryFile
    path: Settings.configDir + "plugins/dmenu/i18n/en.json"
    blockLoading: true
  }
  FileView {
    id: resultFile
    path: root.caseDir + "/results/file"
    printErrors: false
  }
  Process {
    id: actor
    onExited: code => {
      if (code !== 0)
        root.fail("actual IPC exit " + code);
      else
        root.phase = root.actorNext;
    }
  }
  Connections {
    target: ToastService
    function onNotify(title, description, icon, type, duration, actionLabel, actionCallback) {
      root.notices++;
    }
  }
  PanelWindow {
    visible: true
    implicitWidth: 700
    implicitHeight: 800
    Item {
      id: content
      anchors.fill: parent
    }
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("DMENU_ASSERT: lifetime/" + phase + ": " + message);
  }
  function fail(error) {
    console.error(String(error) + "\n" + (error.stack || ""));
    Qt.exit(2);
  }
  function create(entry) {
    var component = Qt.createComponent("file://" + api.pluginDir + "/" + api.manifest.entryPoints[entry]);
    check(component.status === Component.Ready, component.errorString());
    var item = PluginLoader.createObject("dmenu", entry, component, content, api, {});
    check(item !== null, "actual " + entry + " constructs");
    return item;
  }
  function ipc(method, args, next) {
    check(!actor.running, "one IPC actor");
    actorNext = next;
    actor.command = ["qs", "ipc", "-p", Quickshell.shellDir + "/plugin-settings-dmenu-lifetime.qml", "call", "plugin:dmenu", method].concat(args);
    phase = "ipc";
    actor.running = true;
  }
  function menu(label, next) {
    ipc("showItems", [label + "|Second", JSON.stringify({
                                                          separator: "|",
                                                          resultFile: caseDir + "/results/" + label
                                                        })], next);
  }
  function releaseScreens() {
    var old = screens;
    screens = [];
    for (var callback of old)
      callback(Quickshell.screens[0]);
  }
  function releaseFile(row) {
    main.finishFileRequest(row.loader);
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    manifestFile.waitForJob();
    dictionaryFile.waitForJob();
    var manifest = JSON.parse(manifestFile.text()), dictionary = JSON.parse(dictionaryFile.text());
    Registry.installedPlugins = {
      dmenu: manifest
    };
    Service._openSettingsOwner("dmenu", function (owner) {
      try {
        api = Service.createPluginAPI("dmenu", manifest, owner, dictionary, dictionary, {});
        Service.loadedPlugins = {
          dmenu: {
            api: api
          }
        };
        api.state.dmenuFileContinuations = [];
        api.withCurrentScreen = callback => {
          root.screens = root.screens.concat([callback]);
        };
        api.openPanel = screen => {
          root.opens++;
          api.panelOpenScreen = screen;
        };
        api.closePanel = screen => {
          root.closes++;
          api.panelOpenScreen = null;
        };
        api.togglePanel = screen => {
          root.toggles++;
          api.panelOpenScreen = api.panelOpenScreen ? null : screen;
        };
        main = create("main");
        api.mainInstance = main;
        panel = create("panel");
        phase = "toggle-first";
      } catch (error) {
        fail(error);
      }
    });
  }
  function drive() {
    if (!started || phase === "startup")
      return;
    check(Date.now() - phaseStarted < 18000, "finite operation deadline");
    if (phase === "toggle-first") {
      ipc("toggle", [], "toggle-pending");
    } else if (phase === "toggle-pending" && screens.length === 1) {
      releaseScreens();
      check(toggles === 1 && api.panelOpenScreen !== null, "actual plugin-level toggle reaches captured panel collaborator");
      api.panelOpenScreen = null;
      ipc("toggle", [], "toggle-old");
    } else if (phase === "toggle-old" && screens.length === 1) {
      menu("BeforeFile", "toggle-replaced");
    } else if (phase === "toggle-replaced" && screens.length === 2) {
      var oldToggle = screens[0];
      screens = screens.slice(1);
      oldToggle(Quickshell.screens[0]);
      check(toggles === 1, "superseded toggle cannot retarget a new menu");
      releaseScreens();
      ipc("clear", [], "toggle-cleared");
    } else if (phase === "toggle-cleared") {
      releaseScreens();
      main.lastCloseTimestamp = 0;
      phase = "file-request";
    } else if (phase === "file-request") {
      ipc("showFromFile", [caseDir + "/menu.json", JSON.stringify({
                                                                    maxResults: 2,
                                                                    resultFormat: "plain",
                                                                    closeOnSelect: false,
                                                                    showToastOnSelect: false,
                                                                    resultFile: caseDir + "/results/file",
                                                                    callbackCmd: "printf '%s' '{}' > '" + caseDir + "/results/file-callback'"
                                                                  })], "file-loaded");
    } else if (phase === "file-loaded" && api.state.dmenuFileContinuations.length === 1) {
      heldFile = api.state.dmenuFileContinuations.shift();
      check(!main.state.active && main.pendingFileLoader !== null, "actual file loaded but completion held");
      check(heldFile.request === main.pendingFileLoader.request, "held record retains loader request identity");
      check(main.requestCurrent(main.pendingFileLoader.request), "loader retains admitted API/generation before save");
      api.pluginSettings.customInputPrefix = "later:";
      api.pluginSettings.showToastOnSelect = true;
      phase = "saving";
      api.saveSettings(result => {
        root.receipt = result;
        root.phase = "file-release";
      });
    } else if (phase === "file-release") {
      check(receipt.status === "saved", "later native defaults saved");
      check(main.pendingFileLoader === heldFile.loader, "held loader is current");
      check(main.requestCurrent(heldFile.request), "held file request remains current after native save");
      releaseFile(heldFile);
      check(main.state.active && main.state.maxResults === 2 && main.state.resultFile === caseDir + "/results/file" && main.state.resultFormat === "plain", "explicit request options outrank file config");
      check(main.state.customInputPrefix === "captured:" && main.state.prompt === "File prompt" && main.pendingFileLoader === null, "file completion keeps captured defaults and file prompt");
      check(panel.filteredItems.length === 2, "actual file rows obey captured request limit");
      releaseScreens();
      savedCloses = closes;
      panel.filterText = "typed";
      panel.activateItem(0);
      check(closes === savedCloses && screens.length === 0, "closeOnSelect false cannot be overridden by Panel");
      check(notices === 0, "file request toast false keeps authority");
      phase = "result";
    } else if (phase === "result") {
      resultFile.reload();
      phase = "read-result";
    } else if (phase === "read-result" && !resultFile.loaded) {
      phase = "result";
    } else if (phase === "read-result") {
      check(resultFile.text() === "captured:typed", "file selection keeps admitted policy");
      ipc("showFromFile", [caseDir + "/array.json", JSON.stringify({
                                                                     resultFormat: "index",
                                                                     showToastOnSelect: false,
                                                                     resultFile: caseDir + "/results/index",
                                                                     callbackCmd: "printf '%s' '{name}' > '" + caseDir + "/results/index-callback'"
                                                                   })], "array-loaded");
    } else if (phase === "array-loaded" && api.state.dmenuFileContinuations.length === 1) {
      releaseFile(api.state.dmenuFileContinuations.shift());
      check(panel.filteredItems.length === 2 && panel.filteredItems[1].name === "Two", "actual JSON-array file rows");
      panel.activateItem(1);
      releaseScreens();
      ipc("showFromFile", [caseDir + "/items.txt", JSON.stringify({
                                                                    separator: "::",
                                                                    showToastOnSelect: false,
                                                                    resultFile: caseDir + "/results/text"
                                                                  })], "text-loaded");
    } else if (phase === "text-loaded" && api.state.dmenuFileContinuations.length === 1) {
      releaseFile(api.state.dmenuFileContinuations.shift());
      check(panel.filteredItems.length === 2 && panel.filteredItems[1].name === "Text B", "actual delimited file rows");
      panel.filterText = "unmatched";
      check(panel.filteredItems.length === 0, "custom input remains opt-in");
      panel.filterText = "";
      panel.activateItem(1);
      releaseScreens();
      ipc("showJson", [JSON.stringify({
                                        items: [
                                          {
                                            name: "Named",
                                            value: "original",
                                            altActions: {
                                              shift: {
                                                callback: "printf '%s' '{value}' > '" + caseDir + "/results/alt-callback'",
                                                value: "alternate"
                                              }
                                            }
                                          }
                                        ],
                                        resultFormat: "json",
                                        showToastOnSelect: false,
                                        resultFile: caseDir + "/results/alt"
                                      })], "json-admitted");
    } else if (phase === "json-admitted") {
      check(panel.filteredItems[0].name === "Named", "actual structured IPC row");
      savedSid = main.state.sessionId;
      main.handleSelection(panel.filteredItems[0].value, panel.filteredItems[0].originalIndex, "shift");
      releaseScreens();
      check(notices === 0, "all explicit false toast options retain authority");
      ipc("clear", [], "screen-first");
    } else if (phase === "screen-first") {
      releaseScreens();
      main.lastCloseTimestamp = 0;
      savedOpens = opens;
      menu("Old", "screen-old");
    } else if (phase === "screen-old" && screens.length === 1) {
      menu("New", "screen-new");
    } else if (phase === "screen-new" && screens.length === 2) {
      var old = screens[0], latest = screens[1];
      screens = [];
      old(Quickshell.screens[0]);
      check(opens === savedOpens, "superseded screen callback cannot open replacement");
      latest(Quickshell.screens[0]);
      check(opens === savedOpens + 1 && panel.filteredItems[0].name === "New", "latest admitted screen opens its actual Panel rows");
      savedCloses = closes;
      ipc("close", [], "held-close");
    } else if (phase === "held-close" && screens.length === 1) {
      main.lastCloseTimestamp = 0;
      menu("AfterClose", "replace-close");
    } else if (phase === "replace-close") {
      releaseScreens();
      check(closes === savedCloses && main.state.active, "late close cannot close newer session");
      api.panelOpenScreen = null;
      main.lastCloseTimestamp = Date.now();
      savedOpens = opens;
      menu("Chain", "chain-admitted");
    } else if (phase === "chain-admitted") {
      check(screens.length === 0, "chain waits for close animation");
      phase = "chain-wait";
    } else if (phase === "chain-wait" && screens.length === 1) {
      releaseScreens();
      check(opens === savedOpens + 1, "actual deferred timer opens current chain");
      api.panelOpenScreen = null;
      main.lastCloseTimestamp = Date.now();
      menu("CancelledChain", "chain-cancel");
    } else if (phase === "chain-cancel") {
      ipc("clear", [], "chain-cleared");
    } else if (phase === "chain-cleared") {
      releaseScreens();
      savedOpens = opens;
      phase = "chain-quiescent";
    } else if (phase === "chain-quiescent" && Date.now() - phaseStarted > 600) {
      check(opens === savedOpens && screens.length === 0 && !main.state.active, "clear retires deferred timer");
      ipc("showFromFile", [caseDir + "/menu.json", JSON.stringify({
                                                                    resultFile: caseDir + "/results/obsolete"
                                                                  })], "obsolete-file");
    } else if (phase === "obsolete-file" && api.state.dmenuFileContinuations.length === 1) {
      heldFile = api.state.dmenuFileContinuations.shift();
      main.lastCloseTimestamp = 0;
      menu("Replacement", "file-replaced");
    } else if (phase === "file-replaced") {
      savedSid = main.state.sessionId;
      releaseFile(heldFile);
      check(main.state.sessionId === savedSid && main.state.items[0].name === "Replacement" && main.pendingFileLoader === null, "retired file completion cannot replace newer session");
      releaseScreens();
      api.panelOpenScreen = null;
      main.lastCloseTimestamp = 0;
      menu("Retire", "retire");
    } else if (phase === "retire" && screens.length === 1) {
      savedOpens = opens;
      Service.loadedPlugins = ({});
      phase = "retired";
    } else if (phase === "retired" && !main.ownerCurrent) {
      releaseScreens();
      check(opens === savedOpens && !main.state.active && main.currentRequest === null, "retired API fences screen and active session");
      ipc("toggle", [], "retired-toggle");
    } else if (phase === "retired-toggle") {
      check(toggles === 1 && screens.length === 0 && !main.state.active, "retired plugin-level toggle cannot dispatch");
      console.log("DMENU_SESSION: PASS lifetime");
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
    interval: 60
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
