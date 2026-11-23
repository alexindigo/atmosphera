import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins
import qs.Widgets

ShellRoot {
  id: root
  readonly property string casePath: Quickshell.env("PHA_KEYBIND_CASE")
  readonly property string scope: Quickshell.env("PHA_KEYBIND_SCOPE")
  readonly property string mode: Quickshell.env("PHA_KEYBIND_MODE")
  readonly property string boundary: Quickshell.env("PHA_KEYBIND_BOUNDARY")
  readonly property bool oldRed: Quickshell.env("PHA_KEYBIND_RED") === "1"
  property bool started: false
  property string phase: "startup"
  property double since: Date.now()
  onPhaseChanged: since = Date.now()
  property var api: null
  property var selected: null
  property var sibling: null
  property var inherited: null
  property var main: null
  property var panel: null
  property var siblingPanel: null
  property var inheritedPanel: null
  property var sharedPanel: null
  property var receipt: null
  property string afterDisk: ""
  FileView {
    id: manifest
    path: Settings.configDir + "plugins/keybind-cheatsheet/manifest.json"
    blockLoading: true
  }
  FileView {
    id: dictionary
    path: Settings.configDir + "plugins/keybind-cheatsheet/i18n/en.json"
    blockLoading: true
  }
  FileView {
    id: expectations
    path: root.casePath + "/expectations.json"
    blockLoading: true
  }
  FileView {
    id: input
    path: root.casePath + "/input.json"
    blockLoading: true
  }
  property var edits: ({})
  property var keys: []
  property int resetRow: 0
  readonly property var resetRows: ["Super", "Ctrl", "Shift", "Alt", "Mod2", "Mod3", "Mod5", "XF86", "Print", "Numeric", "Mouse", "Default", "Description"]
  Process {
    id: disk
    onExited: code => {
      if (code !== 0)
        root.fail("independent complete documents");
      else
        root.phase = root.afterDisk;
    }
  }
  PanelWindow {
    visible: true
    implicitWidth: 1400
    implicitHeight: 950
    Item {
      id: content
      width: 1400
      height: 950
    }
    NPluginSettingsPopup {
      id: popup
      screen: Quickshell.screens[0]
      onSettingsCompleted: result => root.receipt = result
    }
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("KEYBIND_ASSERT: " + phase + ": " + message);
  }
  function fail(error) {
    console.error(String(error) + "\n" + (error.stack || ""));
    Qt.exit(2);
  }
  function find(object, predicate, visited) {
    visited = visited || new Set();
    if (!object || visited.has(object))
      return null;
    visited.add(object);
    if (object && predicate(object))
      return object;
    for (var list of [object?.data, object?.children]) {
      if (!list || typeof list === "function" || typeof list.length !== "number")
        continue;
      for (var child of list) {
        var found = find(child, predicate, visited);
        if (found)
          return found;
      }
    }
    return null;
  }
  function create(entry, context) {
    var component = Qt.createComponent("file://" + api.pluginDir + "/" + api.manifest.entryPoints[entry]);
    check(component.status === Component.Ready, component.errorString());
    var item = PluginLoader.createObject("keybind-cheatsheet", entry, component, content, context, {});
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
      "keybind-cheatsheet": descriptor
    };
    Service._openSettingsOwner("keybind-cheatsheet", function (owner) {
      try {
        check(owner, "actual native owner");
        api = Service.createPluginAPI("keybind-cheatsheet", descriptor, owner, dict, dict, {});
        Service.loadedPlugins = {
          "keybind-cheatsheet": {
            api: api
          }
        };
        main = create("main", api);
        api.mainInstance = main;
        var placement = index => ({
          kind: "bar",
          list: "global",
          section: "left",
          index: index
        });
        selected = PluginInstances.apiFor("keybind-cheatsheet", placement(0));
        sibling = PluginInstances.apiFor("keybind-cheatsheet", placement(1));
        inherited = PluginInstances.apiFor("keybind-cheatsheet", placement(2));
        phase = "runtime";
      } catch (error) {
        fail(error);
      }
    });
  }
  function probe(name, next) {
    afterDisk = next;
    phase = "disk";
    disk.command = ["python3", "-B", Quickshell.env("PHA_KEYBIND_DISK"), casePath, Quickshell.env("PHA_KEYBIND_OUTPUT") + "/persisted", name];
    disk.running = true;
  }
  function expected(name, index) {
    expectations.reload();
    expectations.waitForJob();
    var doc = JSON.parse(expectations.text())[name];
    return Object.assign({}, api.manifest.metadata.defaultSettings, doc.shared, index < 0 ? {} : doc.bar.widgets.left[index].instanceSettings);
  }
  function ready(name) {
    var target = scope === "instance" ? selected : api;
    var values = expected(name, scope === "instance" ? 0 : -1);
    return keys.every(key => JSON.stringify(target.settingsView[key] ?? api.manifest.metadata.defaultSettings[key]) === JSON.stringify(values[key]));
  }
  function edit() {
    for (var key of keys) {
      var field = popup._pageApi.field(key), value = edits[key];
      var wrapper = find(popup.settingsPage, item => item.field === field);
      check(wrapper, "actual field chrome " + key);
      var control;
      if (key === "bindOverrides") {
        control = find(wrapper, item => item.text === api.tr("settings.clear-overrides") && item.clicked !== undefined);
        check(control, "actual clear overrides action");
        control.clicked();
      } else if (key.startsWith("keyColor") || key.startsWith("keyText") || key === "descriptionTextColor" || key.startsWith("keyLabelMod")) {
        control = find(wrapper, item => item.bgPasted !== undefined);
        check(control, "actual color/label child " + key);
        if (key.startsWith("keyLabelMod"))
          control.labelEdited(value);
        else {
          var isText = key.startsWith("keyText") || key === "descriptionTextColor";
          var pill = find(control, item => item.pasteRequested !== undefined && item.textMode === isText);
          check(pill, "actual injected color pill " + key);
          pill.pasteRequested(value);
        }
      } else if (typeof value === "boolean") {
        control = find(wrapper, item => item.toggled !== undefined);
        check(control, "actual toggle " + key);
        control.toggled(value);
      } else if (key === "columnCount" || key === "hyprlandParserMode") {
        control = find(wrapper, item => item.selected !== undefined);
        check(control, "actual combo " + key);
        control.selected(String(value));
      } else if (key === "workspaceSplitThreshold") {
        control = find(wrapper, item => item.valueModified !== undefined);
        check(control, "actual spinbox");
        control.valueModified(value);
      } else {
        control = find(wrapper, item => item.editCommitted !== undefined);
        check(control, "actual input " + key);
        control.text = String(value);
        control.editCommitted();
      }
    }
  }
  function open(next) {
    check(scope === "shared" ? popup.openPluginSettings(api.manifest, "settings") : popup.openInstanceSettings(api.manifest, selected, "settings"), "actual scoped page opens");
    phase = next;
  }
  function apply(next) {
    receipt = null;
    check(popup.applySettings(), "native Apply");
    phase = next;
  }
  function accepted() {
    if (!receipt || popup.busy)
      return false;
    check(receipt.status === "saved" && receipt.refreshState === "current", "native Apply failed: " + (receipt.error?.code ?? receipt.status));
    check(receipt.runtimeRead?.status === "observed", "selected runtime reader observed Apply");
    return true;
  }
  function consumerName(name, index) {
    var path = expected(name, index).niriConfigPath;
    return path === casePath + "/selected.kdl" ? "selected" : path === casePath + "/following.kdl" ? "following" : path === casePath + "/sibling.kdl" ? "sibling" : path === casePath + "/base.kdl" ? "base" : "reference";
  }
  function hasBind(view, name) {
    return view.rawCategories.some(cat => cat.binds.some(bind => bind.desc === name + " bind"));
  }
  function consumers(name) {
    var index = scope === "instance" ? 0 : -1, values = expected(name, index), label = consumerName(name, index);
    if (oldRed) {
      if (main.isCurrentlyParsing || Date.now() - since < 1000)
        return;
      check(hasBind(panel, label), "original parser consumes saved selected source");
    }
    check(panel.settingsConsumer === main.clientFor(scope === "instance" ? selected : api), "selected entries share exact parser");
    if (!hasBind(panel, label) || panel.columnItems.length !== values.columnCount || !panel.columnItems.some(column => column.some(item => item.desc === label + " bind")))
      return;
    check(find(panel, item => item.text === label + " bind"), "actual rendered selected bind Text");
    check(panel.settingsConsumer !== main.clientFor(sibling) && main.clientFor(selected) === main.settingsConsumerFor(selected.settingsContext), "contexts separate and views share");
    for (var pair of [[siblingPanel, 1], [inheritedPanel, 2], [sharedPanel, -1]]) {
      if (!hasBind(pair[0], consumerName(name, pair[1])))
        return;
      check(pair[0].settingsConsumer === main.clientFor(pair[1] < 0 ? api : pair[1] === 1 ? sibling : inherited), "other entries retain exact client");
    }
    check(panel.settingsWidth === values.windowWidth && panel.settingsHeight === values.windowHeight && panel.autoHeight === values.autoHeight && panel.columnCount === values.columnCount, "actual selected geometry policy");
    check(panel.splitWorkspaces === values.splitLargeWorkspaceCategory && panel.workspaceSplitThreshold === values.workspaceSplitThreshold, "selected split policy");
    for (var key of keys) {
      if (key.startsWith("keyColor") || key.startsWith("keyText")) {
        var suffix = key.replace(/^keyColor|^keyText/, ""), token = suffix === "Default" ? "S" : suffix === "Numeric" ? "1" : suffix === "XF86" ? "XF86Mystery" : suffix === "Mouse" ? "MOUSE:272" : suffix;
        var color = key.startsWith("keyColor") ? panel.getKeyColor(token) : panel.getKeyTextColor(token);
        if (values[key])
          check(String(color).toLowerCase() === values[key].toLowerCase(), "selected color projection " + key);
      } else if (key.startsWith("keyLabelMod"))
        check(panel.getKeyLabel(key.slice(-4)) === (values[key] || key.slice(-4)), "selected label " + key);
    }
    var superText = find(panel, item => item.text === "Super");
    check(superText && String(superText.color).toLowerCase() === String(panel.getKeyTextColor("Super")).toLowerCase(), "actual key child foreground");
    check(String(superText.parent.color).toLowerCase() === String(panel.getKeyColor("Super")).toLowerCase(), "actual key badge background");
    var description = find(panel, item => item.text === label + " bind");
    check(String(description.color).toLowerCase() === String(panel.descriptionTextColor).toLowerCase(), "actual description child color");
    check(!hasBind(panel, "legacy unqualified"), "unqualified cache not attributed");
    console.log("KEYBIND_NATIVE: PASS " + scope + " " + mode + " " + boundary);
    Qt.exit(0);
  }
  function drive() {
    check(Date.now() - since < 18000, phase === "row-reset" ? "actual row Reset removes selected overrides" : "finite native phase");
    if (phase === "runtime" && selected.settingsReady && sibling.settingsReady && inherited.settingsReady) {
      var reader = (scope === "instance" ? selected : api).settingsReadOwner;
      check(typeof reader?.readProjection?.synchronize === "function", "selected reader lacks ConfigQml readProjection.synchronize; load the qualified native module");
      input.waitForJob();
      var data = JSON.parse(input.text());
      edits = data.edits;
      keys = data.keys;
      panel = create("panel", scope === "instance" ? selected : api);
      siblingPanel = create("panel", sibling);
      inheritedPanel = create("panel", inherited);
      sharedPanel = create("panel", api);
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
      check(!popup.dirty, "no construction intent");
      var sourceBeforeDraft = panel.settingsConsumer?.sourceKey;
      edit();
      if (!oldRed && Quickshell.env("PHA_KEYBIND_READER_CONTROL") !== "1") {
        var runtime = scope === "shared" ? api : selected;
        check(runtime.settingsView.keyColorSuper === edits.keyColorSuper, "color preview is active");
        check(runtime.settingsView.niriConfigPath === edits.niriConfigPath && runtime.pluginSettings.niriConfigPath !== edits.niriConfigPath, "preview contains an unapplied parser path");
        check((scope === "shared" ? main.clientFor(api) : main.clientFor(selected)).sourceKey === sourceBeforeDraft, "color preview must not change parser source before Apply");
      }
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
      if (resetRow < resetRows.length) {
        var suffix = resetRows[resetRow], colorKey = suffix === "Description" ? "descriptionTextColor" : "keyColor" + suffix;
        var wrapper = find(popup.settingsPage, item => item.field === popup._pageApi.field(colorKey));
        var row = find(wrapper, item => item.resetRequested !== undefined);
        check(row, "actual color Reset row");
        row.resetRequested();
        phase = "row-reset";
      } else {
        var general = find(popup.settingsPage, item => item.text === api.tr("settings.reset-defaults") && item.clicked !== undefined);
        check(general, "actual general Reset");
        general.clicked();
        phase = "general-reset";
      }
    } else if (phase === "row-reset" && !popup.busy) {
      var suffix = resetRows[resetRow], group = suffix === "Description" ? ["descriptionTextColor"] : ["keyColor" + suffix, "keyText" + suffix];
      if (suffix.startsWith("Mod"))
        group.push("keyLabel" + suffix);
      if (!group.every(key => popup._pageApi.field(key).pendingIntent === "reset"))
        return;
      resetRow++;
      phase = "reset-page";
    } else if (phase === "general-reset" && !popup.busy) {
      if (!keys.slice(0, 14).every(key => popup._pageApi.field(key).pendingIntent === "reset"))
        return;
      var wrapper = find(popup.settingsPage, item => item.field === popup._pageApi.field("bindOverrides"));
      var resetButton = find(wrapper, item => item.text === I18n.tr("common.reset") && item.clicked !== undefined);
      check(resetButton, "actual compound field Reset");
      resetButton.clicked();
      phase = "reset-staging";
    } else if (phase === "reset-staging" && !popup.busy && keys.every(key => popup._pageApi.field(key).pendingIntent === "reset"))
      probe("reset-staged", "reset-apply");
    else if (phase === "reset-apply")
      apply("reset-applied");
    else if (phase === "reset-applied" && accepted() && ready("reset"))
      probe("reset", "reset-consumers");
    else if (phase === "reset-consumers")
      consumers("reset");
    else if (phase === "change-base") {
      var next = JSON.parse(input.text()).following;
      for (var key of keys)
        api.pluginSettings[key] = next[key];
      phase = "base-saving";
      api.saveSettings(result => {
        try {
          check(result.status === "saved", "native following publication");
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
