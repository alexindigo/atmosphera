// Real Music Main/helper plus selected generic page; no preference/action mock.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins
import qs.Widgets

ShellRoot {
  id: root
  readonly property string scope: Quickshell.env("PHA_MUSIC_SCOPE")
  readonly property bool cold: Quickshell.env("PHA_MUSIC_COLD") === "1"
  readonly property string caseRoot: Quickshell.env("PHA_MUSIC_CASE")
  property bool started: false
  property string phase: "startup"
  property var api: null
  property var main: null
  property var selected: null
  property var input: null
  property var limitButton: null
  property var folderButton: null
  property var savedPage: null
  property string afterCapture: ""
  property string capturePath: ""
  property string captureLabel: ""
  FileView {
    id: manifestFile
    path: Settings.configDir + "plugins/music-search/manifest.json"
    blockLoading: true
    printErrors: false
  }
  FileView {
    id: dictionaryFile
    path: Settings.configDir + "plugins/music-search/i18n/en.json"
    blockLoading: true
    printErrors: false
  }
  FileView {
    id: barrier
    path: root.caseRoot + "/locked"
    printErrors: false
  }
  Process {
    id: lockHolder
  }
  Process {
    id: diskProbe
    onExited: code => {
      if (code !== 0)
        root.fail("independent helper-file boundary failed");
      else
        root.renderCapture();
    }
  }
  Process {
    id: captureProcess
    onExited: code => {
      if (code !== 0)
        root.fail("guest screenshot failed " + code);
      else
        root.phase = root.afterCapture;
    }
  }
  Timer {
    id: paint
    interval: 180
    onTriggered: {
      captureProcess.command = ["grim", "-o", Quickshell.screens[0].name, root.capturePath];
      captureProcess.running = true;
    }
  }
  Process {
    id: actor
    onExited: code => {
      if (code !== 0)
        root.fail("actor failed " + code);
      else
        root.phase = root.phase === "release" ? "applied" : root.phase === "refuse" ? "fail-submit" : "retry-submit";
    }
  }
  PanelWindow {
    id: host
    visible: true
    implicitWidth: 1280
    implicitHeight: 800
    NPluginSettingsPopup {
      id: popup
      screen: Quickshell.screens[0]
    }
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("MUSIC_ACTION_ASSERT: " + scope + "/" + phase + ": " + message);
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
  function feedback(code) {
    return find(popup.settingsPage, item => item.objectName === "music-download-action-feedback" && item.visible && item.text.length > 0 && item.text === popup.settingsPage.downloadActionFeedback) !== null && main.downloadSettingsResult?.errorCode === code;
  }
  function clickLimit(value) {
    input.submitValue(value);
    check(popup.settingsPage.editDownloadCacheMaxMb === value, "actual limit input signal");
    limitButton.clicked();
  }
  function capture(label, next) {
    captureLabel = label;
    afterCapture = next;
    phase = "disk";
    diskProbe.command = ["python3", "-B", Quickshell.env("PHA_MUSIC_DISK"), label];
    diskProbe.running = true;
  }
  function renderCapture() {
    var destination = Quickshell.env("PHA_MUSIC_SHOTS");
    if (!destination) {
      phase = afterCapture;
      return;
    }
    var feedbackItem = find(popup.settingsPage, item => item.objectName === "music-download-action-feedback");
    var scroll = find(popup.contentItem, item => typeof item.applyWheelScroll === "function");
    check(feedbackItem && scroll, "actual feedback/scroll presentation");
    var position = feedbackItem.mapToItem(scroll.contentItem, 0, 0);
    scroll.contentItem.contentY = Math.max(0, Math.min(scroll.contentItem.contentHeight - scroll.contentItem.height, scroll.contentItem.contentY + position.y - scroll.contentItem.height / 2));
    capturePath = destination + "/" + captureLabel + ".png";
    phase = "capture";
    paint.start();
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    manifestFile.waitForJob();
    var manifest = JSON.parse(manifestFile.text());
    Registry.installedPlugins = {
      "music-search": manifest
    };
    Service._openSettingsOwner("music-search", function (owner) {
      try {
        check(owner !== null, "native plugin owner");
        dictionaryFile.waitForJob();
        var dictionary = JSON.parse(dictionaryFile.text());
        api = Service.createPluginAPI("music-search", manifest, owner, dictionary, dictionary, {});
        Service.loadedPlugins = {
          "music-search": {
            api: api
          }
        };
        var component = Qt.createComponent("file://" + api.pluginDir + "/Main.qml");
        check(component.status === Component.Ready, component.errorString());
        main = PluginLoader.createObject("music-search", "main", component, host.contentItem, api, {});
        check(main !== null, "actual Main");
        api.mainInstance = main;
        selected = scope === "shared" ? api : PluginInstances.apiFor("music-search", {
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
    if (phase === "runtime" && selected.settingsReady && main.downloadCacheMaxMb === (cold ? 3 : 64)) {
      check(scope === "shared" ? popup.openPluginSettings(api.manifest) : popup.openInstanceSettings(api.manifest, selected, "settings"), "actual selected page");
      phase = "page";
    } else if (phase === "page" && popup.opened && popup.settingsPage) {
      check(!popup.dirty && !popup._editor.dirty, "opening creates no preference intent");
      input = find(popup.settingsPage, item => item.to === 500000 && typeof item.submitValue === "function");
      limitButton = find(popup.settingsPage, item => item.text === api.tr("settings.cache.apply") && typeof item.clicked === "function");
      folderButton = find(popup.settingsPage, item => item.text === api.tr("settings.downloads.applyFolder") && typeof item.clicked === "function");
      check(input && limitButton && folderButton, "actual action controls");
      if (cold) {
        check(popup.settingsPage.editDownloadCacheMaxMb === 3 && main.downloadDirectory === caseRoot + "/new music", "cold Main and Settings actual helper values");
        check(main.downloadSettingsResult === null && !popup.dirty, "cold opening does not invent action success or preference intent");
        check(popup.requestClose(), "cold clean Close");
        console.log("MUSIC_ACTION: COLD_PASS " + scope);
        Qt.exit(0);
        return;
      }
      savedPage = popup.settingsPage;
      input.submitValue(1);
      check(main.downloadCacheMaxMb === 64 && !main.providerBusy && !popup.dirty, "buffered helper limit is not a preference Apply/action");
      lockHolder.command = ["python3", "-B", Quickshell.env("PHA_MUSIC_LOCK")];
      lockHolder.running = true;
      phase = "locking";
    } else if (phase === "locking") {
      barrier.reload();
      barrier.waitForJob();
      if (barrier.text().trim() !== "locked")
        return;
      limitButton.clicked();
      phase = "pending";
    } else if (phase === "pending" && main.providerBusy) {
      check(main.downloadSettingsResult?.status === "pending" && main.downloadCacheMaxMb === 64, "pending real action is not acknowledged success");
      capture("pending", "reject-busy");
    } else if (phase === "reject-busy") {
      clickLimit(2);
      check(main.downloadSettingsResult?.status === "rejected" && feedback("busy") && popup.settingsPage.editDownloadCacheMaxMb === 2, "busy action rejects visibly with local input retained");
      check(popup.settingsPage === savedPage && !popup.dirty, "action admission does not recreate page or author preferences");
      capture("busy", "release-action");
    } else if (phase === "release-action") {
      actor.command = ["touch", caseRoot + "/release"];
      phase = "release";
      actor.running = true;
    } else if (phase === "applied" && !main.providerBusy && !lockHolder.running && main.downloadCacheMaxMb === 1) {
      check(main.downloadSettingsResult?.status === "saved" && main.downloadSettingsResult.appliedValue === 1 && main.downloadSettingsResult.requestedValue === 1, "result names admitted limit, not rejected newer buffer");
      check(popup.settingsPage.editDownloadCacheMaxMb === 2 && feedback("") && popup.settingsPage.downloadActionFeedback.indexOf("1") !== -1, "feedback shows actual applied limit and retains newer local input");
      capture("applied", "folder-submit");
    } else if (phase === "folder-submit") {
      popup.settingsPage.editDownloadDirectory = caseRoot + "/new music";
      folderButton.clicked();
      phase = "folder";
    } else if (phase === "folder" && !main.providerBusy && main.downloadDirectory === caseRoot + "/new music") {
      check(main.downloadSettingsResult?.status === "saved" && main.downloadSettingsResult.kind === "directory" && main.downloadSettingsResult.appliedValue === main.downloadDirectory && feedback(""), "real folder helper result shown");
      capture("folder", "refuse-permissions");
    } else if (phase === "refuse-permissions") {
      actor.command = ["chmod", "500", caseRoot + "/helper"];
      phase = "refuse";
      actor.running = true;
    } else if (phase === "fail-submit") {
      clickLimit(3);
      phase = "failed";
    } else if (phase === "failed" && !main.providerBusy) {
      // This unchanged helper can return old JSON with rc 0 after its pipeline
      // writer fails. Both helper errors and requested/applied mismatch refuse.
      check(main.downloadSettingsResult?.status === "failed" && feedback("helper_failed") && main.downloadCacheMaxMb === 1 && popup.settingsPage.editDownloadCacheMaxMb === 3, "real IO failure retains input and never acknowledges it: " + JSON.stringify({
                                                                                                                                                                                                                                                              result: main.downloadSettingsResult,
                                                                                                                                                                                                                                                              applied: main.downloadCacheMaxMb,
                                                                                                                                                                                                                                                              local: popup.settingsPage.editDownloadCacheMaxMb,
                                                                                                                                                                                                                                                              feedback: popup.settingsPage.downloadActionFeedback
                                                                                                                                                                                                                                                            }));
      capture("failed", "restore-permissions");
    } else if (phase === "restore-permissions") {
      actor.command = ["chmod", "700", caseRoot + "/helper"];
      phase = "restore";
      actor.running = true;
    } else if (phase === "retry-submit") {
      check(popup.settingsPage === savedPage, "Retry same actual page");
      limitButton.clicked();
      phase = "retried";
    } else if (phase === "retried" && !main.providerBusy && main.downloadCacheMaxMb === 3) {
      check(main.downloadSettingsResult?.status === "saved" && main.downloadSettingsResult.appliedValue === 3 && feedback(""), "real helper Retry acknowledged in Settings");
      capture("retried", "close-popup");
    } else if (phase === "close-popup") {
      check(!popup.dirty && popup.requestClose(), "explicit actions stay outside preference draft");
      phase = "closed";
    } else if (phase === "closed" && !popup.visible) {
      console.log("MUSIC_ACTION: PASS " + scope);
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
    interval: 60000
    running: true
    onTriggered: root.fail("watchdog " + phase)
  }
  Component.onCompleted: begin()
}
