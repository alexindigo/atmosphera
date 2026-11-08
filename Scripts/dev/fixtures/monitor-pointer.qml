// Actual monitor UI. IPC observes geometry/state and saves; all interactions are
// native guest pointer events, never calls to menu/drag handlers.
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Modules.Panels.Settings.Bar as Bar
import qs.Services.UI

ShellRoot {
  id: root
  property bool ready: false
  property bool iconsReady: false
  property var left: null
  property var center: null
  property var right: null
  property var completions: []
  property string saved: ""
  readonly property string name: Quickshell.screens[0].name
  function check(ok, message) {
    if (!ok)
      throw new Error("I4_MONITOR_POINTER_ASSERT: " + message);
  }
  function find(item, predicate, visited) {
    visited = visited || [];
    if (!item || visited.indexOf(item) !== -1)
      return null;
    visited.push(item);
    if (predicate(item))
      return item;
    var nested = [];
    for (var child of item.children || [])
      nested.push(child);
    for (var resource of item.resources || [])
      nested.push(resource);
    if (item.contentItem)
      nested.push(item.contentItem);
    for (var child of nested) {
      var found = find(child, predicate, visited);
      if (found)
        return found;
    }
    return null;
  }
  function point(item, fraction) {
    if (!item || !item.visible || item.width <= 0 || item.height <= 0)
      return null;
    var value = item.mapToGlobal(item.width * fraction, item.height / 2);
    return {
      x: value.x,
      y: value.y
    };
  }
  function row(section, index) {
    return find(section, function (item) {
      return item.widgetIndex === index && item.modelData && item.modelData.tag;
    });
  }
  function values() {
    return Settings.getBarWidgetsForScreen(name);
  }
  function finalChecks() {
    var widgets = values();
    check(widgets.left.length === 0 && widgets.center[1].tag === "first" && widgets.right[0].tag === "second", "native menu move and native cross-section drag reach monitor consumer");
    check(widgets.center[1].opaque.keep && widgets.right[0].opaque.keep && Settings.data.bar.screenOverrides[0].opaque === "monitor", "unknown rows/monitor retained");
    check(Settings.data.bar.widgets.left.length === 2 && Settings.data.bar.screenOverrides[1].widgets.left[0].tag === "duplicate", "global source and later duplicate untouched");
  }
  function begin() {
    if (ready || !iconsReady || !Settings.isLoaded)
      return;
    if (Quickshell.env("I4_VERIFY") === "1") {
      finalChecks();
      console.log("I4_MONITOR_POINTER: RESTART_PASS");
      Qt.exit(0);
      return;
    }
    Settings.data.bar.widgets.left = [
          {
            id: "Volume",
            tag: "first",
            opaque: {
              keep: true
            }
          },
          {
            id: "Volume",
            tag: "second",
            opaque: {
              keep: true
            }
          }
        ];
    Settings.data.bar.widgets.center = [
          {
            id: "Clock",
            tag: "global-center"
          }
        ];
    Settings.data.bar.widgets.right = [];
    Settings.data.bar.screenOverrides = [
          {
            name: name,
            enabled: true,
            opaque: "monitor"
          },
          {
            name: name,
            widgets: {
              left: [
                {
                  id: "Volume",
                  tag: "duplicate"
                }
              ]
            }
          }
        ];
    left = find(monitor, function (item) {
      return item.sectionId === "left";
    });
    center = find(monitor, function (item) {
      return item.sectionId === "center";
    });
    right = find(monitor, function (item) {
      return item.sectionId === "right";
    });
    check(left && center && right, "actual MonitorWidgetsConfig section components");
    for (var section of [left, center, right])
      section.widgetCommandCompleted.connect(function (result) {
        root.completions = root.completions.concat([result]);
      });
    ready = true;
  }
  function snapshot() {
    var label = I18n.tr("tooltips.move-to-section", {
                          section: I18n.tr("positions.center")
                        });
    var menuText = find(window.contentItem, function (item) {
      return item.visible && item.text === label;
    });
    if (!menuText)
      menuText = find(monitor, function (item) {
        return item.visible && item.text === label;
      });
    return {
      ready: ready,
      leftRow: left ? point(row(left, 0), 0.25) : null,
      rightDrop: right ? point(right.dropTargetArea, 0.5) : null,
      menu: left ? left.widgetMenuVisible : false,
      menuCenter: point(menuText, 0.5),
      values: ready ? values() : null,
      pointer: {
        x: pointerObserver.point.scenePosition.x,
        y: pointerObserver.point.scenePosition.y,
        hovered: pointerObserver.hovered
      },
      completions: completions,
      saved: saved
    };
  }
  FileView {
    path: Quickshell.env("I4_ICON_DATA")
    onLoaded: {
      IconRegistry.register("fixture:atmosphera-icons", JSON.parse(text()), Quickshell.env("I4_ICON_DIR"));
      root.iconsReady = true;
      root.begin();
    }
  }
  PanelWindow {
    id: window
    anchors {
      top: true
      left: true
    }
    implicitWidth: 1100
    implicitHeight: 780
    exclusiveZone: 0
    color: AtmoColor.mSurface
    HoverHandler {
      id: pointerObserver
      parent: window.contentItem
      blocking: false
    }
    Bar.MonitorWidgetsConfig {
      id: monitor
      anchors.fill: parent
      screen: Quickshell.screens[0]
    }
  }
  IpcHandler {
    target: "monitorPointer"
    function snapshot(): string {
      return JSON.stringify(root.snapshot());
    }
    function save(): void {
      root.finalChecks();
      Settings.saveResult(function (result) {
        root.saved = result.status;
        if (result.status !== "failed") {
          root.finalChecks();
          console.log("I4_MONITOR_POINTER: SAVED_PASS");
        }
      });
    }
    function quit(): void {
      Qt.quit();
    }
  }
  Connections {
    target: Settings
    function onSettingsLoaded() {
      root.begin();
    }
  }
  Component.onCompleted: begin()
  Timer {
    interval: 60000
    running: true
    onTriggered: {
      console.error("I4_MONITOR_POINTER_ASSERT: watchdog");
      Qt.exit(2);
    }
  }
}
