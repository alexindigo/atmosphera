// G2 action-policy representatives: real pages, native owners and inert effects.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins
import qs.Services.UI
import qs.Widgets

ShellRoot {
  id: root
  readonly property string plugin: Quickshell.env("PHA_G2_PLUGIN")
  readonly property string scope: Quickshell.env("PHA_G2_SCOPE")
  readonly property string mode: Quickshell.env("PHA_G2_MODE")
  readonly property string boundary: Quickshell.env("PHA_G2_BOUNDARY")
  readonly property bool control: Quickshell.env("PHA_G2_CONTROL") === "1"
  readonly property bool gif: plugin === "screencast-gif"
  readonly property string field: gif ? "fps" : "disableToastNotifications"
  property bool started: false
  property string phase: "startup"
  property double phaseStarted: Date.now()
  onPhaseChanged: phaseStarted = Date.now()
  property var api: null
  property var selected: null
  property var sibling: null
  property var inherited: null
  property var main: null
  property var views: []
  property var receipt: null
  property string afterDisk: ""
  property string diskBoundary: ""
  property string afterAction: ""
  property string actionBoundary: ""
  property int actionIndex: 0
  property int requestCount: 0
  property int toastCount: 0
  property int beforeToast: 0
  property double actionStarted: 0
  property string actionVerb: ""
  FileView {
    id: manifestFile
    path: Settings.configDir + "plugins/" + root.plugin + "/manifest.json"
    blockLoading: true
  }
  FileView {
    id: dictionaryFile
    path: Settings.configDir + "plugins/" + root.plugin + "/i18n/en.json"
    blockLoading: true
  }
  FileView {
    id: expectedFile
    path: Quickshell.env("PHA_G2_CASE") + "/expectations.json"
    blockLoading: true
  }
  FileView {
    id: requestsFile
    path: Quickshell.env("PHA_G2_CASE") + "/requests.jsonl"
    blockLoading: true
  }
  Process {
    id: disk
    onExited: code => {
      if (code !== 0)
        root.fail("complete native documents: " + root.diskBoundary);
      else
        root.phase = root.afterDisk;
    }
  }
  PanelWindow {
    visible: true
    implicitWidth: 1280
    implicitHeight: 900
    Item {
      id: content
      width: 1280
      height: 900
    }
    NPluginSettingsPopup {
      id: popup
      screen: Quickshell.screens[0]
      onSettingsCompleted: result => root.receipt = result
    }
  }
  Connections {
    target: ToastService
    function onNotify(title, description, icon, type, duration, actionLabel, actionCallback) {
      if (title === api?.tr("toast.connectedTo", {
                              name: "Controlled VPN"
                            }) || title === api?.tr("toast.disconnectedFrom", {
                                                      name: "Controlled VPN"
                                                    }))
        ++root.toastCount;
    }
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("G2_NATIVE_ASSERT: " + plugin + "/" + scope + "/" + mode + "/" + phase + ": " + message);
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
    var item = PluginLoader.createObject(plugin, entry, component, content, context, {
                                           screen: Quickshell.screens[0]
                                         });
    check(item !== null, "actual " + entry + " constructs");
    return item;
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    manifestFile.waitForJob();
    dictionaryFile.waitForJob();
    var manifest = JSON.parse(manifestFile.text()), dictionary = JSON.parse(dictionaryFile.text());
    var registry = {};
    registry[plugin] = manifest;
    Registry.installedPlugins = registry;
    Service._openSettingsOwner(plugin, function (owner) {
      try {
        check(owner !== null, "native plugin owner");
        api = Service.createPluginAPI(plugin, manifest, owner, dictionary, dictionary, {});
        var loaded = {};
        loaded[plugin] = {
          api: api
        };
        Service.loadedPlugins = loaded;
        main = create("main", api);
        api.mainInstance = main;
        var contexts = [0, 1, 2].map(index => PluginInstances.apiFor(plugin, {
                                                                       kind: "bar",
                                                                       list: "global",
                                                                       section: "left",
                                                                       index: index
                                                                     }));
        selected = contexts[0];
        sibling = contexts[1];
        inherited = contexts[2];
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
    return [base].concat(expected.bar.widgets.left.map(row => Object.assign({}, base, row.instanceSettings || {})));
  }
  function ready(name) {
    var expected = values(name);
    return views.every((view, index) => view.api.pluginSettings[field] === expected[index][field]) && (gif || main.vpnList.length === 1);
  }
  function probe(name, next) {
    afterDisk = next;
    diskBoundary = name;
    phase = "disk";
    disk.command = ["python3", "-B", Quickshell.env("PHA_G2_DISK"), Quickshell.env("PHA_G2_CASE"), Quickshell.env("PHA_G2_OUTPUT") + "/persisted", name];
    disk.running = true;
  }
  function open(next) {
    check(scope === "shared" ? popup.openPluginSettings(api.manifest, "settings") : popup.openInstanceSettings(api.manifest, selected, "settings"), "actual scoped page opens");
    phase = next;
  }
  function edit() {
    var control = find(popup.settingsPage, item => item.label === api.tr(gif ? "settings.fps.label" : "settings.disableToastNotifications"));
    check(control, "actual preference control");
    if (gif) {
      control.text = "24";
      control.editCommitted();
    } else
      control.toggled(true);
    check(popup._pageApi.field(field).value === (gif ? 24 : true), "real control stages one selected field");
    for (var key of Object.keys(api.manifest.metadata.settingsSchema.fields))
      if (key !== field)
        check(!popup._pageApi.field(key).pendingIntent, "untouched field has no intent: " + key);
  }
  function apply(next) {
    receipt = null;
    check(popup.applySettings(), "native Apply");
    phase = next;
  }
  function accepted() {
    return receipt && !popup.busy && receipt.status === "saved" && receipt.refreshState === "current";
  }
  function requests() {
    requestsFile.reload();
    requestsFile.waitForJob();
    return String(requestsFile.text()).trim().split("\n").filter(line => line).map(line => JSON.parse(line));
  }
  function startActions(name, next) {
    actionBoundary = name;
    afterAction = next;
    actionIndex = 0;
    phase = "action-start";
  }
  function actions() {
    var view = views[actionIndex], expected = values(actionBoundary)[actionIndex];
    if (phase === "action-start") {
      if (!gif && main.isLoading)
        return;
      requestCount = requests().length;
      beforeToast = toastCount;
      actionStarted = Date.now();
      if (gif)
        view.bar.clicked();
      else {
        var row = find(view.panel, child => child.name === "Controlled VPN" && child.buttonClicked !== undefined);
        check(row, "actual VPN action row");
        actionVerb = row.isConnected ? "down" : "up";
        row.buttonClicked();
      }
      phase = "action-wait";
    } else {
      var rows = requests();
      if (rows.length <= requestCount || Date.now() - actionStarted < 180)
        return;
      check(rows.length === requestCount + 1, "one action owner receives one originating action");
      var row = rows[rows.length - 1];
      if (gif)
        check(row.fps === String(expected.fps) && row.maxSecs === String(expected.maxRecordingSeconds) && row.outDir === expected.outputDir, "actual capture endpoint receives selected policy");
      else {
        check(JSON.stringify(row.argv) === JSON.stringify(["connection", actionVerb, "uuid", "controlled-vpn"]), "literal originating VPN target");
        check(toastCount - beforeToast === (expected.disableToastNotifications ? 0 : 1), "actual toast endpoint receives captured selected policy");
      }
      console.log("G2_ACTION " + JSON.stringify({
                                                  boundary: actionBoundary,
                                                  index: actionIndex,
                                                  request: row,
                                                  toastCount: toastCount - beforeToast
                                                }));
      ++actionIndex;
      if (actionIndex < views.length)
        phase = "action-start";
      else
        phase = afterAction;
    }
  }
  function drive() {
    check(Date.now() - phaseStarted < 18000, "finite action/native deadline");
    if (phase === "runtime" && selected.settingsReady && sibling.settingsReady && inherited.settingsReady) {
      views = [api, selected, sibling, inherited].map(context => ({
        api: context,
        bar: create("barWidget", context),
        panel: gif ? null : create("panel", context)
      }));
      phase = "initial";
    } else if (phase === "initial") {
      var name = mode === "edit" ? "initial" : mode === "reset" ? "edited" : mode === "follow" ? "reset" : boundary;
      if (!ready(name))
        return;
      if (control && mode === "edit")
        phase = "initial-disk";
      else
        startActions(name, mode === "cold" ? "finish" : mode === "edit" ? "initial-disk" : mode === "follow" ? "change-base" : "open-reset");
    } else if (phase === "initial-disk")
      probe("initial", "open-discard");
    else if (phase === "open-discard")
      open("discard-page");
    else if (phase === "discard-page" && popup.opened && popup.settingsPage) {
      check(!popup.dirty && !popup._editor.dirty, "construction has no intent");
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
      probe("edited", "edited-actions");
    else if (phase === "edited-actions")
      startActions("edited", "finish");
    else if (phase === "open-reset")
      open("reset-page");
    else if (phase === "reset-page" && popup.opened && popup.settingsPage && !popup.busy) {
      check(popup._pageApi.field(field).reset(), "native staged Reset");
      probe("reset-staged", "reset-actions");
    } else if (phase === "reset-actions")
      startActions("edited", "reset-apply");
    else if (phase === "reset-apply")
      apply("reset-applied");
    else if (phase === "reset-applied" && accepted() && ready("reset"))
      probe("reset", "reset-final-actions");
    else if (phase === "reset-final-actions")
      startActions("reset", "finish");
    else if (phase === "change-base") {
      api.pluginSettings[field] = gif ? 18 : true;
      phase = "base-saving";
      api.saveSettings(function (result) {
        try {
          check(result.status === "saved", "native base propagation");
          phase = "base-changed";
        } catch (error) {
          fail(error);
        }
      });
    } else if (phase === "base-changed" && ready("following"))
      probe("following", "following-actions");
    else if (phase === "following-actions")
      startActions("following", "retire");
    else if (phase === "retire") {
      requestCount = requests().length;
      Service.loadedPlugins = ({});
      phase = "retired";
    } else if (phase === "retired" && !selected.settingsContext.current()) {
      if (gif)
        main.trigger(selected.settingsContext);
      else
        check(main.connectTo("controlled-vpn", selected.settingsContext) === false, "retired VPN action refuses");
      actionStarted = Date.now();
      phase = "retired-check";
    } else if (phase === "retired-check" && Date.now() - actionStarted > 250) {
      check(requests().length === requestCount, "retired context cannot dispatch a new physical action");
      phase = "finish";
    } else if (phase === "action-start" || phase === "action-wait")
      actions();
    else if (phase === "finish") {
      console.log("G2_NATIVE: PASS " + plugin + " " + scope + " " + mode + " " + boundary);
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
