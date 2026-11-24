// P001 candidate witness: real runtime registry and Desktop Widgets list gear,
// actual Todo Settings/Main/Desktop, selected native persistence and cold read.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Modules.MainScreen
import qs.Modules.Panels.Settings.Tabs
import qs.Services.Plugins
import qs.Services.UI
import qs.Widgets

ShellRoot {
  id: root
  property bool started: false
  property string phase: "opening"
  property var api: null
  property var instanceApi: null
  property var main: null
  property var desktop: null
  property var popup: null
  property var completion: null
  property int closes: 0
  property int route: 0
  property int stage: 0
  property var editedInput: null
  property var afterDisk: null
  property var failedPage: null
  property var failedEditor: null
  readonly property bool cold: Quickshell.env("PHA_TODO_COLD") === "1"
  readonly property var placement: ({
                                      kind: "desktop",
                                      screenName: Quickshell.screens[0].name,
                                      index: 0
                                    })
  readonly property var legacy: ({
                                   todos: [
                                     {
                                       id: 91,
                                       text: "legacy task",
                                       completed: false,
                                       pageId: 0,
                                       priority: "medium",
                                       details: ""
                                     }
                                   ],
                                   pages: [
                                     {
                                       id: 0,
                                       name: "Legacy"
                                     }
                                   ],
                                   current_page_id: 0,
                                   count: 1,
                                   completedCount: 0,
                                   opaque: {
                                     keep: "legacy"
                                   }
                                 })

  FileView {
    id: manifestFile
    path: Settings.configDir + "plugins/todo/manifest.json"
    blockLoading: true
    printErrors: false
  }
  Process {
    id: typing
    onExited: function (code) {
      if (code !== 0)
        root.fail("real keyboard input failed");
    }
  }
  Component {
    id: viewFactory
    PluginView {
      asynchronous: false
    }
  }
  Process {
    id: disk
    stdout: StdioCollector {
      onStreamFinished: console.log(text)
    }
    stderr: StdioCollector {
      onStreamFinished: {
        if (text)
          console.error(text);
      }
    }
    onExited: function (code) {
      if (code !== 0) {
        root.fail("independent persisted endpoint refused");
        return;
      }
      var next = root.afterDisk;
      root.afterDisk = null;
      next();
    }
  }
  Process {
    id: permissions
    onExited: function (code) {
      if (code !== 0) {
        root.fail("permission fixture failed");
        return;
      }
      root.completion = null;
      root.check(root.popup.applySettings(), "native Apply after permission boundary");
      root.phase = root.phase === "make-unwritable" ? "failed-apply" : "retry";
    }
  }
  PopupMenuWindow {
    id: host
    shellScreen: Quickshell.screens[0]
    // The fixture starts without a human click granting OnDemand seat focus.
    // Capture keyboard focus explicitly; production focus policy is not a gate
    // claimed by this native preference/consumer witness.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
  }
  PanelWindow {
    id: gearHost
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    visible: false
    implicitWidth: 1280
    implicitHeight: 800
    Loader {
      id: tabLoader
      active: false
      anchors.fill: parent
      sourceComponent: Component {
        DesktopWidgetsTab {}
      }
    }
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("TODO_HOST_ASSERT: " + message);
  }
  function fail(error) {
    console.error(String(error) + "\n" + (error.stack || ""));
    Qt.exit(2);
  }
  function construct(entry, parent, context) {
    var url = "file://" + api.pluginDir + "/" + api.manifest.entryPoints[entry];
    var component = Qt.createComponent(url);
    check(component.status === Component.Ready, component.errorString());
    // This consumer leg supplies known inherited desktop inputs at creation.
    // The separate loader matrix retains its root/late-context contract; the
    // old DraggableDesktopWidget null-context diagnostic is not tested here.
    var item = entry === "desktopWidget" ? component.createObject(parent, Object.assign({
                                                                                          pluginApi: instanceApi
                                                                                        }, context)) : PluginLoader.createObject("todo", entry, component, parent, api, context);
    check(item !== null, "real " + entry + " creation");
    return item;
  }
  function contents() {
    check(main.rawTodos.length === 2 && main.rawTodos[0].id === 1, "shared Main tasks remain");
    check(desktop.rawTodos.length === 1 && desktop.rawTodos[0].id === 91, "legacy desktop tasks remain");
    check(api.pluginSettings.pages.length === 2 && api.pluginSettings.current_page_id === 7, "shared pages remain");
    check(instanceApi.pluginSettings.pages[0].name === "Legacy" && instanceApi.pluginSettings.count === 1 && instanceApi.pluginSettings.completedCount === 0, "legacy pages/counters remain");
  }
  function boundaries() {
    var pageApi = popup._pageApi;
    check(pageApi.runtimeContext === instanceApi.settingsContext && pageApi.runtimeContext !== api.settingsContext, "one stable selected runtime context per API");
    check(Object.isFrozen(pageApi.capability) && Object.isFrozen(pageApi.pluginSettings), "page receives frozen capabilities and owned read projection");
    var denied = false;
    try {
      pageApi.pluginSettings = {
        todos: []
      };
    } catch (error) {
      denied = true;
    }
    check(denied, "whole generic namespace assignment refused");
    var projection = pageApi.pluginSettings;
    try {
      projection.todos[0].text = "projection mutation";
      projection.todos.push({
                              id: 92
                            });
    } catch (error) {}
    // QV4 can grow a frozen array's local length before push throws. The agreed
    // contract is alias isolation, not a new GUI store: even that owned display
    // mutation cannot enter the native namespace or a later Apply.
    check(popup._editor.values.todos[0].text === "legacy task" && popup._editor.values.todos.length === 1 && pageApi.capability.readSettings().todos.length === 1 && instanceApi.pluginSettings.todos.length === 1 && !popup._editor.dirty, "owned compound display mutation cannot reach native publication");
    var field = pageApi.field("priorityColors");
    check(field === pageApi.field("priorityColors"), "stable field handles");
    var colors = field.value;
    colors.high = "foreign projection";
    check(field.value.high !== "foreign projection" && !popup._editor.dirty, "field compound alias isolated");
    var url = "file://" + api.pluginDir + "/" + api.manifest.entryPoints.settings;
    denied = false;
    try {
      PluginLoader.initialProperties("settings", url, api, {});
    } catch (error) {
      denied = String(error).indexOf("settings-editor-api-required") !== -1;
    }
    check(denied, "Loader.setSource caller cannot obtain runtime initial properties");
    var component = Qt.createComponent(url);
    check(PluginLoader.createObject("todo", "settings", component, host.contentItem, api, {}) === null, "direct generic creation refuses runtime API before page construction");
    var view = viewFactory.createObject(host.contentItem, {
                                          pluginKey: "todo",
                                          entryPoint: "settings",
                                          url: url,
                                          api: api
                                        });
    check(view.failed && view.item === null, "PluginView refuses runtime API before page construction");
    view.destroy();
    Service.clearPluginError("todo");
  }
  function findPopup(object) {
    return find(object, function (item) {
      return typeof item.openInstanceSettings === "function" && typeof item.applySettings === "function";
    });
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
  function openRoute() {
    completion = null;
    if (route === 0) {
      check(DesktopWidgetRegistry.openWidgetSettings(Quickshell.screens[0], 0, "plugin:todo", {
                                                       id: "plugin:todo"
                                                     }, function () {
                                                       root.closes++;
                                                     }) !== false, "runtime registry request admitted");
      popup = DesktopWidgetRegistry.currentSettingsDialog;
    } else {
      gearHost.visible = true;
      tabLoader.active = true;
      tabLoader.item._openInstanceSettings(api.manifest, "settings", placement.screenName, 0);
      popup = findPopup(tabLoader.item);
    }
    check(popup !== null, "same generic popup selected by actual route " + route);
    popup.settingsCompleted.connect(function (result) {
      root.completion = result;
    });
    phase = "page";
  }
  function exerciseEarlyDesktopClose() {
    var screen = Quickshell.screens[0];
    check(DesktopWidgetRegistry.openWidgetSettings(screen, 0, "plugin:todo", {
                                                     id: "plugin:todo"
                                                   }) !== false, "early desktop opening admitted");
    var opening = DesktopWidgetRegistry.currentSettingsDialog;
    check(opening && !opening.visible && opening._editor, "desktop adopted a not-yet-shown editor");
    var host = PanelService.getPopupMenuWindow(screen);
    check(host.popupContentItem === opening && host.close(), "host accepts Close during opening");
    check(host.popupContentItem === null && DesktopWidgetRegistry.currentSettingsDialog === null, "early Close clears both presentation owners");
    console.log("PLUGIN_SETTINGS_TODO: EARLY_DESKTOP_CLOSE_RELEASED");
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    manifestFile.waitForJob();
    var manifest = JSON.parse(manifestFile.text());
    Registry.installedPlugins = {
      todo: manifest
    };
    Service._openSettingsOwner("todo", function (owner) {
      try {
        check(owner !== null, "native owner");
        api = Service.createPluginAPI("todo", manifest, owner, {}, {}, {});
        Service.loadedPlugins = {
          todo: {
            api: api
          }
        };
        main = construct("main", root, {});
        api.mainInstance = main;
        if (cold) {
          instanceApi = PluginInstances.apiFor("todo", placement);
          phase = "runtime";
          return;
        }
        Settings.data.desktopWidgets.monitorWidgets = [
              {
                name: placement.screenName,
                widgets: [
                  {
                    id: "plugin:todo",
                    tag: "keep",
                    instanceSettings: Object.assign({}, legacy, {
                                                      showCompleted: false,
                                                      isExpanded: true
                                                    })
                  },
                  {
                    id: "plugin:todo"
                  }
                ]
              }
            ];
        Settings.saveSelected([["desktopWidgets", "monitorWidgets"]], function (receipt) {
          try {
            check(receipt.status !== "failed", "placement persisted");
            instanceApi = PluginInstances.apiFor("todo", placement);
            phase = "runtime";
          } catch (error) {
            fail(error);
          }
        });
      } catch (error) {
        fail(error);
      }
    });
  }
  function drive() {
    if (phase === "runtime" && instanceApi.settingsReady) {
      desktop = construct("desktopWidget", host.contentItem, {
                            screen: Quickshell.screens[0],
                            widgetData: {
                              id: "plugin:todo"
                            },
                            widgetIndex: 0
                          });
      contents();
      if (cold) {
        check(instanceApi.pluginSettings.showCompleted === api.pluginSettings.showCompleted, "cold config Reset inherits");
        console.log("PLUGIN_SETTINGS_TODO: COLD_PASS");
        Qt.exit(0);
        return;
      }
      exerciseEarlyDesktopClose();
      openRoute();
    } else if (phase === "page" && popup.opened && popup.settingsPage) {
      contents();
      check(popup._pageApi.apiRole === "settings-editor" && popup._pageApi.scopeKind === "instance", "instance editor role");
      check(popup._pageApi.editor === undefined && popup._pageApi.base === undefined && popup._pageApi.pluginSettings.todos[0].id === 91, "read-only page without native/live writer");
      check(!popup.dirty && !popup._editor.dirty, "open submits no intent");
      if (stage === 0) {
        if (route === 0)
          check(popup.undisplayedOverrideFields.some(function (field) {
            return field.key === "isExpanded";
          }), "host summary includes configuration absent from the page");
        boundaries();
        check(popup.requestClose(), "untouched Close does not save");
        observe("untouched", function () {
          root.phase = "closed";
        });
      } else if (stage === 1) {
        prepareTyping();
      } else if (stage === 2) {
        if (route === 0) {
          var hiddenRow = find(popup.contentItem, function (item) {
            return item.modelData === "isExpanded" && item.field?.key === "isExpanded";
          });
          check(!!hiddenRow, "host-owned hidden override row rendered");
          var reset = find(hiddenRow, function (item) {
            return typeof item.clicked === "function" && item.text === I18n.tr("common.reset");
          });
          check(!!reset, "host-owned hidden override Reset control");
          reset.clicked();
          check(popup._pageApi.field("isExpanded").pendingIntent === "reset" && instanceApi.pluginSettings.isExpanded, "summary Reset stages native intent without publication");
        }
        prepareTyping();
      } else if (stage === 3) {
        var field = popup._pageApi.field("exportPath");
        check(field.overridden && field.reset() && field.value === field.inheritedValue, "field Reset immediately presents inherited value");
        check(popup.applySettings(), "field Reset Apply requested");
        phase = "field-reset";
      } else if (stage === 4) {
        check(popup._pageApi.field("exportFormat").set("json"), "explicit field retained through IO failure");
        failedPage = popup.settingsPage;
        failedEditor = popup._editor;
        permissions.command = ["chmod", "500", Settings.configDir + "settings"];
        phase = "make-unwritable";
        permissions.running = true;
      } else if (stage === 5) {
        check(popup.resetInstanceSettings(), "declared config Reset requested");
        phase = "reset";
      }
    } else if (phase === "focus-input") {
      editedInput.forceActiveFocus();
      editedInput.selectAll();
      check(editedInput.activeFocus && editedInput.selectionEnd === editedInput.text.length, "native field selected before real typing");
      check(Quickshell.env("PHA_INPUT_INJECTOR") !== "", "task-owned input injector required");
      typing.command = [Quickshell.env("PHA_INPUT_INJECTOR"), "--", "/synthetic/export"];
      typing.running = true;
      phase = "typing";
    } else if (phase === "typing" && !typing.running && editedInput.text === "/synthetic/export") {
      if (stage === 1) {
        check(!popup.requestClose() && popup.discardPending, "dirty Close refuses");
        popup.keepEditing();
        check(popup.settingsPage !== null && popup.visible, "Keep retains actual page");
        check(!instanceApi.pluginSettings.exportEmptySections, "staging does not publish");
        check(popup.confirmDiscard(), "explicit discard admitted");
        observe("discard", function () {
          root.phase = "closed";
        });
      } else if (stage === 2) {
        check(popup._pageApi.field("exportEmptySections").set(true), "config intent for Apply");
        check(popup.applySettings(), "single native Apply requested");
        phase = "apply";
      }
    } else if (phase === "apply" && completion && instanceApi.pluginSettings.exportEmptySections && instanceApi.pluginSettings.exportPath === "/synthetic/export") {
      check(completion.status === "saved" && completion.refreshState === "current" && !popup.saveFailed, "current selected Apply");
      contents();
      observe("apply", function () {
        root.check(root.popup.requestClose(), "Close after acknowledged Apply");
        root.phase = "closed";
      });
    } else if (phase === "field-reset" && completion && instanceApi.pluginSettings.exportPath === api.pluginSettings.exportPath) {
      check(completion.status === "saved" && completion.refreshState === "current" && !popup._pageApi.field("exportPath").overridden, "field Reset acknowledged and recaptured");
      check(instanceApi.pluginSettings.exportEmptySections, "field Reset preserves unrelated configuration");
      contents();
      observe("field-reset", function () {
        root.check(root.popup.requestClose(), "Close after field Reset");
        root.phase = "closed";
      });
    } else if (phase === "failed-apply" && completion && !popup.busy) {
      check(completion.status === "failed" && popup.saveFailed, "real destination IO failure is not acknowledged");
      check(popup.settingsPage === failedPage && popup._editor === failedEditor && popup._pageApi.field("exportFormat").value === "json", "failed input/page/editor retained");
      check(!popup.requestClose() && popup.discardPending, "failed Close requires explicit discard");
      popup.keepEditing();
      observe("failed", function () {
        root.phase = "make-writable";
        permissions.command = ["chmod", "700", Settings.configDir + "settings"];
        permissions.running = true;
      });
    } else if (phase === "retry" && completion && !popup.busy && instanceApi.pluginSettings.exportFormat === "json") {
      check(completion.status === "saved" && completion.refreshState === "current" && !popup.saveFailed, "same-editor Retry persisted current input");
      check(popup.settingsPage === failedPage && popup._editor === failedEditor, "Retry retains selected capture");
      contents();
      observe("retry", function () {
        root.check(root.popup.requestClose(), "Close after Retry");
        root.phase = "closed";
      });
    } else if (phase === "reset" && completion && !instanceApi.pluginSettings.exportEmptySections && instanceApi.pluginSettings.showCompleted) {
      check(completion.status === "saved" && completion.refreshState === "current" && !popup.saveFailed, "configuration Reset acknowledged");
      contents();
      observe("reset", function () {
        root.check(root.popup.requestClose(), "Close after config Reset");
        root.phase = "closed";
      });
    } else if (phase === "closed" && (!popup || !popup.visible)) {
      contents();
      stage++;
      if (stage === 6) {
        stage = 0;
        route++;
      }
      if (route === 2) {
        check(closes === 6, "unused field capture cleanup exactly once per runtime presentation");
        console.log("PLUGIN_SETTINGS_TODO: NATIVE_OPERATIONS_COMPLETE");
        Qt.exit(0);
        return;
      }
      Qt.callLater(openRoute);
      phase = "between";
    }
  }
  function observe(operation, next) {
    phase = "independent-disk";
    afterDisk = next;
    disk.command = ["python3", "-B", Quickshell.env("PHA_TODO_DISK_PROBE"), operation, String(route), Settings.configDir];
    disk.running = true;
  }
  function prepareTyping() {
    var control = find(popup.settingsPage, function (item) {
      return item.label === api.tr("settings.export_path.label") && typeof item.inputEditingFinished === "function";
    });
    check(control !== null, "actual Todo export field");
    var input = find(control, function (item) {
      return typeof item.commitEdit === "function" && item.inputItem !== undefined;
    });
    check(input !== null, "native buffered field input");
    editedInput = input.inputItem;
    phase = "focus-input";
  }
  Connections {
    target: Settings
    function onSettingsLoaded() {
      root.begin();
    }
  }
  Timer {
    interval: 60
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
    interval: 45000
    running: true
    onTriggered: root.fail("watchdog " + phase + " route=" + route + " stage=" + stage + " text=" + (editedInput ? editedInput.text : "none") + " focus=" + (editedInput ? editedInput.activeFocus : false) + " runtimeHost=" + host.visible + " gearHost=" + gearHost.visible)
  }
  Component.onCompleted: begin()
}
