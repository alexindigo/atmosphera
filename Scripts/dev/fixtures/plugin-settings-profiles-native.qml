import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins
import qs.Widgets

ShellRoot {
  id: root
  readonly property string scope: Quickshell.env("PHA_PROFILES_SCOPE")
  readonly property string mode: Quickshell.env("PHA_PROFILES_MODE")
  readonly property string boundary: Quickshell.env("PHA_PROFILES_BOUNDARY")
  readonly property string casePath: Quickshell.env("PHA_PROFILES_CASE")
  readonly property bool oldRed: Quickshell.env("PHA_PROFILES_RED") === "1"
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
  FileView {
    id: manifest
    path: Settings.configDir + "plugins/shell-profiles/manifest.json"
    blockLoading: true
  }
  FileView {
    id: dictionary
    path: Settings.configDir + "plugins/shell-profiles/i18n/en.json"
    blockLoading: true
  }
  FileView {
    id: expectations
    path: root.casePath + "/expectations.json"
    blockLoading: true
  }
  FileView {
    id: directories
    path: root.casePath + "/directories.json"
    blockLoading: true
  }
  Process {
    id: disk
    onExited: code => {
      if (code !== 0)
        root.fail("independent complete profile documents " + root.diskBoundary);
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
      throw new Error("PROFILES_ASSERT: " + scope + "/" + mode + "/" + phase + ": " + message);
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
        var found = find(child, predicate);
        if (found)
          return found;
      }
    }
    return null;
  }
  function create(entry, context) {
    var component = Qt.createComponent("file://" + api.pluginDir + "/" + api.manifest.entryPoints[entry]);
    check(component.status === Component.Ready, component.errorString());
    var item = PluginLoader.createObject("shell-profiles", entry, component, content, context, {});
    check(item, "actual " + entry + " constructs");
    return item;
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    manifest.waitForJob();
    dictionary.waitForJob();
    directories.waitForJob();
    var descriptor = JSON.parse(manifest.text()), dict = JSON.parse(dictionary.text());
    Registry.installedPlugins = {
      "shell-profiles": descriptor
    };
    Service._openSettingsOwner("shell-profiles", function (owner) {
      try {
        check(owner, "actual native owner");
        api = Service.createPluginAPI("shell-profiles", descriptor, owner, dict, dict, {});
        Service.loadedPlugins = {
          "shell-profiles": {
            api: api
          }
        };
        main = create("main", api);
        api.mainInstance = main;
        selected = PluginInstances.apiFor("shell-profiles", {
                                            kind: "bar",
                                            list: "global",
                                            section: "left",
                                            index: 0
                                          });
        sibling = PluginInstances.apiFor("shell-profiles", {
                                           kind: "bar",
                                           list: "global",
                                           section: "left",
                                           index: 1
                                         });
        inherited = PluginInstances.apiFor("shell-profiles", {
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
    return ["profilesDir", "includeWallpapers", "backupEnabled", "backupCount"].every(key => JSON.stringify(target.pluginSettings[key]) === JSON.stringify(cfg[key]));
  }
  function probe(name, next) {
    diskBoundary = name;
    afterDisk = next;
    phase = "disk";
    disk.command = ["python3", "-B", Quickshell.env("PHA_PROFILES_DISK"), casePath, Quickshell.env("PHA_PROFILES_OUTPUT") + "/persisted", name];
    disk.running = true;
  }
  function open(next) {
    check(scope === "shared" ? popup.openPluginSettings(api.manifest, "settings") : popup.openInstanceSettings(api.manifest, selected, "settings"), "actual scoped page opens");
    phase = next;
  }
  function edit() {
    var directory = find(popup.settingsPage, item => item.label === api.tr("settings.dir-label") && item.inputEditCommitted !== undefined);
    var wallpaper = find(popup.settingsPage, item => item.label === api.tr("settings.wallpapers-label") && item.toggled !== undefined);
    var backup = find(popup.settingsPage, item => item.label === api.tr("settings.backup-label") && item.toggled !== undefined);
    var count = find(popup.settingsPage, item => item.objectName === "settings-range-editBackupCount");
    check(directory && wallpaper && backup && count, "actual directory and policy controls");
    directory.text = JSON.parse(directories.text()).selected;
    directory.inputEditCommitted();
    wallpaper.toggled(false);
    backup.toggled(false);
    count.moved(2);
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
    var cfg = values(name), client = oldRed ? main : main.settingsConsumerFor((scope === "instance" ? selected : api).settingsContext);
    var dir = cfg.profilesDir || Settings.configDir + "profiles/";
    var paths = JSON.parse(directories.text());
    var label = Object.keys(paths).find(key => dir === paths[key] || dir === paths[key] + "/") || "default";
    if (oldRed)
      check(client.profiles.indexOf("profile-" + label) !== -1, "original listing consumes saved selected directory");
    else {
      if (client.profiles.indexOf("profile-" + label) === -1)
        return;
      check(panel.service === client, "Panel uses exact Main-owned selected client");
      check(main.settingsConsumerFor((scope === "instance" ? selected : api).settingsContext) === client, "same context shares listing");
      check(find(panel, item => item.text === "profile-" + label), "actual Panel profile Text");
      check(bar.widgetIcon === cfg.icon && find(bar, item => item.icon === cfg.icon), "actual Bar icon");
      var other = main.settingsConsumerFor(sibling.settingsContext), follow = main.settingsConsumerFor(inherited.settingsContext);
      if (other.profiles.indexOf("profile-sibling") === -1 || follow.profiles.length !== 1)
        return;
      check(other !== client && follow !== client, "distinct API clients");
      check(other.profiles[0] === "profile-sibling", "overridden sibling directory remains selected");
    }
    console.log("PROFILES_CONSUMER " + JSON.stringify({
                                                        boundary: name,
                                                        profiles: client.profiles,
                                                        directory: dir
                                                      }));
    console.log("PROFILES_NATIVE: PASS " + scope + " " + mode + " " + boundary);
    Qt.exit(0);
  }
  function drive() {
    check(Date.now() - since < 18000, "finite native profile phase");
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
    else if (phase === "reset-page" && popup.opened && popup.settingsPage && !popup.busy) {
      check(popup._pageApi.resetFields(["profilesDir", "includeWallpapers", "backupEnabled", "backupCount"]), "one staged native Reset");
      phase = "reset-staging";
    } else if (phase === "reset-staging" && !popup.busy && ["profilesDir", "includeWallpapers", "backupEnabled", "backupCount"].every(key => popup._pageApi.field(key).pendingIntent === "reset"))
      probe("reset-staged", "reset-apply");
    else if (phase === "reset-apply")
      apply("reset-applied");
    else if (phase === "reset-applied" && accepted() && ready("reset"))
      probe("reset", "reset-consumers");
    else if (phase === "reset-consumers")
      consumers("reset");
    else if (phase === "change-base") {
      api.pluginSettings.profilesDir = JSON.parse(directories.text()).following;
      api.pluginSettings.includeWallpapers = false;
      api.pluginSettings.backupEnabled = false;
      api.pluginSettings.backupCount = 3;
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
