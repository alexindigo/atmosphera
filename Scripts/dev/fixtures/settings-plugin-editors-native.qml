import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins

// Native equivalent of the retained old-owner plugin-settings-editors fixture.
Scope {
  id: root
  property bool started: false
  property var api: null
  property var consumer: null
  property bool faultBlocked: false
  property var afterFault: null
  property bool exitAfterRepair: false
  readonly property string key: "i4-editors"
  readonly property bool cold: Quickshell.env("I4_VERIFY") === "1"
  readonly property var placements: [{kind:"bar",list:"global",section:"left",index:0},{kind:"bar",list:"I4-screen",section:"left",index:0},{kind:"controlCenter",section:"left",index:0},{kind:"desktop",screenName:"I4-screen",index:0}]
  readonly property var names: ["global-saved","screen-saved","control-saved","desktop-saved"]
  readonly property string globalConsumer: consumer ? consumer.values.label : ""
  FileView {id:manifestFile;path:Settings.configDir+"plugins/i4-editors/manifest.json";blockLoading:true}
  function check(ok,label){if(!ok)throw new Error("I4_PLUGIN_EDITORS_ASSERT: "+label);}
  function fail(error){console.error(String(error));if(faultBlocked&&!faultProcess.running){exitAfterRepair=true;fault("repair",function(){});return;}Qt.exit(2);}
  function guard(callback){try{callback();}catch(error){fail(error);}}
  function register(owner){
    check(owner!==null,"actual native shared owner");manifestFile.waitForJob();api=Service.createPluginAPI(key,JSON.parse(manifestFile.text()),owner,{},{},{});
    var loaded=Object.assign({},Service.loadedPlugins);loaded[key]={api:api};Service.loadedPlugins=loaded;
  }
  function row(tag){return {id:"plugin:"+key,tag:tag,instanceSettings:{label:"original",opaque:{keep:true}}};}
  function ownerValue(index){return index===0?Settings.data.bar.widgets.left:index===1?Settings.data.bar.screenOverrides:index===2?Settings.data.controlCenter.shortcuts.left:Settings.data.desktopWidgets.monitorWidgets;}
  function setOwner(index,value){if(index===0)Settings.data.bar.widgets.left=value;else if(index===1)Settings.data.bar.screenOverrides=value;else if(index===2)Settings.data.controlCenter.shortcuts.left=value;else Settings.data.desktopWidgets.monitorWidgets=value;}
  function open(index,callback){
    if(index<0){
      function settled(){return api.settingsOwner.store.settingsKeys.every(function(key){var info=api.settingsHandle.info([key]);return info.latestInput.length<info.workerCovered.length||(info.latestInput.length===info.workerCovered.length&&info.latestInput<=info.workerCovered);});}
      if(!settled()){
        function completed(){if(!settled())return;api.settingsHandle.completed.disconnect(completed);Qt.callLater(function(){root.guard(function(){root.open(index,callback);});});}
        api.settingsHandle.completed.connect(completed);return;
      }
    }
    var editor=index<0?api.createSettingsEditor():PluginInstances.createSettingsEditor(key,placements[index],api);
    check(editor!==null,"factory "+index);
    editor.whenReady(function(result){guard(function(){check(result.status==="opened","opened "+index+" "+JSON.stringify(result));callback(editor);});});
  }
  function apply(editor,callback){editor.apply(editor.values,function(result){guard(function(){callback(result);});});}
  function begin(){
    if(started||!Settings.isLoaded)return;started=true;
    Service._openSettingsOwner(key,function(owner){guard(function(){
      register(owner);if(cold){finalChecks(function(){console.log("I4_PLUGIN_EDITORS: RESTART_PASS");Qt.exit(0);});return;}
      Settings.data.bar.widgets.left=[row("first"),row("second")];
      Settings.data.bar.screenOverrides=[{name:"I4-screen",opaque:"monitor",widgets:{left:[row("screen")],center:[],right:[]}}];
      Settings.data.controlCenter.shortcuts.left=[row("control")];Settings.data.desktopWidgets.monitorWidgets=[{name:"I4-screen",opaque:"desktop-monitor",widgets:[row("desktop")]}];
      Settings.saveResult(function(result){guard(function(){check(result.status==="saved","baseline save");placementABA(0);});});
    });});
  }
  function placementABA(index){
    if(index===placements.length){cancelAndShared();return;}
    open(index,function(editor){var before=Settings.store.copyValue(ownerValue(index)),foreign=Settings.store.copyValue(before);foreign[0].abaWitness=true;
      setOwner(index,foreign);setOwner(index,before);editor.values.label="must-not-recapture-after-ABA";
      apply(editor,function(result){check(result.status==="failed"&&result.error.code==="overlay-conflict","captured ABA "+index);check(JSON.stringify(ownerValue(index))===JSON.stringify(before),"ABA owner unchanged "+index);editor.discard();placementABA(index+1);});
    });
  }
  function cancelAndShared(){open(-1,function(cancelled){
    check(cancelled.initialValue.label==="shared","shared baseline");cancelled.initialValue.nested.base=false;check(api.pluginSettings.nested.base&&cancelled.discard(),"detached Cancel no live mutation");
    open(-1,function(editor){editor.values.label="shared-saved";apply(editor,function(result){check(result.status==="saved"&&result.refreshState==="current","shared Apply");check(api.pluginSettings.label==="shared-saved"&&api.pluginSettings.nested.base,"shared consumer");editor.discard();staleRefresh();});});
  });}
  function staleRefresh(){open(-1,function(editor){
    editor.values.label="submitted-stale";
    apply(editor,function(result){check(result.status==="saved"&&result.refreshState==="stale","saved but stale refresh");check(api.pluginSettings.label==="later-preview","newer API input wins");editor.discard();
      open(-1,function(current){current.values.label="shared-saved";apply(current,function(saved){check(saved.status==="saved"&&saved.refreshState==="current","explicit latest editor");current.discard();placementConflict();});});
    });api.pluginSettings.label="later-preview";
  });}
  function placementConflict(){open(0,function(editor){
    var before=Settings.store.copyValue(Settings.data.bar.widgets.left);Settings.data.bar.widgets.left=[before[1],before[0]];editor.values.label="must not overwrite repeated ID";
    apply(editor,function(result){check(result.status==="failed"&&result.error.code==="overlay-conflict","repeated-ID fence");check(Settings.data.bar.widgets.left[0].tag==="second"&&Settings.data.bar.widgets.left[0].instanceSettings.label==="original","replacement retained");editor.discard();Settings.data.bar.widgets.left=before;baseConflict();});
  });}
  function baseConflict(){open(1,function(editor){api.pluginSettings.label="foreign";apply(editor,function(result){
    check(result.status==="failed"&&result.error.code==="overlay-conflict","shared-base fence");editor.discard();api.pluginSettings.label="shared-saved";
    api.saveSettings(function(saved){guard(function(){check(saved.status!=="failed","restore shared choice");unloadConflict();});});
  });});}
  function unloadConflict(){open(2,function(editor){
    var loaded=Object.assign({},Service.loadedPlugins);delete loaded[key];Service.loadedPlugins=loaded;Service.unloadPlugin(key,true);
    apply(editor,function(result){check(result.status==="failed","actual base unload refuses");editor.discard();Service._openSettingsOwner(key,function(owner){guard(function(){register(owner);failureRetry();});});});
  });}
  function failureRetry(){PluginInstances.openRuntime(api,placements[0],function(opened){guard(function(){
    check(opened.status==="opened","runtime consumer opened");consumer=opened.editor;
    open(0,function(editor){editor.values.label=names[0];fault("block",function(){apply(editor,function(failed){
      check(failed.status==="failed"&&failed.refreshState==="not_refreshed","failed real save no refresh");check(editor.values.label===names[0]&&editor.dirty,"native editor retains latest work");
      fault("repair",function(){apply(editor,function(result){check((result.status==="saved"||result.status==="nothing_to_save")&&result.refreshState==="current","same-editor Retry");check(globalConsumer===names[0],"runtime consumer sees Retry");editor.discard();applyPlacement(1);});});
    });});});
  });});}
  function applyPlacement(index){
    if(index===placements.length){open(3,function(reset){reset.resetOverrides(function(result){guard(function(){check(result.status==="saved"&&result.refreshState==="current","instance reset");reset.discard();finalChecks(function(){console.log("I4_PLUGIN_EDITORS: SAVED_PASS");Qt.exit(0);});});});});return;}
    open(index,function(editor){editor.values.label=names[index];apply(editor,function(result){check(result.status==="saved"&&result.refreshState==="current","placement receipt "+index);editor.discard();applyPlacement(index+1);});});
  }
  function finalChecks(done){
    check(api.pluginSettings.label==="shared-saved"&&api.pluginSettings.nested.base,"shared saved/cold consumer");check(Settings.data.bar.widgets.left[1].tag==="second","repeated sibling");
    check(Settings.data.bar.screenOverrides[0].opaque==="monitor"&&Settings.data.desktopWidgets.monitorWidgets[0].opaque==="desktop-monitor","unknown ancestry");
    function next(index){
      if(index===placements.length){done();return;}var entry=PluginInstances.entryFor(placements[index]);
      if(index<3)check(entry.instanceSettings.opaque.keep&&entry.instanceSettings.nested===undefined,"opaque/sparse override "+index);else check(entry.instanceSettings===undefined,"reset removes override");
      PluginInstances.openRuntime(api,placements[index],function(result){guard(function(){check(result.status==="opened","final consumer "+index);check(result.editor.values.label===(index<3?names[index]:"shared-saved")&&result.editor.values.nested.base,"native effective value "+index);result.editor.detach();next(index+1);});});
    }next(0);
  }
  function fault(mode,callback){afterFault=callback;faultProcess.command=["python3","-B",Quickshell.env("I5_DESKTOP_FAULT"),Quickshell.env("ATMOSPHERA_CONFIG_DIR"),mode];faultProcess.running=true;}
  Process {id:faultProcess;onExited:code=>{guard(function(){check(code===0,"IO fault prerequisite");faultBlocked=command[command.length-1]==="block";if(exitAfterRepair){Qt.exit(2);return;}var callback=afterFault;afterFault=null;callback();});}}
  Connections {target:Settings;function onSettingsLoaded(){root.begin();}}
  Component.onCompleted:begin()
  Timer {interval:100000;running:true;onTriggered:root.fail("I4_PLUGIN_EDITORS_ASSERT: watchdog")}
}
