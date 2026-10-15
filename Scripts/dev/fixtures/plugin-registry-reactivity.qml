// Plugin registry reactivity probe (M09). Runs as the qs entry of a disposable
// shell copy made by plugin-registry-reactivity.py, which also writes the tiny
// widget component next to it (plugin-registry-reactivity-widget.qml).
//
// Bindings read each registry's own public lookup for the test id. The probe
// then drives the real register/unregister functions through four phases:
// cold, registered, unregistered, registered again. After each phase it
// prints one PLUGIN_REGISTRY_REACTIVITY|<json> line per registry, plus one for
// the real BarWidgetLoader instance for the same id. Afterwards it drives the
// real ControlCenterWidgetLoader for the same id through an unrelated register
// and unregister (the loaded instance must survive) and through its own
// unregister and re-register (the instance must unload and load again).
import QtQuick
import Quickshell
import qs.Modules.Bar.Extras
import qs.Modules.Panels.ControlCenter
import qs.Services.Plugins
import qs.Services.UI

Item {
  id: root

  readonly property string pluginId: "test:x"
  readonly property string widgetKey: "plugin:test:x"
  readonly property string iconName: "m09-test-icon"
  readonly property var phaseNames: ["cold", "registered", "unregistered", "registered-again"]
  property int tick: 0

  readonly property var widgetComponent: Qt.createComponent(Qt.resolvedUrl("plugin-registry-reactivity-widget.qml"))

  // The bindings under test: each reads its registry's public lookup.
  readonly property bool barBinding: BarWidgetRegistry.hasWidget(root.widgetKey)
  readonly property bool controlCenterBinding: ControlCenterWidgetRegistry.hasWidget(root.widgetKey)
  readonly property bool desktopBinding: DesktopWidgetRegistry.hasWidget(root.widgetKey)
  readonly property bool launcherBinding: LauncherProviderRegistry.hasProvider(root.widgetKey)
  readonly property bool iconBinding: IconRegistry.resolve(root.iconName) !== null

  // The real bar loader for the same id, placed in the left bar section.
  BarWidgetLoader {
    id: barLoader

    widgetId: root.widgetKey
    widgetScreen: Quickshell.screens[0]
    widgetProps: ({
                    "widgetId": root.widgetKey,
                    "section": "left",
                    "sectionWidgetIndex": 0,
                    "sectionWidgetsCount": 1
                  })
  }

  // The real control-center loader for the same id (plugin path). It must keep
  // the widget it loaded across registry changes that do not concern its id.
  ControlCenterWidgetLoader {
    id: ccLoader

    widgetId: root.widgetKey
    widgetScreen: Quickshell.screens[0]
    widgetProps: ({
                    "section": "left",
                    "sectionWidgetIndex": 0
                  })
    listSection: "left"
  }

  // Control-center steps run after the four registry phases. Each step's row is
  // published on the next tick, after the loader has settled.
  property var ccRecorded: null
  property string ccPending: ""
  readonly property string ccOtherId: "test:other"

  function publish(row) {
    console.log("PLUGIN_REGISTRY_REACTIVITY|" + JSON.stringify(row));
  }

  // The widget instance a loader currently holds, or null.
  function loaderItem(loaderRoot) {
    for (const child of loaderRoot.children) {
      if ("sourceComponent" in child)
        return child.item ?? null;
    }
    return null;
  }

  function realWidgetLoaded() {
    const item = root.loaderItem(barLoader);
    return item !== null && item.objectName === "m09-real-widget";
  }

  function publishCc(step) {
    const item = root.loaderItem(ccLoader);
    root.publish({
                   phase: "cc-loader",
                   step: step,
                   loaded: item !== null,
                   sameAsRecorded: item !== null && item === root.ccRecorded
                 });
  }

  function ccRecord() {
    root.ccRecorded = root.loaderItem(ccLoader);
    root.ccPending = "record";
  }

  function ccRegisterOther() {
    const ok = ControlCenterWidgetRegistry.registerPluginWidget(root.ccOtherId, root.widgetComponent, {});
    root.publish({
                   phase: "call",
                   action: "cc-register-other",
                   returned: ok
                 });
    root.ccPending = "other-registered";
  }

  function ccUnregisterOther() {
    const ok = ControlCenterWidgetRegistry.unregisterPluginWidget(root.ccOtherId);
    root.publish({
                   phase: "call",
                   action: "cc-unregister-other",
                   returned: ok
                 });
    root.ccPending = "other-unregistered";
  }

  function ccUnregisterTest() {
    const ok = ControlCenterWidgetRegistry.unregisterPluginWidget(root.pluginId);
    root.publish({
                   phase: "call",
                   action: "cc-unregister-test",
                   returned: ok
                 });
    root.ccPending = "test-unregistered";
  }

  function ccReregisterTest() {
    const ok = ControlCenterWidgetRegistry.registerPluginWidget(root.pluginId, root.widgetComponent, {});
    root.publish({
                   phase: "call",
                   action: "cc-reregister-test",
                   returned: ok
                 });
    root.ccPending = "test-reregistered";
  }

  function report(phase) {
    const name = root.phaseNames[phase];
    root.publish({
                   phase: name,
                   registry: "bar",
                   binding: root.barBinding,
                   direct: BarWidgetRegistry.hasWidget(root.widgetKey)
                 });
    root.publish({
                   phase: name,
                   registry: "control-center",
                   binding: root.controlCenterBinding,
                   direct: ControlCenterWidgetRegistry.hasWidget(root.widgetKey)
                 });
    root.publish({
                   phase: name,
                   registry: "desktop",
                   binding: root.desktopBinding,
                   direct: DesktopWidgetRegistry.hasWidget(root.widgetKey)
                 });
    root.publish({
                   phase: name,
                   registry: "launcher",
                   binding: root.launcherBinding,
                   direct: LauncherProviderRegistry.hasProvider(root.widgetKey)
                 });
    root.publish({
                   phase: name,
                   registry: "icon",
                   binding: root.iconBinding,
                   direct: IconRegistry.resolve(root.iconName) !== null
                 });
    root.publish({
                   phase: name,
                   registry: "bar-loader",
                   unavailable: barLoader._pluginUnavailable,
                   realWidget: root.realWidgetLoaded()
                 });
  }

  // Installed but not registered: the placeholder path needs the plugin to
  // count as installed (Registry.isPluginDownloaded reads installedPlugins).
  function seedInstalled() {
    Registry.installedPlugins = Object.assign({}, Registry.installedPlugins, {
                                                "test:x": {
                                                  "id": "test:x",
                                                  "name": "M09 registry probe",
                                                  "version": "0.0.0",
                                                  "entryPoints": {}
                                                }
                                              });
  }

  function registerAll() {
    if (root.widgetComponent.status !== Component.Ready) {
      root.publish({
                     phase: "setup",
                     registry: "component",
                     error: root.widgetComponent.errorString()
                   });
      return;
    }
    const calls = {
      "bar": BarWidgetRegistry.registerPluginWidget(root.pluginId, root.widgetComponent, {}),
      "control-center": ControlCenterWidgetRegistry.registerPluginWidget(root.pluginId, root.widgetComponent, {}),
      "desktop": DesktopWidgetRegistry.registerPluginWidget(root.pluginId, root.widgetComponent, {}),
      "launcher": LauncherProviderRegistry.registerPluginProvider(root.pluginId, root.widgetComponent, {})
    };
    IconRegistry.register(root.pluginId, {
                            "icons": {
                              "m09-test-icon": {
                                "filename": "icon.svg"
                              }
                            }
                          }, Quickshell.shellDir);
    root.publish({
                   phase: "call",
                   action: "register",
                   returned: calls
                 });
  }

  function unregisterAll() {
    const calls = {
      "bar": BarWidgetRegistry.unregisterPluginWidget(root.pluginId),
      "control-center": ControlCenterWidgetRegistry.unregisterPluginWidget(root.pluginId),
      "desktop": DesktopWidgetRegistry.unregisterPluginWidget(root.pluginId),
      "launcher": LauncherProviderRegistry.unregisterPluginProvider(root.pluginId)
    };
    IconRegistry.unregister(root.pluginId);
    root.publish({
                   phase: "call",
                   action: "unregister",
                   returned: calls
                 });
  }

  // One step per tick: at tick n the state reported is the one left by the
  // step before it, after one full second for asynchronous loaders to settle.
  Timer {
    id: stepper

    interval: 1000
    running: true
    repeat: true
    onTriggered: {
      if (root.ccPending !== "") {
        root.publishCc(root.ccPending);
        root.ccPending = "";
      }
      if (root.tick >= 1 && root.tick <= 4)
        root.report(root.tick - 1);
      if (root.tick === 0)
        root.seedInstalled();
      else if (root.tick === 1)
        root.registerAll();
      else if (root.tick === 2)
        root.unregisterAll();
      else if (root.tick === 3)
        root.registerAll();
      else if (root.tick === 4)
        root.ccRecord();
      else if (root.tick === 5)
        root.ccRegisterOther();
      else if (root.tick === 6)
        root.ccUnregisterOther();
      else if (root.tick === 7)
        root.ccUnregisterTest();
      else if (root.tick === 8)
        root.ccReregisterTest();
      else {
        root.publish({
                       phase: "done",
                       registry: "probe",
                       status: "settled"
                     });
        Qt.exit(0);
        return;
      }
      root.tick++;
    }
  }

  Timer {
    interval: 60000
    running: true
    onTriggered: {
      root.publish({
                     phase: "timeout",
                     registry: "probe",
                     status: "timeout",
                     tick: root.tick
                   });
      Qt.exit(2);
    }
  }
}
