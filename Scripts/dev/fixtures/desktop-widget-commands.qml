// Actual desktop owners and Popup; VM-only save / separate-restart witness.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI
import qs.Modules.DesktopWidgets as Desktop
import qs.Modules.Panels.Settings.Tabs as Tabs

PanelWindow {
  id: root
  implicitWidth: 1050; implicitHeight: 750; color: AtmoColor.mSurface
  readonly property var testScreen: Quickshell.screens[0]
  readonly property string monitorName: testScreen.name
  readonly property bool verifyOnly: Quickshell.env("I4_VERIFY") === "1"
  property bool started: false
  property bool iconsReady: false
  property int writes: 0
  property var waiting: null
  property var nextWait: null
  property int polls: 0
  property int popupStage: 0
  Tabs.DesktopWidgetsTab { id: owner; visible: false }
  Item { id: scene; anchors.fill: parent }
  QtObject {
    id: popupHost
    readonly property var dialogParent: scene
    function hideDynamicMenu() {}
    function showDialog(dialog) {}
  }
  Desktop.DraggableDesktopWidget {
    id: runtimeWidget; screen: root.testScreen; widgetIndex: 0; width: 100; height: 80
    widgetData: DesktopWidgetRegistry.getWidgetsForMonitor(root.monitorName)[0] || ({id: "Clock"})
  }
  FileView {
    path: Quickshell.env("I4_ICON_DATA")
    onLoaded: {
      IconRegistry.register("fixture:atmosphera-icons", JSON.parse(text()), Quickshell.env("I4_ICON_DIR"));
      root.iconsReady = true; root.begin();
    }
  }
  function check(ok, message) { if (!ok) throw new Error("I4_DESKTOP_ASSERT: " + message); }
  function fail(error) { console.error(String(error)); Qt.exit(2); }
  function later(callback) { Qt.callLater(function () { try { callback(); } catch (error) { fail(error); } }); }
  function receipt(callback) {
    Settings.saveResult(function (result) { try { check(result.status !== "failed", "save receipt"); callback(); } catch (error) { fail(error); } });
  }
  function waitFor(condition, callback) { waiting=condition; nextWait=callback; polls=0; waitTimer.start(); }
  Timer {
    id: waitTimer; interval: 10; repeat: true
    onTriggered: {
      try {
        check(++root.polls < 3000, "bounded UI wait");
        if (root.waiting()) { stop(); var callback=root.nextWait; root.waiting=null; root.nextWait=null; callback(); }
      } catch (error) { stop(); root.fail(error); }
    }
  }
  function rows() { return [{id: "Clock", tag: "first", x: 7, y: 9, scale: 2, opaque: {keep: true}}, {id: "Clock", tag: "second", opaque: {keep: true}}]; }
  function seedMoves() {
    Settings.data.desktopWidgets.monitorWidgets=[
      {name: monitorName, opaque: "monitor", widgets: rows()},
      {name: "i4-missing", opaque: "missing"},
      {name: monitorName, opaque: "duplicate", widgets: [{id: "Clock", tag: "duplicate"}]}
    ];
  }
  function list(name) { return DesktopWidgetRegistry.getWidgetsForMonitor(name); }
  function begin() {
    if (started || !Settings.isLoaded || !iconsReady) return;
    started=true;
    try {
      if (verifyOnly) { finalChecks(); console.log("I4_DESKTOP_COMMANDS: RESTART_PASS"); Qt.exit(0); return; }
      PanelService.registerPopupMenuWindow(testScreen, popupHost);
      if (Quickshell.env("I4_PARENT") === "1") {
        seedMoves(); var before=writes;
        owner._moveWidgetToMonitor(monitorName,0,"i4-missing");
        check(writes===before+1,"move is one owner admission");
        Qt.exit(3); return;
      }
      Settings.data.desktopWidgets.monitorWidgets=[];
      check(owner._addWidgetToMonitor(monitorName,"Clock"),"first actual tab insertion");
      check(list(monitorName)[0].id==="Clock","created record consumer");
      receipt(function () {
        Settings.data.desktopWidgets.monitorWidgets=[{name:"i4-missing",opaque:"missing"}];
        check(owner._addWidgetToMonitor("i4-missing","Clock"),"missing list insertion");
        check(Settings.data.desktopWidgets.monitorWidgets[0].opaque==="missing","insertion preserves monitor unknowns");
        receipt(moveFirst);
      });
    } catch (error) { fail(error); }
  }
  function moveFirst() {
    seedMoves(); var original=JSON.stringify(Settings.data.desktopWidgets.monitorWidgets);
    check(DesktopWidgetRegistry.captureWidgetInteraction(monitorName,99,["i4-created"])===null,"invalid source capture");
    var canceled=DesktopWidgetRegistry.captureWidgetInteraction(monitorName,0,["i4-created"]); canceled.detach();
    check(JSON.stringify(Settings.data.desktopWidgets.monitorWidgets)===original,"read/cancel creates nothing");
    var before=writes;
    check(owner._moveWidgetToMonitor(monitorName,0,"i4-missing"),"actual tab move");
    check(writes===before+1,"move is one owner admission");
    check(list(monitorName)[0].tag==="second" && list("i4-missing")[0].tag==="first","moved original row");
    var moved=list("i4-missing")[0];
    check(moved.x===100 && moved.y===100 && moved.scale===1 && moved.opaque.keep,"only placement fields reset");
    check(Settings.data.desktopWidgets.monitorWidgets[0].opaque==="monitor" && Settings.data.desktopWidgets.monitorWidgets[1].opaque==="missing" && Settings.data.desktopWidgets.monitorWidgets[2].opaque==="duplicate","monitor ancestry and first duplicate");
    receipt(function () {
      var count=writes;
      check(owner._moveWidgetToMonitor("i4-missing",0,"i4-created"),"absent destination transfer");
      check(writes===count+1 && list("i4-missing").length===0 && list("i4-created")[0].tag==="first","one admission and empty source retained");
      receipt(staleActors);
    });
  }
  function staleActors() {
    var actor=DesktopWidgetRegistry.captureWidgetInteraction(monitorName,0,["i4-created"]);
    var current=Settings.data.desktopWidgets.monitorWidgets;
    Settings.data.desktopWidgets.monitorWidgets=current.concat([{name:"i4-intervening",widgets:[]}]);
    Settings.data.desktopWidgets.monitorWidgets=current;
    var before=JSON.stringify(Settings.data.desktopWidgets.monitorWidgets);
    check(!actor.submit("move","i4-created",function (result) {
      try {
        check(result.status==="failed" && result.error.code==="list-edit-conflict","notified ABA refuses");
        check(JSON.stringify(Settings.data.desktopWidgets.monitorWidgets)===before,"no partial stale transfer"); actor.detach();
        later(staleRuntimeMenu);
      } catch (error) { fail(error); }
    }),"stale actor admission false");
  }
  function staleRuntimeMenu() {
    var action=runtimeWidget.captureContextMenuAction();
    var current=Settings.data.desktopWidgets.monitorWidgets;
    Settings.data.desktopWidgets.monitorWidgets=current.concat([{name:"i4-intervening",widgets:[]}]);
    Settings.data.desktopWidgets.monitorWidgets=current;
    action("delete");
    receipt(function () {
      check(list(monitorName)[0].tag==="second","retained runtime menu cannot delete newer generation");
      var editor=DesktopWidgetRegistry.createWidgetSettingsEditor(monitorName,0);
      Settings.data.desktopWidgets.monitorWidgets=current.concat([{name:"i4-intervening",widgets:[]}]);
      Settings.data.desktopWidgets.monitorWidgets=current;
      check(!editor.submit({mustNotLand:true},function (result) {
        try {
          check(result.status==="failed" && list(monitorName)[0].mustNotLand===undefined,"captured gesture fields refuse stale owner"); editor.detach();
          shortcutCleanup();
        } catch (error) { fail(error); }
      }),"stale field admission false");
    });
  }
  function shortcutCleanup() {
    check(DesktopWidgetRegistry.addWidget("i4-empty",{id:"AppShortcut",appId:""},function (result,index) {
      try {
        check(result.status==="admitted","new unassigned shortcut");
        var editor=DesktopWidgetRegistry.createWidgetSettingsEditor("i4-empty",index);
        check(editor.submit({customLabel:"unassigned"},function (saved) {
          try {
            check(saved.status!=="failed","own shortcut field save");
            check(editor.removeIfUnassigned(function (removed) {
              try {
                check(removed.status==="admitted" && list("i4-empty").length===0,"cleanup retains created empty container"); editor.detach(); assignedShortcut();
              } catch (error) { fail(error); }
            }),"captured unassigned cleanup");
          } catch (error) { fail(error); }
        }),"shortcut field input");
      } catch (error) { fail(error); }
    }),"shortcut insert");
  }
  function assignedShortcut() {
    DesktopWidgetRegistry.addWidget("i4-assigned",{id:"AppShortcut",appId:""},function (result,index) {
      try {
        var editor=DesktopWidgetRegistry.createWidgetSettingsEditor("i4-assigned",index);
        check(editor.submit({appId:"i4.app"},function (saved) {
          try { check(saved.status!=="failed" && !editor.removeIfUnassigned() && list("i4-assigned")[0].appId==="i4.app","assigned shortcut is never auto-deleted"); editor.detach(); actualShortcutClose(); }
          catch (error) { fail(error); }
        }),"assigned shortcut input");
      } catch (error) { fail(error); }
    });
  }
  function actualShortcutClose() {
    var count=list(monitorName).length;
    check(owner._createAndEditAppShortcut(),"actual tab shortcut creation");
    waitFor(function () { return DesktopWidgetRegistry.currentSettingsDialog?.visible; },function () {
      check(list(monitorName).length===count+1,"new shortcut before dialog close");
      DesktopWidgetRegistry.currentSettingsDialog.saveAndClose();
      waitFor(function () { return DesktopWidgetRegistry.currentSettingsDialog===null; },function () {
        receipt(function () { check(list(monitorName).length===count,"actual unassigned close cleanup"); actualShortcutDiscard(); });
      });
    });
  }
  function actualShortcutDiscard() {
    var count=list(monitorName).length;
    Settings.setBindingsUnresolved(true);
    check(owner._createAndEditAppShortcut(),"shortcut creation before failed discard");
    waitFor(function () { return DesktopWidgetRegistry.currentSettingsDialog?.visible; },function () {
      var dialog=DesktopWidgetRegistry.currentSettingsDialog;
      dialog.queueSettings({customLabel:"unassigned failed input"});
      waitFor(function () { return dialog.saveFailed && !dialog.saveBusy; },function () {
        check(dialog.settingsDirty,"failed shortcut input retained");
        dialog.requestDiscard(); check(dialog.confirmDiscard(),"explicit shortcut discard confirmed");
        waitFor(function () { return DesktopWidgetRegistry.currentSettingsDialog===null; },function () {
          Settings.setBindingsUnresolved(false);
          receipt(function () { check(list(monitorName).length===count,"confirmed discard keeps cleanup session alive through closed"); staleShortcutDiscard(); });
        });
      });
    });
  }
  function staleShortcutDiscard() {
    var count=list(monitorName).length;
    check(owner._createAndEditAppShortcut(),"shortcut creation before foreign change");
    waitFor(function () { return DesktopWidgetRegistry.currentSettingsDialog?.visible; },function () {
      var dialog=DesktopWidgetRegistry.currentSettingsDialog;
      var current=Settings.data.desktopWidgets.monitorWidgets;
      Settings.data.desktopWidgets.monitorWidgets=current.concat([{name:"i4-intervening",widgets:[]}]);
      Settings.data.desktopWidgets.monitorWidgets=current;
      dialog.queueSettings({customLabel:"must not land"});
      waitFor(function () { return dialog.saveFailed && !dialog.saveBusy; },function () {
        dialog.requestDiscard(); check(dialog.confirmDiscard(),"stale local shortcut input discarded explicitly");
        waitFor(function () { return DesktopWidgetRegistry.currentSettingsDialog===null; },function () {
          receipt(function () {
            check(list(monitorName).length===count+1 && list(monitorName)[count].customLabel!=="must not land","stale close cleanup never deletes foreign generation");
            // A separate fresh user action may remove the still-unassigned row.
            var remove=DesktopWidgetRegistry.captureWidgetInteraction(monitorName,count);
            check(remove.submit("remove",null,function (result) {
              try { check(result.status==="admitted","fresh explicit cleanup action"); remove.detach(); popupFailure(); }
              catch (error) { fail(error); }
            }),"new removal captures the current row");
          });
        });
      });
    });
  }
  function popupFailure() {
    Settings.setBindingsUnresolved(true); popupStage=1;
    DesktopWidgetRegistry.openWidgetSettings(testScreen,0,"Clock",list(monitorName)[0]);
    waitFor(function () { return DesktopWidgetRegistry.currentSettingsDialog?.visible; },function () {
      DesktopWidgetRegistry.currentSettingsDialog.queueSettings({i4Explicit:true});
    });
  }
  Connections {
    target: DesktopWidgetRegistry.currentSettingsDialog
    ignoreUnknownSignals: true
    function onSettingsSaveCompleted(result) { root.popupResult(result); }
  }
  function popupResult(result) {
    try {
      var dialog=DesktopWidgetRegistry.currentSettingsDialog;
      if (popupStage===1) {
        check(result.status==="failed" && dialog.visible && dialog.settingsDirty && list(monitorName)[0].i4Explicit,"failed actual Popup retains admitted input");
        DesktopWidgetRegistry.openWidgetSettings(testScreen,0,"Clock",list(monitorName)[0]);
        check(DesktopWidgetRegistry.currentSettingsDialog===dialog,"competing open retains failed Popup");
        dialog.requestDiscard(); check(dialog.discardPending,"discard asks"); dialog.keepEditing();
        check(dialog.settingsDirty && !dialog.discardPending,"canceled discard retains input");
        Settings.setBindingsUnresolved(false); popupStage=2; dialog.saveAndClose();
      } else if (popupStage===2) {
        check(result.status!=="failed" && !dialog.settingsDirty,"same editor retry receipt"); popupStage=3;
        waitFor(function () { return DesktopWidgetRegistry.currentSettingsDialog===null; },saveFinal);
      }
    } catch (error) { fail(error); }
  }
  function finalChecks() {
    var monitors=Settings.data.desktopWidgets.monitorWidgets;
    check(list(monitorName).length===1 && list(monitorName)[0].tag==="second" && list(monitorName)[0].i4Explicit && list(monitorName)[0].opaque.keep,"final captured settings consumer");
    check(monitors[0].opaque==="monitor" && monitors[1].opaque==="missing" && monitors[2].opaque==="duplicate" && monitors[2].widgets[0].tag==="duplicate","final monitor unknowns/duplicates");
    check(list("i4-created")[0].tag==="first" && list("i4-created")[0].opaque.keep && list("i4-created")[0].x===100 && list("i4-created")[0].scale===1,"final transferred row");
    check(list("i4-empty").length===0 && list("i4-assigned")[0].appId==="i4.app","final shortcut cleanup/preservation");
  }
  function saveFinal() { receipt(function () { finalChecks(); console.log("I4_DESKTOP_COMMANDS: SAVED_PASS"); Qt.exit(0); }); }
  Connections { target: Settings.data.desktopWidgets; function onMonitorWidgetsChanged() { root.writes++; } }
  Connections { target: Settings; function onSettingsLoaded() { root.begin(); } }
  Component.onCompleted: begin()
  Timer { interval:90000; running:true; onTriggered:root.fail("desktop watchdog") }
}
