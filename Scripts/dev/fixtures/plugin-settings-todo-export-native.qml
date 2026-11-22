// Actual Todo page intent and Panel export with independent native documents.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins
import qs.Widgets

ShellRoot {
  id: root
  readonly property string scope: Quickshell.env("PHA_TODO_EXPORT_SCOPE")
  readonly property string mode: Quickshell.env("PHA_TODO_EXPORT_MODE")
  readonly property string boundary: Quickshell.env("PHA_TODO_EXPORT_BOUNDARY")
  readonly property string casePath: Quickshell.env("PHA_TODO_EXPORT_CASE")
  readonly property bool oldRed: Quickshell.env("PHA_TODO_EXPORT_RED") === "1"
  property bool started: false
  property string phase: "startup"
  property double phaseStarted: Date.now()
  onPhaseChanged: phaseStarted = Date.now()
  property var api: null
  property var selected: null
  property var main: null
  property var panel: null
  property var receipt: null
  property string afterDisk: ""
  property string diskBoundary: ""
  property string exportBoundary: ""
  property string afterExport: ""
  property var displayList: null
  FileView {
    id: manifestFile
    path: Settings.configDir + "plugins/todo/manifest.json"
    blockLoading: true
  }
  FileView {
    id: dictionaryFile
    path: Settings.configDir + "plugins/todo/i18n/en.json"
    blockLoading: true
  }
  FileView {
    id: expectedFile
    path: root.casePath + "/expectations.json"
    blockLoading: true
  }
  Process {
    id: disk
    onExited: code => {
      if (code !== 0)
        root.fail("complete independent Todo documents: " + root.diskBoundary);
      else
        root.phase = root.afterDisk;
    }
  }
  PanelWindow {
    visible: true
    implicitWidth: 1200
    implicitHeight: 950
    Item {
      id: content
      width: 1200
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
      throw new Error("TODO_EXPORT_ASSERT: " + scope + "/" + mode + "/" + phase + ": " + message);
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
    var item = PluginLoader.createObject("todo", entry, component, content, context, {});
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
    Registry.installedPlugins = {
      todo: manifest
    };
    Service._openSettingsOwner("todo", function (owner) {
      try {
        check(owner !== null, "actual native owner");
        api = Service.createPluginAPI("todo", manifest, owner, dictionary, dictionary, {});
        Service.loadedPlugins = {
          todo: {
            api: api
          }
        };
        main = create("main", api);
        api.mainInstance = main;
        selected = PluginInstances.apiFor("todo", {
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
  function values(name) {
    expectedFile.reload();
    expectedFile.waitForJob();
    var expected = JSON.parse(expectedFile.text())[name];
    return Object.assign({}, api.manifest.metadata.defaultSettings, expected.shared, scope === "instance" ? expected.bar.widgets.left[0].instanceSettings : {});
  }
  function ready(name) {
    var expected = values(name), context = scope === "instance" ? selected : api;
    return ["exportPath", "exportFormat", "exportEmptySections", "showCompleted"].every(key => JSON.stringify(context.pluginSettings[key]) === JSON.stringify(expected[key]) && JSON.stringify(context.settingsContext.settingsView[key]) === JSON.stringify(expected[key]));
  }
  function probe(name, next) {
    afterDisk = next;
    diskBoundary = name;
    phase = "disk";
    disk.command = ["python3", "-B", Quickshell.env("PHA_TODO_EXPORT_DISK"), casePath, Quickshell.env("PHA_TODO_EXPORT_OUTPUT") + "/persisted", name];
    disk.running = true;
  }
  function open(next) {
    check(scope === "shared" ? popup.openPluginSettings(api.manifest, "settings") : popup.openInstanceSettings(api.manifest, selected, "settings"), "actual scoped page opens");
    phase = next;
  }
  function edit() {
    var path = find(popup.settingsPage, item => item.label === api.tr("settings.export_path.label") && item.inputEditCommitted !== undefined);
    var format = find(popup.settingsPage, item => item.label === api.tr("settings.export_format.label") && item.currentKey !== undefined);
    var empty = find(popup.settingsPage, item => item.label === api.tr("settings.export_empty_sections.label") && item.toggled !== undefined);
    var completed = find(popup.settingsPage, item => item.label === api.tr("settings.show_completed.label") && item.toggled !== undefined);
    check(path && format && empty && completed, "actual export and display controls");
    path.text = casePath + "/export-edited";
    path.inputEditCommitted();
    format.selected("json");
    empty.toggled(true);
    completed.toggled(false);
  }
  function accepted() {
    return receipt && !popup.busy && receipt.status === "saved" && receipt.refreshState === "current";
  }
  function apply(next) {
    receipt = null;
    check(popup.applySettings(), "native Apply");
    phase = next;
  }
  function doExport(name, next) {
    exportBoundary = name;
    afterExport = next;
    phase = "display";
  }
  function exportDisplayed() {
    var expected = values(exportBoundary), visibleTodos = expected.todos.filter(todo => todo.pageId === expected.current_page_id && (expected.showCompleted || !todo.completed));
    check(panel.showCompleted === expected.showCompleted && panel.filteredTodosModel.count === visibleTodos.length, "actual Panel selected completed filter");
    displayList = find(panel, item => item.model === panel.filteredTodosModel && typeof item.itemAtIndex === "function");
    if (!displayList || visibleTodos.some((todo, index) => !displayList.itemAtIndex(index)))
      return;
    for (var todo of visibleTodos)
      check(find(panel, item => item.text === todo.text && item.font !== undefined && item.elide !== undefined && item.visible), "actual Panel task Text uses selected filtered content");
    if (!expected.showCompleted)
      for (var hidden of expected.todos.filter(todo => todo.completed))
        check(!find(panel, item => item.text === hidden.text && item.font !== undefined && item.elide !== undefined && item.visible), "completed task Text is not rendered");
    console.log("TODO_EXPORT_DISPLAY " + JSON.stringify({
                                                          boundary: exportBoundary,
                                                          showCompleted: panel.showCompleted,
                                                          texts: visibleTodos.map(todo => todo.text)
                                                        }));
    var button = find(panel, item => item.text === api.tr("panel.header.export_button") && item.clicked !== undefined);
    check(button, "actual Panel export button");
    button.clicked();
    phase = "exporting";
  }
  function drive() {
    check(Date.now() - phaseStarted < 18000, "finite operation deadline");
    if (phase === "runtime" && selected.settingsReady && !api._pendingSettingsSaves) {
      panel = create("panel", scope === "instance" ? selected : api);
      phase = "initial";
    } else if (phase === "initial") {
      var name = mode === "edit" ? "initial" : mode === "reset" ? "edited" : mode === "follow" ? "reset" : boundary;
      if (!ready(name))
        return;
      if (mode === "cold")
        doExport(boundary, "finish");
      else if (mode === "edit")
        probe("initial", "open-discard");
      else if (mode === "follow")
        phase = "change-base";
      else
        open("reset-page");
    } else if (phase === "open-discard")
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
      probe("edited", "edited-export");
    else if (phase === "edited-export")
      doExport("edited", "finish");
    else if (phase === "reset-page" && popup.opened && popup.settingsPage && !popup.busy) {
      check(popup._pageApi.resetFields(["exportPath", "exportFormat", "exportEmptySections", "showCompleted"]), "one native multi-field staged Reset");
      phase = "reset-staging";
    } else if (phase === "reset-staging" && !popup.busy && ["exportPath", "exportFormat", "exportEmptySections", "showCompleted"].every(key => popup._pageApi.field(key).pendingIntent === "reset")) {
      probe("reset-staged", "reset-apply");
    } else if (phase === "reset-apply")
      apply("reset-applied");
    else if (phase === "reset-applied" && accepted() && ready("reset"))
      probe("reset", "reset-export");
    else if (phase === "reset-export")
      doExport("reset", "finish");
    else if (phase === "change-base") {
      api.pluginSettings.exportFormat = "json";
      api.pluginSettings.exportPath = casePath + "/export-following";
      phase = "base-saving";
      api.saveSettings(function (result) {
        try {
          check(result.status === "saved", "native shared propagation");
          phase = "base-changed";
        } catch (error) {
          fail(error);
        }
      });
    } else if (phase === "base-changed" && ready("following"))
      probe("following", "following-export");
    else if (phase === "following-export")
      doExport("following", "finish");
    else if (phase === "display")
      exportDisplayed();
    else if (phase === "exporting") {
      var process = find(main, item => item.command !== undefined && item.running !== undefined);
      if (!process || process.running || !main.currentExportPath)
        return;
      var expected = values(exportBoundary);
      check(main.currentExportPath.startsWith(expected.exportPath.replace("~", Quickshell.env("HOME")) + "/") && main.currentExportPath.endsWith(expected.exportFormat === "json" ? ".json" : ".md"), oldRed ? "original Panel export uses saved selected policy" : "Panel export uses selected path and format");
      console.log("TODO_EXPORT_OUTPUT " + JSON.stringify({
                                                           boundary: exportBoundary,
                                                           path: main.currentExportPath,
                                                           format: expected.exportFormat,
                                                           empty: expected.exportEmptySections
                                                         }));
      phase = afterExport;
    } else if (phase === "finish")
      finish();
  }
  function finish() {
    console.log("TODO_EXPORT_NATIVE: PASS " + scope + " " + mode + " " + boundary);
    Qt.exit(0);
  }
  Connections {
    target: Settings
    function onSettingsLoaded() {
      root.begin();
    }
  }
  Timer {
    interval: 50
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
