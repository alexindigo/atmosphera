import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins

// Actual consumers of stable native namespace notifications, not API replacement.
ShellRoot {
  id: root
  property var names:["hermes-ssh-chat","niri-screensaver"]
  property int index:0
  property var api:null
  property var consumer:null
  property var namespaceIdentity:null
  property bool started:false
  property string phase:"start"
  readonly property bool cold:Quickshell.env("I4_VERIFY")==="1"
  FileView {id:manifest;blockLoading:true;printErrors:false}
  FileView {id:config;printErrors:false}
  function check(ok,message){if(!ok)throw new Error("I5_PLUGIN_NOTIFICATIONS_ASSERT: "+names[index]+" "+message);}
  function fail(error){console.error(String(error));Qt.exit(2);}
  function next(){
    if(index===names.length){console.log("I5_PLUGIN_NOTIFICATIONS: "+(cold?"RESTART_PASS":"SAVED_PASS"));Qt.exit(0);return;}
    var name=names[index];phase="opening";
    Service._openSettingsOwner(name,function(owner){try{
      check(owner!==null,"native owner opened");manifest.path=Registry.getPluginDir(name)+"/manifest.json";manifest.waitForJob();
      api=Service.createPluginAPI(name,JSON.parse(manifest.text()),owner,{},{},{});
      var loaded=Object.assign({},Service.loadedPlugins);loaded[name]={api:api};Service.loadedPlugins=loaded;
      namespaceIdentity=api.pluginSettings;
      var file=index===0?"Panel.qml":"Main.qml";
      var component=Qt.createComponent("file://"+Registry.getPluginDir(name)+"/"+file);
      check(component.status===Component.Ready,component.errorString());consumer=component.createObject(root,{pluginApi:api});check(consumer!==null,"actual consumer constructed");
      if(cold){phase="observing";return;}
      if(index===0){
        consumer.valueHost="local-buffer";consumer.valuePort=1000;consumer.valueUser="local-user";consumer.terminalCols=90;consumer.terminalRows=20;consumer.terminalFontSize=8;
        api.pluginSettings.host="notification.invalid";api.pluginSettings.port=2222;api.pluginSettings.user="fixture-user";api.pluginSettings.terminalCols=150;api.pluginSettings.terminalRows=40;api.pluginSettings.terminalFontSize=13;
        phase="observing";
      }else{api.pluginSettings.frameRate=31;phase="first-config";}
    }catch(error){fail(error);}});
  }
  function drive(){try{
    if(phase==="first-config"||phase==="observing"&&index===1){
      config.path=consumer.configFile;config.reload();config.waitForJob();
      var rate=phase==="first-config"?31:47;
      if(config.text().indexOf('FRAME_RATE="'+rate+'"')===-1)return;
      if(phase==="first-config"){api.pluginSettings.frameRate=47;phase="observing";return;}
    }
    if(phase!=="observing")return;
    check(api.pluginSettings===namespaceIdentity,"namespace identity unchanged");
    if(index===0)check(consumer.valueHost==="notification.invalid"&&consumer.valuePort===2222&&consumer.valueUser==="fixture-user"&&consumer.terminalCols===150&&consumer.terminalRows===40&&consumer.terminalFontSize===13,"all six actual local consumers update");
    else check(api.pluginSettings.frameRate===47,"actual shell config tracks second field publication");
    phase="saving";
    api.saveSettings(function(result){try{check(result.status===(cold?"nothing_to_save":"saved"),"acknowledged preference persistence "+result.status);consumer.destroy();consumer=null;index++;next();}catch(error){fail(error);}});
  }catch(error){fail(error);}}
  function begin(){if(started||!Settings.isLoaded)return;started=true;next();}
  Connections {target:Settings;function onSettingsLoaded(){root.begin();}}
  Component.onCompleted:begin()
  Timer {interval:25;running:true;repeat:true;onTriggered:root.drive()}
  Timer {interval:30000;running:true;onTriggered:root.fail("notification consumer watchdog "+root.phase)}
}
