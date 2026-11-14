import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins
import qs.Widgets

ShellRoot {
  id: root
  property var spotify: null
  property var spotifyMain: null
  property var todo: null
  property var todoMain: null
  property var manifests: null
  property bool started: false
  property string phase: "start"
  readonly property bool verifyOnly: Quickshell.env("I4_VERIFY") === "1"
  readonly property string tokenConsumer: spotify?.pluginSettings?.accessToken || ""
  FileView { id: input; path: Quickshell.env("I4_FINAL_MANIFESTS"); blockLoading: true; printErrors: false }
  FileView { id: announced; path: Quickshell.env("I4_AUTH_WORK") + "/announced.json"; printErrors: false }
  Process { id: releaseProcess }
  function check(ok, label) { if (!ok) throw new Error("I4_FINAL_PAGES_ASSERT: " + phase + " " + label); }
  function openOwner(name,callback){Service._openSettingsOwner(name,function(owner){try{root.check(owner!==null,"native owner "+name);root.register(name,owner);callback();}catch(error){console.error(String(error));Qt.exit(2);}});}
  function register(name, value) {
    var api = Service.createPluginAPI(name, manifests[name], value, {}, {}, {});
    var loaded = Object.assign({}, Service.loadedPlugins); loaded[name] = {api: api}; Service.loadedPlugins = loaded;
    var component = Qt.createComponent("file://" + Registry.getPluginDir(name) + "/Main.qml");
    check(component.status === Component.Ready, component.errorString());
    var main = component.createObject(scene, {pluginApi: api}); check(main !== null, "actual Main " + name); api.mainInstance = main;
    if (name === "spotify-player") { spotify = api; spotifyMain = main; }
    else { todo = api; todoMain = main; }
  }
  function ready(number) {
    announced.reload(); announced.waitForJob();
    var text = announced.text(); return text && JSON.parse(text).number >= number;
  }
  function release(number) {
    check(!releaseProcess.running, "prior release settled");
    releaseProcess.command = ["python3", Quickshell.env("I4_AUTH_HELPER"), "release", Quickshell.env("I4_AUTH_WORK"), String(number)];
    releaseProcess.running = true;
  }
  function request(page) {
    page.requestToken({clientId: page.editClientId, clientSecret: page.editClientSecret, callbackPort: page.editCallbackPort}, {refresh_token: page.editRefreshToken, grant_type: "refresh_token"}, null);
  }
  function start() {
    if (started || !Settings.isLoaded) return;
    started = true; input.waitForJob(); manifests = JSON.parse(input.text());
    if (verifyOnly) {
      openOwner("spotify-player", function() {
        openOwner("todo", function() { root.phase = "restart"; });
      });
      return;
    }
    openOwner("spotify-player",function(){
      check(spotify.pluginSettings.clientId==="fixture-client"&&spotify.pluginSettings.refreshToken==="fixture-refresh-0","initial inert preferences");
      popup.openPluginSettings(manifests["spotify-player"], "settings"); phase = "auth";
    });
  }
  function drive() {
    var page = popup.settingsPage;
    if (phase === "auth" && popup.opened && page) {
      check(!popup.dirty && !spotifyMain._request, "opening causes no refresh or preference input");
      page.editCallbackPort = Number(Quickshell.env("I4_AUTH_CALLBACK_PORT"));
      page.startAuth(); phase = "auth-request";
    } else if (phase === "auth-request" && ready(1)) {
      check(tokenConsumer === "" && spotify.pluginSettings.callbackPort === 8888, "browser/callback/token request never persists editor preferences");
      release(1); phase = "auth-result";
    } else if (phase === "auth-result" && page.editAccessToken === "fixture-token-1") {
      check(popup.dirty && tokenConsumer === "", "local token result is pending");
      popup.applySettings(); phase = "applied";
    } else if (phase === "applied" && !popup.busy) {
      check(!popup.saveFailed && !popup.dirty && tokenConsumer === "fixture-token-1", "actual token consumer after current preference receipt");
      request(page); phase = "stale-request";
    } else if (phase === "stale-request" && ready(2)) {
      page.editClientId = "newer-local-client"; release(2); phase = "stale-result";
    } else if (phase === "stale-result" && !page._tokenRequest) {
      check(page.editAccessToken === "fixture-token-1" && page.editClientId === "newer-local-client" && tokenConsumer === "fixture-token-1", "stale auth result never replaces newer input or live token");
      popup.requestClose(); popup.confirmDiscard(); phase = "dead-open";
    } else if (phase === "dead-open" && !popup.visible && !popup.currentPlugin) {
      popup.openPluginSettings(manifests["spotify-player"], "settings"); phase = "dead-request";
    } else if (phase === "dead-request" && popup.opened && page) {
      request(page); phase = "dead-announced";
    } else if (phase === "dead-announced" && ready(3)) {
      popup.requestClose(); phase = "dead-close";
    } else if (phase === "dead-close" && !popup.visible && !popup.currentPlugin) {
      release(3); spotifyMain.refreshAccessToken(); phase = "runtime-stale";
    } else if (phase === "runtime-stale" && ready(4)) {
      spotify.pluginSettings.clientId = "foreign-client";
      release(4); phase = "runtime-stale-result";
    } else if (phase === "runtime-stale-result" && !spotifyMain._request) {
      check(tokenConsumer === "fixture-token-1" && spotify.pluginSettings.clientId === "foreign-client", "runtime stale request fenced");
      spotifyMain.refreshAccessToken(); phase = "runtime-current";
    } else if (phase === "runtime-current" && ready(5)) {
      release(5); phase = "runtime-current-result";
    } else if (phase === "runtime-current-result" && tokenConsumer === "fixture-token-5") {
      spotify.saveSettings(function(result) {
        check(result.status === "saved" || result.status === "nothing_to_save", "actual runtime token save completed");
        openOwner("todo",function(){check(todo.pluginSettings.current_page_id===1,"Todo initial native owner");popup.openPluginSettings(manifests.todo,"settings");phase="todo";});
      });
      phase = "runtime-saving";
    } else if (phase === "todo" && popup.opened && page) {
      check(page.renamePage(1, "Renamed"), "actual selected rename");
      page.performPageDeletion(1);
      page.newPageName = "Added"; page.addPage();
      check(todoMain.rawPages[1].name === "Work" && todoMain.rawTodos[0].pageId === 1, "selected page commands do not mutate Main before Apply");
      popup.applySettings(); phase = "todo-saved";
    } else if (phase === "todo-saved" && !popup.busy) {
      check(!popup.saveFailed && !popup.dirty && todoMain.rawPages[1].name === "Added" && todoMain.rawTodos[0].pageId === 0 && todoMain.rawTodos[0].opaque.keep && todo.pluginSettings.current_page_id === 0, "actual Main consumes admitted selected page command bundle");
      console.log("I4_FINAL_PAGES: SAVED_PASS"); Qt.exit(0);
    } else if (phase === "restart") {
      check(tokenConsumer === "fixture-token-5" && spotify.pluginSettings.clientId === "foreign-client", "runtime tokens after cold restart");
      check(todoMain.rawPages[1].name === "Added" && todoMain.rawTodos[0].pageId === 0 && todoMain.rawTodos[0].opaque.keep, "actual Todo Main after cold restart");
      console.log("I4_FINAL_PAGES: RESTART_PASS"); Qt.exit(0);
    }
  }
  FloatingWindow {
    visible: true; implicitWidth: 900; implicitHeight: 700
    Item { id: scene; anchors.fill: parent }
    NPluginSettingsPopup { id: popup; parent: Overlay.overlay }
  }
  Connections { target: Settings; function onSettingsLoaded() { root.start(); } }
  Component.onCompleted: start()
  Timer { interval: 80; repeat: true; running: true; onTriggered: { try { root.drive(); } catch (error) { console.error(String(error)); Qt.exit(2); } } }
  Timer { interval: 50000; running: true; onTriggered: { console.error("I4_FINAL_PAGES_ASSERT: watchdog", root.phase); Qt.exit(2); } }
}
