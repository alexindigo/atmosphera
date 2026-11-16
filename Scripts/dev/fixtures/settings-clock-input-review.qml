import QtQuick
import Quickshell
import qs.Commons
import qs.Services.UI
import qs.Modules.Panels.Settings.Bar.WidgetSettings as B
import qs.Modules.Panels.Settings.DesktopWidgets.WidgetSettings as D

PanelWindow {
  id: root
  implicitWidth: 900
  implicitHeight: 700
  property bool started: false
  property var page: null
  property var editor: null
  property var fields: ({})
  property int index: 0
  property int emitted: 0
  readonly property bool desktop: Quickshell.env("CLOCK_INPUT_MODE") === "desktop"
  readonly property bool verifyOnly: Quickshell.env("CLOCK_INPUT_VERIFY") === "1"
  readonly property string screenName: Quickshell.screens[0].name
  readonly property var names: desktop ? ["format"] : ["formatHorizontal", "formatVertical", "tooltipFormat"]
  readonly property var labels: desktop ? ["panels.desktop-widgets.clock-format-label"] : ["bar.clock.horizontal-bar-label", "bar.clock.vertical-bar-label", "bar.clock.tooltip-format-label"]
  Item { id: scene; anchors.fill: parent }
  Component { id: barPage; B.ClockSettings { onSettingsChanged: root.record(settings) } }
  Component { id: desktopPage; D.ClockSettings { onSettingsChanged: root.record(settings) } }
  function check(ok, label) { if (!ok) throw new Error("CLOCK_INPUT_ASSERT: " + label); }
  function fail(error) { console.error(String(error)); Qt.exit(2); }
  function find(item, label) {
    if (String(item).indexOf("NTextInput_QMLTYPE") === 0 && item.label === I18n.tr(label)) return item;
    for (var child of (item.children || [])) { var result = find(child, label); if (result) return result; }
    return null;
  }
  function record(patch) {
    try {
      check(Object.keys(patch).join(",") === names[index], "one current user field");
      fields[names[index]] = patch[names[index]];
      emitted++;
    } catch (error) { fail(error); }
  }
  function row() { return desktop ? Settings.data.desktopWidgets.monitorWidgets[0].widgets[0] : Settings.data.bar.widgets.left[0]; }
  function verify() {
    for (var i = 0; i < names.length; i++) check(row()[names[i]] === "HH:mm:ss 'edit" + i + "'", "cold field " + names[i]);
    check(row().opaque.keep === true, "unknown row member preserved");
    console.log("CLOCK_INPUT: COLD_PASS " + (desktop ? "desktop" : "bar"));
    Qt.exit(0);
  }
  function begin() {
    if (started || !Settings.isLoaded) return;
    started = true;
    try {
      if (verifyOnly) { verify(); return; }
      var seed = {id: "Clock", opaque: {keep: true}};
      if (desktop) Settings.data.desktopWidgets.monitorWidgets = [{name: screenName, widgets: [seed]}];
      else Settings.data.bar.widgets.left = [seed];
      capture.start();
    } catch (error) { fail(error); }
  }
  Timer {
    id: capture
    interval: 20
    repeat: true
    onTriggered: {
      try {
        root.editor = root.desktop ? DesktopWidgetRegistry.createWidgetSettingsEditor(root.screenName, 0) : BarService.createWidgetSettingsEditor("", "left", 0);
        if (!root.editor) return;
        stop();
        var metadata = root.desktop ? DesktopWidgetRegistry.widgetMetadata.Clock : BarWidgetRegistry.widgetMetadata.Clock;
        root.page = (root.desktop ? desktopPage : barPage).createObject(scene, {widgetData: root.editor.initialValue, widgetMetadata: metadata});
        root.check(root.page !== null, "actual Clock settings page");
        settle.start();
      } catch (error) { stop(); root.fail(error); }
    }
  }
  Timer { id: settle; interval: 100; onTriggered: root.edit() }
  function edit() {
    try {
      check(emitted === 0, "construction and programmatic refresh do not publish");
      for (index = 0; index < names.length; index++) {
        var input = find(page, labels[index]);
        check(input !== null, "real native format field " + names[index]);
        var before = emitted;
        input.text = "";
        check(emitted === before, "programmatic change is not intent");
        input.inputItem.insert(0, " HH:mm:ss 'edit" + index + "' ");
        check(emitted === before + 1, "one native user edit");
        check(fields[names[index]] === input.text.trim(), "signal-time current input " + names[index] + ": " + fields[names[index]]);
      }
      check(editor.submit(fields, function (result) {
        try {
          check(result.status !== "failed", "actual selected-owner publication");
          for (var i = 0; i < names.length; i++) check(row()[names[i]] === fields[names[i]], "saved consumer " + names[i]);
          console.log("CLOCK_INPUT: SAVED_PASS " + (desktop ? "desktop" : "bar"));
          Qt.exit(0);
        } catch (error) { fail(error); }
      }), "format fields admitted");
    } catch (error) { fail(error); }
  }
  Connections { target: Settings; function onSettingsLoaded() { root.begin(); } }
  Component.onCompleted: Qt.callLater(begin)
  Timer { interval: 30000; running: true; onTriggered: root.fail("clock input deadline") }
}
