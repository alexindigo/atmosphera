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
  readonly property bool ds4: plugin === "ds4-colors"
  readonly property bool nv: plugin === "nvibrant"
  readonly property bool hardware: ds4 || nv
  readonly property string field: gif ? "fps" : ds4 ? "color" : nv ? "vibranceValue" : "disableToastNotifications"
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
  property int toggleStep: 0
  readonly property bool readOnlyAction: mode === "cold" || popup.opened
  property var heldControllers: null
  property int typedValue: 0
  property int typedDisplay: 0
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
    return views.every((view, index) => view.api.pluginSettings[field] === expected[index][field]) && (gif || nv || (ds4 ? Object.keys(main.controllers).length === 2 && !main.isApplying : main.vpnList.length === 1));
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
    if (ds4) {
      var picker = find(popup.settingsPage, item => item.selectedColor !== undefined && item.colorSelected !== undefined);
      check(picker, "actual color picker");
      picker.colorSelected("#334455");
      check(popup._pageApi.field(field).value === "#334455", "actual color intent");
      return;
    }
    if (nv) {
      var spin = find(popup.settingsPage, item => item.to === 1023 && item.valueModified !== undefined);
      check(spin, "actual vibrance spinbox");
      spin.valueModified(640);
      check(popup._pageApi.field(field).value === 640, "actual vibrance intent");
      return;
    }
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
    toggleStep = 0;
    phase = "action-start";
  }
  function actions() {
    var view = views[actionIndex], expected = values(actionBoundary)[actionIndex];
    if (phase === "action-start") {
      if (hardware) {
        if (ds4 && main.isApplying || view.api._pendingSettingsSaves > 0)
          return;
        // A preceding context's native toggle can still be propagating through
        // the inherited preview read view after its persistence receipt.
        if (nv) {
          const enabled = toggleStep === 0 ? expected.enabled : !expected.enabled;
          if (view.api.settingsContext.settingsView.enabled !== enabled || view.api.pluginSettings.enabled !== enabled)
            return;
        }
        requestCount = requests().length;
        actionStarted = Date.now();
        if (nv) {
          if (readOnlyAction)
            main.applyVibrance(expected.vibranceValue, view.api.settingsContext);
          else
            view.bar.toggle();
        } else
          main.applyColors(view.api.settingsContext);
        phase = "action-wait";
        return;
      }
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
      if (hardware) {
        if (ds4 && main.isApplying || view.api._pendingSettingsSaves > 0)
          return;
        var observed = rows.slice(requestCount);
        if (ds4) {
          var color = Qt.color(expected.color);
          var rgb = [color.r, color.g, color.b].map(c => String(Math.round(c * 255)));
          check(observed.length === 2 && observed.every(row => JSON.stringify(row.argv.slice(3)) === JSON.stringify(rgb)), "actual hardware endpoint receives selected policy");
          check(view.bar.currentColor === expected.color, "actual selected Bar color");
        } else {
          var argv = Array(Math.round(expected.displayIndex - 1)).fill("0").concat([String(toggleStep === 0 ? Math.round(expected.vibranceValue) : 0)]);
          check(observed.length === 1 && JSON.stringify(observed[0].argv) === JSON.stringify(argv), "actual hardware endpoint receives selected policy");
          check(readOnlyAction || view.bar.vibrantEnabled === (toggleStep === 0), "actual native runtime enabled write");
          if (toggleStep === 0 && !readOnlyAction) {
            toggleStep = 1;
            phase = "action-start";
            return;
          }
          toggleStep = 0;
        }
        console.log("G2_ACTION " + JSON.stringify({
                                                    boundary: actionBoundary,
                                                    index: actionIndex,
                                                    requests: observed
                                                  }));
        ++actionIndex;
        phase = actionIndex < views.length ? "action-start" : afterAction;
        return;
      }
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
  Process {
    id: gate
    onExited: code => {
      if (code !== 0)
        root.fail("hardware gate/physical-byte readback failed");
    }
  }
  function gateCommand(action) {
    check(!gate.running, "one controlled hardware barrier");
    const base = Quickshell.env("PHA_G2_CASE");
    var script = "from pathlib import Path\np=Path(" + JSON.stringify(base) + ")\n";
    if (action === "hold")
      script += "(p/'hold-hardware').touch()\n(p/'fallback-hardware').touch()\n";
    else if (action === "release")
      script += "(p/'hold-hardware').unlink()\n";
    else
      script += "import json\nv={str(i):[(p/('led'+str(i)+':'+c)).read_text() for c in ('red','green','blue')] for i in (0,1)}\nassert all(x==['18','52','86'] for x in v.values()),v\nPath(" + JSON.stringify(Quickshell.env("PHA_G2_OUTPUT") + "/physical.json") + ").write_text(json.dumps(v))\n";
    gate.command = ["python3", "-c", script];
    gate.running = true;
  }
  function lifetime() {
    if (phase === "life-prepare") {
      requestCount = requests().length;
      if (ds4) {
        heldControllers = JSON.parse(JSON.stringify(main.controllers));
        gateCommand("hold");
        phase = "life-admit";
      } else {
        selected.pluginSettings.displayIndex = 3.6;
        selected.pluginSettings.vibranceValue = 640.6;
        selected.saveSettings();
        typedDisplay = 3.6 - 1;
        typedValue = 640.6;
        phase = "life-nv-admit";
      }
    } else if (phase === "life-admit" && !gate.running) {
      check(main.setColor(18, 52, 86, selected), "selected native hardware writer admitted");
      phase = "life-held";
    } else if (phase === "life-held" && requests().length > requestCount) {
      check(main.isApplying, "direct controller operation is actually held");
      check(main.setColor(200, 201, 202, sibling) === false, "another origin cannot overwrite admitted operation");
      main.currentR = 200;
      main.currentG = 201;
      main.currentB = 202;
      for (var path of Object.keys(main.controllers)) {
        main.controllers[path].red = Quickshell.env("PHA_G2_CASE") + "/alternate:red";
        main.controllers[path].green = Quickshell.env("PHA_G2_CASE") + "/alternate:green";
        main.controllers[path].blue = Quickshell.env("PHA_G2_CASE") + "/alternate:blue";
        main.controllers[path].separator = "::";
      }
      main.controllers = ({});
      gateCommand("release");
      phase = "life-complete";
    } else if (phase === "life-complete" && !main.isApplying && selected._pendingSettingsSaves === 0 && api._pendingSettingsSaves === 0 && !gate.running) {
      var rows = requests().slice(requestCount);
      check(rows.length === 4, "two captured controllers each reach direct then fallback once");
      check(rows.every(row => JSON.stringify(row.argv.slice(-3)) === JSON.stringify(["18", "52", "86"])), "direct and elevation retain admitted RGB");
      check(rows.filter(row => row.endpoint === "pkexec").length === 2, "actual inert elevation endpoints");
      gateCommand("bytes");
      phase = "life-bytes";
    } else if (phase === "life-bytes" && !gate.running) {
      main.controllers = heldControllers;
      probe("runtime", "life-retire-hold");
    } else if (phase === "life-retire-hold") {
      gateCommand("hold");
      requestCount = requests().length;
      phase = "life-retire-admit";
    } else if (phase === "life-retire-admit" && !gate.running) {
      check(main.setColor(68, 85, 102, selected), "held retirement action admitted");
      phase = "life-retire-pending";
    } else if (phase === "life-retire-pending" && requests().length > requestCount) {
      Service.loadedPlugins = ({});
      phase = "life-retire-release";
    } else if (phase === "life-retire-release" && !selected.settingsContext.current()) {
      gateCommand("release");
      phase = "life-retired";
    } else if (phase === "life-retired" && !main.isApplying && !gate.running) {
      check(requests().length === requestCount + 1, "retired direct completion cannot elevate or start next controller");
      probe("retired", "finish");
    } else if (phase === "life-nv-admit" && selected._pendingSettingsSaves === 0 && selected.settingsContext.settingsView.vibranceValue === 640.6 && selected.settingsContext.settingsView.enabled === false) {
      views[1].bar.toggle();
      phase = "life-nv-enabled";
    } else if (phase === "life-nv-enabled" && selected._pendingSettingsSaves === 0 && requests().length === requestCount + 1 && selected.settingsContext.settingsView.enabled === true) {
      var expected = Array(typedDisplay).fill("0").concat([String(typedValue)]);
      check(JSON.stringify(requests().slice(-1)[0].argv) === JSON.stringify(expected), "original QML int admission preserved for selected command");
      views[1].bar.toggle();
      phase = "life-nv-disabled";
    } else if (phase === "life-nv-disabled" && selected._pendingSettingsSaves === 0 && requests().length === requestCount + 2 && selected.settingsContext.settingsView.enabled === false) {
      probe("runtime", "life-nv-retire");
    } else if (phase === "life-nv-retire") {
      requestCount = requests().length;
      Service.loadedPlugins = ({});
      phase = "life-nv-retired";
    } else if (phase === "life-nv-retired" && !selected.settingsContext.current()) {
      check(main.toggle(selected) === false && main.applyVibrance(99, selected.settingsContext) === false, "retired selected runtime writer/physical action refuses");
      check(requests().length === requestCount, "retired NVibrant emits no endpoint");
      probe("retired", "finish");
    }
  }
  function drive() {
    check(Date.now() - phaseStarted < 18000, "finite action/native deadline");
    if (phase === "runtime" && selected.settingsReady && sibling.settingsReady && inherited.settingsReady) {
      views = [api, selected, sibling, inherited].map(context => ({
        api: context,
        bar: create("barWidget", context),
        panel: gif || hardware ? null : create("panel", context)
      }));
      phase = "initial";
    } else if (phase === "initial") {
      var name = mode === "edit" ? "initial" : mode === "reset" ? "edited" : mode === "follow" ? "reset" : boundary;
      if (!ready(name))
        return;
      if (mode === "lifetime") {
        phase = "life-prepare";
        return;
      }
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
    else if (phase === "edited-actions") {
      if (ds4) {
        const value = Qt.color(values("edited")[scope === "shared" ? 0 : 1].color);
        const rgb = [value.r, value.g, value.b].map(c => String(Math.round(c * 255)));
        check(requests().slice(-2).every(row => JSON.stringify(row.argv.slice(3)) === JSON.stringify(rgb)), "actual hardware endpoint receives selected policy");
      }
      startActions("edited", "finish");
    } else if (phase === "open-reset")
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
      api.pluginSettings[field] = gif ? 18 : ds4 ? "#556677" : nv ? 256 : true;
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
      else if (ds4)
        check(main.applyColors(selected.settingsContext) === false, "retired DS4 action refuses");
      else if (nv)
        check(main.toggle(selected) === false, "retired NVibrant action refuses");
      else
        check(main.connectTo("controlled-vpn", selected.settingsContext) === false, "retired VPN action refuses");
      actionStarted = Date.now();
      phase = "retired-check";
    } else if (phase === "retired-check" && Date.now() - actionStarted > 250) {
      check(requests().length === requestCount, "retired context cannot dispatch a new physical action");
      phase = "finish";
    } else if (phase.startsWith("life-"))
      lifetime();
    else if (phase === "action-start" || phase === "action-wait")
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
