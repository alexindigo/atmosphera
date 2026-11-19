// Real NSectionEditor + global BarTab owner. The VM relocates this inert entry.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI
import qs.Widgets
import qs.Modules.Panels.Settings.Tabs.Bar as Bar

PanelWindow {
  id: root
  implicitWidth: 1000
  implicitHeight: 750
  color: AtmoColor.mSurface
  property bool started: false
  property int stage: 0
  property int settingsCaptures: 0
  property int revisionBefore: 0
  property bool iconsReady: false
  readonly property bool verifyOnly: Quickshell.env("I4_VERIFY") === "1"
  Bar.BarTab { id: owner; visible: false }
  ListModel { id: available; ListElement { key: "Clock"; name: "Clock" } }
  ColumnLayout {
    anchors.fill: parent
    anchors.margins: 20
    NSectionEditor {
      id: left
      sectionName: "Left"; sectionId: "left"; availableWidgets: available
      widgetRegistry: BarWidgetRegistry
      widgetModel: Settings.data.bar.widgets.left
      captureWidgetInteraction: owner.captureWidgetInteraction
      onMoveWidget: (section, index, target) => owner._moveWidgetBetweenSections(section, index, target)
      onRemoveWidget: (section, index) => owner._removeWidgetFromSection(section, index)
      onReorderWidget: (section, from, to) => owner._reorderWidgetInSection(section, from, to)
      captureWidgetSettings: function (section, index) { root.settingsCaptures++; return BarService.createWidgetSettingsEditor("", section, index); }
      settingsDialogComponent: Quickshell.shellDir + "/i4-bar-section-dialog.qml"
      onWidgetCommandCompleted: result => root.commandResult(result)
      onWidgetSettingsCompleted: result => root.settingsResult(result)
      onWidgetSettingsClosed: root.settingsClosed()
    }
    NSectionEditor {
      id: center
      sectionName: "Center"; sectionId: "center"; availableWidgets: available
      widgetRegistry: BarWidgetRegistry
      widgetModel: Settings.data.bar.widgets.center
      captureWidgetInteraction: owner.captureWidgetInteraction
      onMoveWidget: (section, index, target) => owner._moveWidgetBetweenSections(section, index, target)
      onRemoveWidget: (section, index) => owner._removeWidgetFromSection(section, index)
      onReorderWidget: (section, from, to) => owner._reorderWidgetInSection(section, from, to)
      onWidgetCommandCompleted: result => root.commandResult(result)
    }
    NSectionEditor {
      id: right
      sectionName: "Right"; sectionId: "right"; availableWidgets: available
      widgetRegistry: BarWidgetRegistry
      widgetModel: Settings.data.bar.widgets.right
      captureWidgetInteraction: owner.captureWidgetInteraction
      onMoveWidget: (section, index, target) => owner._moveWidgetBetweenSections(section, index, target)
      onRemoveWidget: (section, index) => owner._removeWidgetFromSection(section, index)
      onReorderWidget: (section, from, to) => owner._reorderWidgetInSection(section, from, to)
      onWidgetCommandCompleted: result => root.commandResult(result)
    }
  }
  function check(ok, name) { if (!ok) throw new Error("I4_BAR_SECTION_ASSERT: " + name); }
  FileView {
    path: Quickshell.env("I4_ICON_DATA")
    onLoaded: {
      IconRegistry.register("fixture:atmosphera-icons", JSON.parse(text()), Quickshell.env("I4_ICON_DIR"));
      root.iconsReady = true;
      root.begin();
    }
  }
  function fail(error) { console.error(String(error)); Qt.exit(2); }
  function rows() { return [{id: "Volume", tag: "first", opaque: {keep: true}}, {id: "Volume", tag: "second", opaque: {keep: true}}]; }
  function seed() {
    Settings.data.bar.widgets.left = rows();
    Settings.data.bar.widgets.center = [{id: "Clock", tag: "destination"}];
    Settings.data.bar.widgets.right = [];
  }
  function later(callback) { Qt.callLater(function () { try { callback(); } catch (error) { root.fail(error); } }); }
  function openLeft(action) {
    check(left.openWidgetMenu(0) && left.widgetMenuVisible, "real menu opened");
    return left.activateWidgetMenu(action);
  }
  Process {
    id: capture
    command: ["timeout", "10", "grim", Quickshell.env("I4_BAR_SECTION_CAPTURE")]
    onExited: (code, status) => {
      try { root.check(code === 0, "guest menu capture"); root.completeFirstMenu(); } catch (error) { root.fail(error); }
    }
  }
  Timer { id: captureDelay; interval: 100; onTriggered: capture.running = true }
  function completeFirstMenu() {
    var original = rows();
    Settings.data.bar.widgets.left = [original[1], original[0]];
    var admitted = left.activateWidgetMenu("center");
    check(Settings.data.bar.widgets.center.length === 1, "stale menu modified consumer");
    check(!admitted, "source replacement refused");
  }
  function firstMenu() {
    later(function () {
      stage = 1;
      check(left.openWidgetMenu(0), "source menu capture");
      if (Quickshell.env("I4_BAR_SECTION_CAPTURE"))
        captureDelay.restart();
      else
        completeFirstMenu();
    });
  }
  function optionalActor() {
    var interaction = owner.captureWidgetInteraction("left", 0);
    check(interaction.submit("move", "right"), "observer-free section transfer");
    Settings.saveResult(function (result) {
      try {
        check(result.status !== "failed" && Settings.data.bar.widgets.left.length === 1 && Settings.data.bar.widgets.right[0].tag === "first", "observer-free actor still changes and saves owner");
        interaction.detach();
        var invalid = owner.captureWidgetInteraction("left", 0);
        check(invalid.submit("invalid", null, {}) === false, "nonfunction actor failure observer");
        Settings.saveResult(function (fenced) {
          try {
            check(fenced.status !== "failed" && Settings.data.bar.widgets.left.length === 1 && Settings.data.bar.widgets.right.length === 1, "observer-free refusal stays inert");
            invalid.detach();
            seed();
            firstMenu();
          } catch (error) { fail(error); }
        });
      } catch (error) { fail(error); }
    });
  }
  function refused(result) { check(result.status === "failed" && result.error.code === "list-edit-conflict", "stale captured interaction refused"); }
  function commandResult(result) {
    try {
      if (stage === 1) {
        refused(result);
        check(Settings.data.bar.widgets.left[0].tag === "second" && Settings.data.bar.widgets.center.length === 1, "menu does not move newer repeated-ID row");
        seed();
        later(function () {
          stage = 2;
          check(left.openWidgetMenu(0), "ABA menu capture");
          Settings.data.bar.widgets.center = [{id: "Clock", tag: "intervening"}];
          Settings.data.bar.widgets.center = [{id: "Clock", tag: "destination"}];
          check(!left.activateWidgetMenu("center"), "destination ABA admission refused");
        });
      } else if (stage === 2) {
        refused(result);
        check(Settings.data.bar.widgets.left.length === 2 && Settings.data.bar.widgets.center[0].tag === "destination", "both menu owners retained");
        stage = 3;
        revisionBefore = BarService.widgetsRevision;
        check(openLeft("center"), "menu transfer admitted");
      } else if (stage === 3) {
        check(result.status === "admitted" && result.refreshState === "current", "menu current admission");
        check(Settings.data.bar.widgets.left.length === 1 && Settings.data.bar.widgets.center[1].tag === "first" && Settings.data.bar.widgets.center[1].opaque.keep, "menu consumer original row");
        check(BarService.widgetsRevision === revisionBefore + 1, "structural revision after admission");
        seed();
        later(function () {
          stage = 4;
          check(left.beginWidgetDrag(0), "drag captures at press");
          var original = rows();
          Settings.data.bar.widgets.left = [original[1], original[0]];
          check(!left.finishWidgetDrag(-1, "right"), "stale drag refused");
        });
      } else if (stage === 4) {
        refused(result);
        check(Settings.data.bar.widgets.right.length === 0, "drag did not copy replacement row");
        seed();
        later(function () {
          check(left.beginWidgetDrag(0), "cancel capture");
          left.cancelWidgetDrag();
          check(!left.finishWidgetDrag(-1, "right") && Settings.data.bar.widgets.left.length === 2, "canceled drag is inert");
          stage = 5;
          check(left.beginWidgetDrag(0) && left.finishWidgetDrag(1, ""), "same-section drag reorder");
        });
      } else if (stage === 5) {
        check(result.status === "admitted" && Settings.data.bar.widgets.left[0].tag === "second", "reorder consumer");
        stage = 6;
        check(left.beginWidgetDrag(1) && left.finishWidgetDrag(-1, "right"), "cross-section drag transfer");
      } else if (stage === 6) {
        check(result.status === "admitted" && Settings.data.bar.widgets.left.length === 1 && Settings.data.bar.widgets.right[0].tag === "first", "drag consumer retains original fields");
        stage = 7;
        check(center.openWidgetMenu(0) && center.activateWidgetMenu("remove"), "captured remove menu");
      } else if (stage === 7) {
        check(result.status === "admitted" && Settings.data.bar.widgets.center.length === 0, "remove consumer");
        check(owner._addWidgetToSection("Clock", "center"), "explicit insert command");
        later(function () {
          check(Settings.data.bar.widgets.center[0].id === "Clock", "insert consumer");
          stage = 8;
          Settings.setBindingsUnresolved(true);
          left.openWidgetSettings(0, Settings.data.bar.widgets.left[0]);
          check(settingsCaptures === 1, "settings owner captured before component creation");
        });
      }
    } catch (error) { fail(error); }
  }
  function settingsResult(result) {
    try {
      if (stage === 8) {
        check(result.status === "failed" && left.widgetSettingsVisible && left.widgetSettingsDirty, "real failed Popup retains work");
        check(Settings.data.bar.widgets.left[0].i4Explicit === true, "failed receipt retains admitted field");
        left.openWidgetSettings(0, Settings.data.bar.widgets.left[0]);
        check(settingsCaptures === 1, "competing open never discards active failed editor");
        left.requestWidgetSettingsDiscard();
        check(left.widgetSettingsDiscardPending, "explicit discard confirmation");
        left.keepWidgetSettings();
        check(left.widgetSettingsDirty && !left.widgetSettingsDiscardPending, "cancel discard retains input");
        Settings.setBindingsUnresolved(false);
        stage = 9;
        left.saveWidgetSettings();
      } else if (stage === 9) {
        check(result.status !== "failed" && !left.widgetSettingsDirty, "same captured Popup retry acknowledged");
      }
    } catch (error) { fail(error); }
  }
  function settingsClosed() {
    if (stage !== 9)
      return;
    later(function () {
      check(!left.widgetSettingsVisible && Settings.data.bar.widgets.left[0].i4Explicit === true, "acknowledged Popup closes with actual consumer");
      save();
    });
  }
  function finalChecks() {
    check(Settings.data.bar.widgets.left.length === 1 && Settings.data.bar.widgets.left[0].tag === "second" && Settings.data.bar.widgets.left[0].i4Explicit === true, "final left consumer");
    check(Settings.data.bar.widgets.center.length === 1 && Settings.data.bar.widgets.center[0].id === "Clock", "final center consumer");
    check(Settings.data.bar.widgets.right.length === 1 && Settings.data.bar.widgets.right[0].tag === "first" && Settings.data.bar.widgets.right[0].opaque.keep, "final right raw fields");
    check(Settings.data.bar.screenOverrides[0].widgets.left[0].tag === "screen-untouched", "global editor never follows screen route");
  }
  function save() {
    finalChecks();
    Settings.saveResult(function (result) {
      try {
        check(result.status !== "failed", "final persistence receipt");
        finalChecks();
        console.log("I4_BAR_SECTION: SAVED_PASS");
        Qt.exit(0);
      } catch (error) { fail(error); }
    });
  }
  function begin() {
    if (started || !Settings.isLoaded || !iconsReady)
      return;
    started = true;
    try {
      if (verifyOnly) {
        finalChecks();
        console.log("I4_BAR_SECTION: RESTART_PASS");
        Qt.exit(0);
        return;
      }
      seed();
      Settings.data.bar.screenOverrides = [{name: Quickshell.screens[0].name, widgets: {left: [{id: "Volume", tag: "screen-untouched"}], center: [], right: []}}];
      if (typeof owner.captureWidgetInteraction === "function")
        optionalActor();
      else
        firstMenu();
    } catch (error) { fail(error); }
  }
  Connections { target: Settings; function onSettingsLoaded() { root.begin(); } }
  Component.onCompleted: begin()
  Timer { interval: 90000; running: true; onTriggered: root.fail("bar section watchdog") }
}
