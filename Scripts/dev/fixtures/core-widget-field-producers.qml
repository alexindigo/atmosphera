// Actual core pages/controls -> selected owner -> files -> independent restart.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI
import qs.Modules.Panels.Settings.Bar.WidgetSettings as B
import qs.Modules.Panels.Settings.DesktopWidgets.WidgetSettings as D
import qs.Modules.Panels.Settings.ControlCenter.WidgetSettings as C
import qs.Modules.Panels.Settings.Tabs.ControlCenter as CC

PanelWindow {
  id: root
  implicitWidth: 1000; implicitHeight: 750
  property bool started: false
  property bool iconsReady: false
  property string phase: "idle"
  property int index: -1
  property var page: null
  property var editor: null
  property var fields: ({})
  property var expectedKeys: []
  property int signals: 0
  property var liveDialog: null
  property int barStage: 0
  property int volumeIndex: 0
  property bool verifyOnly: Quickshell.env("I4_VERIFY") === "1"
  readonly property var screenObject: Quickshell.screens[0]
  CC.ControlCenterTab { id: ccOwner; visible: false }
  Item { id: scene; anchors.fill: parent }
  QtObject { id: popupHost; readonly property var dialogParent: scene; function hideDynamicMenu() {} function showDialog(dialog) {root.liveDialog=dialog;} }
  FileView { path: Quickshell.env("I4_ICON_DATA"); onLoaded: { IconRegistry.register("fixture:atmosphera-icons",JSON.parse(text()),Quickshell.env("I4_ICON_DIR"));root.iconsReady=true;root.begin(); } }

  // Fields are semantic control contracts, independent of the page serializer.
  property var cases: [
    {id:"ActiveWindow",c:active,kind:"NComboBox",field:"hideMode"},
    {id:"AudioVisualizer",c:audio,kind:"NTextInput",field:"width"},
    {id:"Battery",c:battery,kind:"NComboBox",field:"deviceNativePath"},
    {id:"Bluetooth",c:bluetooth,kind:"NComboBox",field:"displayMode"},
    {id:"Brightness",c:brightness,kind:"NComboBox",field:"displayMode"},
    {id:"Clock",c:clock,kind:"NColorChoice",field:"clockColor"},
    {id:"ControlCenter",c:control,kind:"NToggle",field:"useDistroLogo"},
    {id:"CustomButton",c:custom,kind:"NTextInput",field:"leftClickExec"},
    {id:"DarkMode",c:dark,kind:"NColorChoice",field:"iconColor"},
    {id:"InputMethod",c:inputMethod,kind:"NComboBox",field:"displayMode"},
    {id:"KeepAwake",c:awake,kind:"NColorChoice",field:"iconColor"},
    {id:"KeyboardLayout",c:keyboard,kind:"NComboBox",field:"displayMode"},
    {id:"Launcher",c:launcher,kind:"NToggle",field:"useDistroLogo"},
    {id:"LockKeys",c:locks,kind:"NToggle",field:"showCapsLock"},
    {id:"MediaMini",c:media,kind:"NComboBox",field:"hideMode"},
    {id:"Microphone",c:microphone,kind:"NComboBox",field:"displayMode"},
    {id:"Network",c:network,kind:"NComboBox",field:"displayMode"},
    {id:"NightLight",c:night,kind:"NColorChoice",field:"iconColor"},
    {id:"AtmospheraPerformance",c:performance,kind:"NColorChoice",field:"iconColor"},
    {id:"NotificationHistory",c:notification,kind:"NToggle",field:"showUnreadBadge"},
    {id:"PowerProfile",c:power,kind:"NColorChoice",field:"iconColor"},
    {id:"SessionMenu",c:session,kind:"NColorChoice",field:"iconColor"},
    {id:"Settings",c:settings,kind:"NColorChoice",field:"iconColor"},
    {id:"Spacer",c:spacer,kind:"NTextInput",field:"width"},
    {id:"SystemMonitor",c:system,kind:"NToggle",field:"compactMode"},
    {id:"Taskbar",c:taskbar,kind:"NComboBox",field:"hideMode"},
    {id:"Tray",c:tray,kind:"NToggle",field:"drawerEnabled"},
    {id:"Volume",c:volume,kind:"NComboBox",field:"displayMode"},
    {id:"VPN",c:vpn,kind:"NComboBox",field:"displayMode"},
    {id:"WallpaperSelector",c:wallpaper,kind:"NColorChoice",field:"iconColor"},
    {id:"Workspace",c:workspace,kind:"NComboBox",field:"labelMode"},
    {id:"Clock",group:"desktop",c:dclock,kind:"NComboBox",field:"clockStyle"},
    {id:"MediaPlayer",group:"desktop",c:dmedia,kind:"NToggle",field:"showBackground"},
    {id:"Weather",group:"desktop",c:dweather,kind:"NToggle",field:"showBackground"},
    {id:"SystemStat",group:"desktop",c:dstat,kind:"NComboBox",field:"statType"},
    {id:"AudioVisualizer",group:"desktop",c:daudio,kind:"NTextInput",field:"width"},
    {id:"AppShortcut",group:"desktop",c:app,kind:"NTextInput",field:"customLabel",label:"panels.desktop-widgets.app-shortcut-custom-label"},
    {id:"CustomButton",group:"cc",c:cccustom,kind:"NTextInput",field:"generalTooltipText"}
  ]
  Component { id: active; B.ActiveWindowSettings { onSettingsChanged: root.record(settings) } }
  Component { id: audio; B.AudioVisualizerSettings { onSettingsChanged: root.record(settings) } }
  Component { id: battery; B.BatterySettings { onSettingsChanged: root.record(settings) } }
  Component { id: bluetooth; B.BluetoothSettings { onSettingsChanged: root.record(settings) } }
  Component { id: brightness; B.BrightnessSettings { onSettingsChanged: root.record(settings) } }
  Component { id: clock; B.ClockSettings { onSettingsChanged: root.record(settings) } }
  Component { id: control; B.ControlCenterSettings { onSettingsChanged: root.record(settings) } }
  Component { id: custom; B.CustomButtonSettings { onSettingsChanged: root.record(settings) } }
  Component { id: dark; B.DarkModeSettings { onSettingsChanged: root.record(settings) } }
  Component { id: inputMethod; B.InputMethodSettings { onSettingsChanged: root.record(settings) } }
  Component { id: awake; B.KeepAwakeSettings { onSettingsChanged: root.record(settings) } }
  Component { id: keyboard; B.KeyboardLayoutSettings { onSettingsChanged: root.record(settings) } }
  Component { id: launcher; B.LauncherSettings { onSettingsChanged: root.record(settings) } }
  Component { id: locks; B.LockKeysSettings { onSettingsChanged: root.record(settings) } }
  Component { id: media; B.MediaMiniSettings { onSettingsChanged: root.record(settings) } }
  Component { id: microphone; B.MicrophoneSettings { onSettingsChanged: root.record(settings) } }
  Component { id: network; B.NetworkSettings { onSettingsChanged: root.record(settings) } }
  Component { id: night; B.NightLightSettings { onSettingsChanged: root.record(settings) } }
  Component { id: performance; B.NoctaliaPerformanceSettings { onSettingsChanged: root.record(settings) } }
  Component { id: notification; B.NotificationHistorySettings { onSettingsChanged: root.record(settings) } }
  Component { id: power; B.PowerProfileSettings { onSettingsChanged: root.record(settings) } }
  Component { id: session; B.SessionMenuSettings { onSettingsChanged: root.record(settings) } }
  Component { id: settings; B.SettingsSettings { onSettingsChanged: root.record(settings) } }
  Component { id: spacer; B.SpacerSettings { onSettingsChanged: root.record(settings) } }
  Component { id: system; B.SystemMonitorSettings { onSettingsChanged: root.record(settings) } }
  Component { id: taskbar; B.TaskbarSettings { onSettingsChanged: root.record(settings) } }
  Component { id: tray; B.TraySettings { onSettingsChanged: root.record(settings) } }
  Component { id: volume; B.VolumeSettings { onSettingsChanged: root.record(settings) } }
  Component { id: vpn; B.VPNSettings { onSettingsChanged: root.record(settings) } }
  Component { id: wallpaper; B.WallpaperSelectorSettings { onSettingsChanged: root.record(settings) } }
  Component { id: workspace; B.WorkspaceSettings { onSettingsChanged: root.record(settings) } }
  Component { id: dclock; D.ClockSettings { onSettingsChanged: root.record(settings) } }
  Component { id: dmedia; D.MediaPlayerSettings { onSettingsChanged: root.record(settings) } }
  Component { id: dweather; D.WeatherSettings { onSettingsChanged: root.record(settings) } }
  Component { id: dstat; D.SystemStatSettings { onSettingsChanged: root.record(settings) } }
  Component { id: daudio; D.AudioVisualizerSettings { onSettingsChanged: root.record(settings) } }
  Component { id: app; D.AppShortcutSettings { onSettingsChanged: root.record(settings) } }
  Component { id: cccustom; C.CustomButtonSettings { onSettingsChanged: root.record(settings) } }

  function check(ok,label) { if(!ok)throw new Error("I4_CORE_FIELD_ASSERT: "+label); }
  function fail(error) { console.error(String(error));Qt.exit(2); }
  function later(next) { Qt.callLater(function(){try{next();}catch(error){fail(error);}}); }
  function kind(item,name) { return String(item).indexOf(name+"_QMLTYPE")===0; }
  function find(item,predicate) { if(predicate(item))return item;var children=item.children||[];for(var i=0;i<children.length;i++){var found=find(children[i],predicate);if(found)return found;}return null; }
  function record(patch) {
    try {
      check(phase==="action","no lifecycle field emission: "+index+"/"+phase);
      check(patch && Object.keys(patch).sort().join(',')===expectedKeys.slice().sort().join(','),"only the named user fields: "+index+" "+JSON.stringify(patch));
      Object.keys(patch).forEach(function(key){fields[key]=patch[key];});signals++;
    } catch(error) { fail(error); }
  }
  function rowFor(c) { return {id:c.id,opaque:{keep:true}}; }
  function metadata(c) { return c.group==="desktop"?DesktopWidgetRegistry.widgetMetadata[c.id]:c.group==="cc"?ControlCenterWidgetRegistry.widgetMetadata[c.id]:BarWidgetRegistry.widgetMetadata[c.id]; }
  function ownerIndex(c) { return cases.slice(0,index).filter(function(other){return (other.group||"bar")===(c.group||"bar");}).length; }
  function savedRow(c,n) { return c.group==="desktop"?Settings.data.desktopWidgets.monitorWidgets[0].widgets[n]:c.group==="cc"?Settings.data.controlCenter.shortcuts.left[n]:Settings.data.bar.widgets.left[n]; }
  function begin() {
    if(started||!iconsReady||!Settings.isLoaded)return;started=true;
    try {
      if(verifyOnly){finalChecks();console.log("I4_CORE_FIELDS: RESTART_PASS");Qt.exit(0);return;}
      var bar=[],desktop=[],cc=[];
      cases.forEach(function(c){var row=rowFor(c);if(c.id==="AppShortcut")row.appId="i4.app";if(c.group==="desktop")desktop.push(row);else if(c.group==="cc")cc.push(row);else bar.push(row);});
      Settings.data.bar.widgets.left=bar;
      Settings.data.desktopWidgets.monitorWidgets=[{name:screenObject.name,opaque:"monitor",widgets:desktop}];
      Settings.data.controlCenter.shortcuts.left=cc;
      if (Quickshell.env("I4_PARENT") === "1")
        index = cases.findIndex(function (c) { return c.id === "Volume" && !c.group; }) - 1;
      next();
    }catch(error){fail(error);}
  }
  function next() {
    if(page){page.destroy();page=null;}if(editor){editor.detach();editor=null;}
    index++;
    if(index===cases.length){specialNumericClose();return;}
    var c=cases[index],n=ownerIndex(c);phase="construct";fields={};signals=0;
    editor=c.group==="desktop"?DesktopWidgetRegistry.createWidgetSettingsEditor(screenObject.name,n):c.group==="cc"?ccOwner.captureWidgetSettings("left",n):BarService.createWidgetSettingsEditor("","left",n);
    check(editor!==null,"actual selected editor");
    var props={widgetData:editor.initialValue,widgetMetadata:metadata(c)};if(!c.group)props.screen=screenObject;
    page=c.c.createObject(scene,props);check(page!==null,"actual page constructor "+c.id);
    settle.restart();
  }
  Timer { id:settle;interval:100;onTriggered:{try{root.untouched();}catch(error){root.fail(error);}} }
  function untouched() {
    var c=cases[index];phase="untouched-close";
    if(typeof page.saveSettings==="function")page.saveSettings();else page.save();
    check(signals===0,"untouched close has no intent");
    phase="metadata";var changed=Object.assign({},metadata(c));
    if(typeof changed[c.field]==="boolean")changed[c.field]=!changed[c.field];
    else if(typeof changed[c.field]==="number")changed[c.field]+=1;
    else if(changed[c.field]!==undefined)changed[c.field]=changed[c.field];
    page.widgetMetadata=changed;later(userAction);
  }
  function userAction() {
    var c=cases[index];check(signals===0,"metadata/binding refresh has no intent");
    var control=find(page,function(item){return kind(item,c.kind)&&(!c.label||item.label===I18n.tr(c.label));});
    check(control!==null,"actual control "+c.id+"/"+c.kind);
    if(c.kind==="NTextInput") {
      phase="programmatic";control.text="";check(signals===0,"programmatic text is not intent");
    }
    phase="action";expectedKeys=[c.field];
    if(c.kind==="NColorChoice")control.selected(control.currentKey);
    else if(c.kind==="NComboBox")control.selected(control.currentKey);
    else if(c.kind==="NToggle")control.toggled(control.checked);
    else control.inputItem.insert(0,c.field==="width"?"37":"explicit user text");
    if(typeof page.saveSettings==="function")page.saveSettings();else page.save();
    check(signals===1,"one action / one emission including explicit-equal "+c.id);
    if(c.kind==="NTextInput" && !(c.group==="desktop" && c.id==="AudioVisualizer"))textClearUndo(control);
    if(c.id==="Tray"&&!c.group)trayCollection();
    if(c.group==="cc")ccCollection();
    if(c.id==="Workspace")spinControl();
    if(c.id==="AppShortcut"){appCollections();return;}
    persist();
  }
  function appCollections() {
    expectedKeys=["appId","params"];
    var appPicker=find(page,function(item){return kind(item,"NSearchableComboBox")&&item.placeholder===I18n.tr("panels.desktop-widgets.app-shortcut-application-placeholder");});
    check(appPicker!==null,"actual application picker");appPicker.selected("i4.app");
    expectedKeys=["params"];
    var add=find(page,function(item){return kind(item,"NButton")&&item.text===I18n.tr("panels.desktop-widgets.app-shortcut-params-add");});check(add!==null,"actual params add");add.clicked();
    later(function(){
      var input=find(page,function(item){return kind(item,"NTextInput")&&item.placeholderText===I18n.tr("panels.desktop-widgets.app-shortcut-params-placeholder");});check(input!==null,"actual params delegate");input.inputItem.insert(0,"--flag");
      check(fields.params.join(',')==="--flag","params field only");
      expectedKeys=["environmentVars"];
      var addEnv=find(page,function(item){return kind(item,"NButton")&&item.text===I18n.tr("panels.desktop-widgets.app-shortcut-env-var-add");});check(addEnv!==null,"actual environment add");addEnv.clicked();
      later(function(){
        var key=find(page,function(item){return kind(item,"NTextInput")&&item.placeholderText===I18n.tr("panels.desktop-widgets.app-shortcut-env-var-key-placeholder");});
        var value=find(page,function(item){return kind(item,"NTextInput")&&item.placeholderText===I18n.tr("panels.desktop-widgets.app-shortcut-env-var-value-placeholder");});
        check(key&&value,"actual environment delegates");key.inputItem.insert(0,"KEY");value.inputItem.insert(0,"value");
        check(fields.environmentVars[0].key==="KEY"&&fields.environmentVars[0].value==="value","environment field only");persist();
      });
    });
  }
  function trayCollection() {
    expectedKeys=["blacklist"];
    var input=find(page,function(item){return kind(item,"NTextInputButton");});check(input!==null,"tray add control");
    input.text="explicit-rule";input.buttonClicked();check(fields.blacklist[0]==="explicit-rule","collection field only");
  }
  function ccCollection() { expectedKeys=["stateChecksJson"];page.addStateCheck();check(JSON.parse(fields.stateChecksJson).length===1,"CC collection field only"); }
  function spinControl() {
    var spin=find(page,function(item){return kind(item,"NSpinBox");});check(spin!==null,"workspace spin");
    phase="programmatic-spin";spin.value=4;phase="action";expectedKeys=["characterCount"];
    spin.changeValue(1,1);check(fields.characterCount===5,"actual spin modification");
    var input=find(spin,function(item){return item.validator!==undefined && typeof item.insert==="function";});
    check(input!==null,"actual numeric input");
    var count=signals;input.text="5";spin.commitEdit();check(signals===count,"programmatic spin text is not intent");
    input.forceActiveFocus();input.text="";input.insert(0,"5");page.saveSettings();
    check(signals===count+1 && fields.characterCount===5,"typed equal numeric choice commits on close flush");
  }
  function textClearUndo(control) {
    var clear=find(control,function(item){return kind(item,"AtmoIconButton");});check(clear!==null,"actual clear action");
    var count=signals;
    clear.clicked();check(signals===count+1 && control.text==="","clear is one explicit user field emission");
    check(control.inputItem.canUndo,"native clear retains its undo group");
    // Native insert+clear coalesce, including on the prior control with real
    // uinput/Ctrl+Z. Undo restores the original empty edit-group base, not37.
    control.inputItem.undo();check(signals===count+2 && control.text==="","native undo group emits its restored field exactly once");
  }
  function persist() {
    var c=cases[index],n=ownerIndex(c);phase="save";
    check(editor.submit(fields,function(result){try{
      check(result.status!=="failed","actual owner save "+c.id);
      var row=savedRow(c,n);check(row.opaque.keep,"unknown row data retained");
      check(Object.keys(row).sort().join(',')===Object.keys(Object.assign({id:c.id,opaque:{}},c.id==="AppShortcut"?{appId:"i4.app"}:{},fields)).sort().join(','),"no unrelated/default field materialization "+c.id);
      later(next);
    }catch(error){fail(error);}}),"field admission "+c.id);
  }
  function specialNumericClose() {
    phase="numeric-popup";PanelService.registerPopupMenuWindow(screenObject,popupHost);
    var i=cases.filter(function(c){return c.group==="desktop";}).findIndex(function(c){return c.id==="AudioVisualizer";});
    DesktopWidgetRegistry.openWidgetSettings(screenObject,i,"AudioVisualizer",Settings.data.desktopWidgets.monitorWidgets[0].widgets[i]);
    numericWait.start();
  }
  Timer { id:numericWait;interval:150;onTriggered:{try{
    var dialog=DesktopWidgetRegistry.currentSettingsDialog;root.check(dialog&&dialog.visible,"actual numeric Popup");
    var height=root.find(dialog.contentItem,function(item){return root.kind(item,"NTextInput")&&item.label===I18n.tr("common.height");});root.check(height!==null,"actual numeric buffered field");
    height.text="";height.inputItem.insert(0,"81");dialog.saveAndClose();closedWait.start();
  }catch(error){root.fail(error);}} }
  Timer { id:closedWait;interval:50;repeat:true;onTriggered:{try{if(DesktopWidgetRegistry.currentSettingsDialog===null){stop();root.specialBarFailure();}}catch(error){stop();root.fail(error);}} }
  function specialBarFailure() {
    phase="bar-popup";barStage=1;Settings.setBindingsUnresolved(true);
    volumeIndex=cases.filter(function(c){return !c.group;}).findIndex(function(c){return c.id==="Volume";});
    BarService.openWidgetSettings(screenObject,"left",volumeIndex,"Volume",Settings.data.bar.widgets.left[volumeIndex]);barOpen.start();
  }
  function commandInput() {return find(liveDialog.contentItem,function(item){return kind(item,"NTextInput")&&item.label===I18n.tr("bar.custom-button.middle-click-label");});}
  Timer { id:barOpen;interval:150;onTriggered:{try{root.check(root.liveDialog&&root.liveDialog.visible,"actual bar Popup");var input=root.commandInput();root.check(input!==null,"actual Volume command input");input.text="";input.inputItem.insert(0,"first");}catch(error){root.fail(error);}} }
  Connections {
    target: root.liveDialog
    ignoreUnknownSignals: true
    function onSettingsSaveCompleted(result) {
      try {
        if(root.barStage===1){
          root.check(result.status==="failed"&&root.liveDialog.settingsDirty&&Settings.data.bar.widgets.left[root.volumeIndex].middleClickCommand==="first","producer-to-Popup failed input retained");
          root.barStage=2;var input=root.commandInput();input.text="";input.inputItem.insert(0,"newer");Settings.setBindingsUnresolved(false);root.liveDialog.saveAndClose();
        }else if(root.barStage===2){
          root.check(result.status!=="failed"&&Settings.data.bar.widgets.left[root.volumeIndex].middleClickCommand==="newer","newer producer input survives failed-save Retry");root.barStage=3;barClosed.start();
        }
      }catch(error){root.fail(error);}
    }
  }
  Timer { id:barClosed;interval:50;repeat:true;onTriggered:{try{if(!root.liveDialog||!root.liveDialog.visible){stop();root.finish();}}catch(error){stop();root.fail(error);}} }
  function finalChecks() {
    var bar=Settings.data.bar.widgets.left,desktop=Settings.data.desktopWidgets.monitorWidgets[0].widgets;
    check(bar.length===31&&desktop.length===6,"actual complete core map counts");
    var volume=bar.find(function(row){return row.id==="Volume";});
    check(volume.middleClickCommand==="newer"&&volume.iconColor===undefined&&volume.textColor===undefined,"producer Retry persists only touched fields");
    check(bar.find(function(row){return row.id==="Tray";}).blacklist[0]==="explicit-rule","tray field restart");
    check(bar.find(function(row){return row.id==="Workspace";}).characterCount===5,"spin field restart");
    check(desktop.find(function(row){return row.id==="AudioVisualizer";}).height===81,"typed buffered height survives close");
    var appRow=desktop.find(function(row){return row.id==="AppShortcut";});check(appRow.params[0]==="--flag"&&appRow.environmentVars[0].key==="KEY","app collection fields restart");
    check(Settings.data.controlCenter.shortcuts.left[0].stateChecksJson!==undefined,"CC collection restart");
    check(bar.every(function(row){return row.opaque.keep;})&&desktop.every(function(row){return row.opaque.keep;}),"unknown data at consumers");
  }
  function finish(){Settings.saveResult(function(result){try{check(result.status!=="failed","final save");finalChecks();console.log("I4_CORE_FIELDS: SAVED_PASS");Qt.exit(0);}catch(error){fail(error);}});}
  Connections { target:Settings;function onSettingsLoaded(){root.begin();} }
  Component.onCompleted:begin()
  Timer { interval:110000;running:true;onTriggered:root.fail("core field watchdog"); }
}
