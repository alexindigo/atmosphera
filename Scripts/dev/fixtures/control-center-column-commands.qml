// Actual owner, shared NSectionEditor intents and real live Popup; VM-only.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI
import qs.Widgets
import qs.Modules.Panels.Settings.ControlCenter
import qs.Modules.Panels.Settings.Tabs.ControlCenter as CC

PanelWindow {
  id: root
  implicitWidth:1000; implicitHeight:750; color:AtmoColor.mSurface
  property bool started:false
  property bool iconsReady:false
  property int stage:0
  property int captures:0
  readonly property bool verifyOnly:Quickshell.env("I4_VERIFY")==="1"
  CC.ControlCenterTab { id:owner; visible:false }
  ListModel { id:available; ListElement {key:"CustomButton";name:"CustomButton"} }
  ColumnLayout {
    anchors.fill:parent; anchors.margins:20
    NSectionEditor {
      id:left; sectionName:"Left"; sectionId:"left"; availableSections:["left","right"]
      availableWidgets:available; widgetRegistry:ControlCenterWidgetRegistry; widgetModel:Settings.data.controlCenter.shortcuts.left
      captureWidgetInteraction:function(section,index){return typeof owner.captureWidgetInteraction==="function"?owner.captureWidgetInteraction(section,index):null;}
      captureWidgetSettings:function(section,index){root.captures++;return owner.captureWidgetSettings(section,index);}
      settingsDialogComponent:Quickshell.shellDir+"/i4-control-column-dialog.qml"
      onWidgetCommandCompleted:result=>root.commandResult(result)
      onWidgetSettingsCompleted:result=>root.settingsResult(result)
      onWidgetSettingsClosed:root.settingsClosed()
    }
    NSectionEditor {
      id:right; sectionName:"Right"; sectionId:"right"; availableSections:["left","right"]
      availableWidgets:available; widgetRegistry:ControlCenterWidgetRegistry; widgetModel:Settings.data.controlCenter.shortcuts.right
      captureWidgetInteraction:function(section,index){return owner.captureWidgetInteraction(section,index);}
      captureWidgetSettings:function(section,index){return owner.captureWidgetSettings(section,index);}
      settingsDialogComponent:Quickshell.shellDir+"/i4-control-column-dialog.qml"
      onWidgetCommandCompleted:result=>root.commandResult(result)
    }
  }
  FileView {
    path:Quickshell.env("I4_ICON_DATA")
    onLoaded:{IconRegistry.register("fixture:atmosphera-icons",JSON.parse(text()),Quickshell.env("I4_ICON_DIR"));root.iconsReady=true;root.begin();}
  }
  function check(ok,label){if(!ok)throw new Error("I4_CC_COLUMN_ASSERT: "+label);}
  function fail(error){console.error(String(error));Qt.exit(2);}
  function later(next){Qt.callLater(function(){try{next();}catch(error){fail(error);}});}
  function rows(){return [{id:"CustomButton",tag:"first",opaque:{keep:true}},{id:"CustomButton",tag:"second",opaque:{keep:true}}];}
  function seed(){Settings.data.controlCenter.shortcuts.left=rows();Settings.data.controlCenter.shortcuts.right=[{id:"DarkMode",tag:"destination"}];}
  function begin(){
    if(started || !Settings.isLoaded || !iconsReady)return;started=true;
    try{
      if(verifyOnly){finalChecks();console.log("I4_CC_COLUMNS: RESTART_PASS");Qt.exit(0);return;}
      seed();
      if(Quickshell.env("I4_PARENT")==="1"){
        var command=typeof owner.captureWidgetInteraction==="function"?owner.captureWidgetInteraction("left",0):null;
        var original=rows();Settings.data.controlCenter.shortcuts.left=[original[1],original[0]];
        if(command)command.submit("move","right");else owner._moveWidgetBetweenSections("left",0,"right");
        check(Settings.data.controlCenter.shortcuts.right.length===1,"stale column moved a newer row");Qt.exit(3);return;
      }
      optionalActor();
    }catch(error){fail(error);}
  }
  function optionalActor(){
    var command=owner.captureWidgetInteraction("left",0);
    check(command.submit("move","right"),"observer-free transfer");
    Settings.saveResult(function(result){try{
      check(result.status!=="failed" && Settings.data.controlCenter.shortcuts.right[1].tag==="first","observer-free consumer/save");command.detach();
      seed();later(function(){stage=1;check(left.openWidgetMenu(0),"actual shared menu opened");var original=rows();Settings.data.controlCenter.shortcuts.left=[original[1],original[0]];check(!left.activateWidgetMenu("right"),"stale menu refuses");});
    }catch(error){fail(error);}});
  }
  function refused(result){check(result.status==="failed" && result.error.code==="list-edit-conflict","captured owner conflict");}
  function commandResult(result){
    try{
      if(stage===1){
        refused(result);check(Settings.data.controlCenter.shortcuts.right.length===1,"stale menu has no destination write");seed();
        later(function(){stage=2;check(left.beginWidgetDrag(0),"press captures both transfer endpoints");Settings.data.controlCenter.shortcuts.right=[{id:"DarkMode",tag:"foreign"}];Settings.data.controlCenter.shortcuts.right=[{id:"DarkMode",tag:"destination"}];check(!left.finishWidgetDrag(-1,"right"),"destination ABA drag refuses");});
      }else if(stage===2){
        refused(result);check(Settings.data.controlCenter.shortcuts.left.length===2,"stale drag leaves source");
        later(function(){check(left.beginWidgetDrag(0),"cancel starts");left.cancelWidgetDrag();check(!left.finishWidgetDrag(-1,"right"),"canceled drag inert");stage=3;check(left.beginWidgetDrag(0) && left.finishWidgetDrag(1,""),"reorder admitted");});
      }else if(stage===3){
        check(result.status==="admitted" && Settings.data.controlCenter.shortcuts.left[0].tag==="second","reorder consumer");
        stage=4;check(left.openWidgetMenu(1) && left.activateWidgetMenu("right"),"cross-column menu transfer");
      }else if(stage===4){
        check(result.status==="admitted" && Settings.data.controlCenter.shortcuts.left.length===1 && Settings.data.controlCenter.shortcuts.right[1].tag==="first" && Settings.data.controlCenter.shortcuts.right[1].opaque.keep,"moved original row/unknowns");
        stage=5;check(right.openWidgetMenu(0) && right.activateWidgetMenu("remove"),"right removal");
      }else if(stage===5){
        check(result.status==="admitted" && Settings.data.controlCenter.shortcuts.right.length===1,"removed intended right row");
        check(owner._addWidgetToSection("DarkMode","right"),"explicit new row insert");
        later(function(){stage=6;Settings.setBindingsUnresolved(true);left.openWidgetSettings(0,Settings.data.controlCenter.shortcuts.left[0]);check(captures===1,"settings capture before component loading");});
      }
    }catch(error){fail(error);}
  }
  function settingsResult(result){
    try{
      if(stage===6){
        check(result.status==="failed" && left.widgetSettingsVisible && left.widgetSettingsDirty,"actual failed Popup retains input");
        check(Settings.data.controlCenter.shortcuts.left[0].i4Explicit===true,"failed save retains admitted field");
        left.openWidgetSettings(0,Settings.data.controlCenter.shortcuts.left[0]);check(captures===1,"competing open retains same Popup");
        left.requestWidgetSettingsDiscard();check(left.widgetSettingsDiscardPending,"discard confirmation");left.keepWidgetSettings();check(left.widgetSettingsDirty && !left.widgetSettingsDiscardPending,"canceled discard retains input");
        Settings.setBindingsUnresolved(false);stage=7;left.saveWidgetSettings();
      }else if(stage===7){
        check(result.status!=="failed" && !left.widgetSettingsDirty,"actual same-session retry receipt");
      }else if(stage===8){
        refused(result);check(left.widgetSettingsDirty && Settings.data.controlCenter.shortcuts.left[0].i4Explicit===undefined,"stale field does not overwrite foreign row");
        left.requestWidgetSettingsDiscard();check(left.confirmWidgetSettingsDiscard(),"stale pending input explicitly discarded");
      }
    }catch(error){fail(error);}
  }
  function settingsClosed(){
    if(stage===7){
      later(function(){
        check(!left.widgetSettingsVisible && Settings.data.controlCenter.shortcuts.left[0].opaque.keep,"acknowledged close keeps unknown row");
        stage=8;left.openWidgetSettings(0,Settings.data.controlCenter.shortcuts.left[0]);
        Settings.data.controlCenter.shortcuts.left=[{id:"CustomButton",tag:"foreign",opaque:{keep:true}}];
      });
    }else if(stage===8){later(saveFinal);}
  }
  function finalChecks(){
    var l=Settings.data.controlCenter.shortcuts.left,r=Settings.data.controlCenter.shortcuts.right;
    check(l.length===1 && l[0].tag==="foreign" && l[0].opaque.keep && l[0].i4Explicit===undefined,"final foreign row retained");
    check(r.length===2 && r[0].tag==="first" && r[0].opaque.keep && r[1].id==="DarkMode","final transferred and inserted consumers");
  }
  function saveFinal(){finalChecks();Settings.saveResult(function(result){try{check(result.status!=="failed","final save receipt");finalChecks();console.log("I4_CC_COLUMNS: SAVED_PASS");Qt.exit(0);}catch(error){fail(error);}});}
  Connections{target:Settings;function onSettingsLoaded(){root.begin();}}
  Component.onCompleted:begin()
  Timer{interval:90000;running:true;onTriggered:root.fail("control-center watchdog");}
}
