// Inert receipt-boundary witness; relocated to the shell root in the test VM.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Item {
  id: root
  property bool started: false
  property int savedSignals: 0
  property int failedSignals: 0
  property bool faultBlocked: false
  property bool exitAfterRepair: false
  property var afterFault: null
  readonly property string seenDefault: Settings.data.ui.fontDefault
  readonly property string seenFixed: Settings.data.ui.fontFixed
  readonly property bool verifyOnly: Quickshell.env("I4_VERIFY") === "1"
  function check(ok, name) { if (!ok) throw new Error("I4_OPTIONAL_CALLBACK_ASSERT: " + name); }
  function fail(error) {console.error(String(error));if(faultBlocked&&!faultProcess.running){exitAfterRepair=true;fault("repair",function(){});return;}Qt.exit(2);}
  function commandOwner(): var { return Settings; }
  function finalChecks() {
    check(seenDefault === "I4 Callback Sans final" && seenFixed === "I4 Callback Mono final", "bound final consumers");
    if (typeof root.commandOwner().createRecordListEditor === "function")
      check(Settings.data.bar.widgets.left[0].optionalCallback === true, "record-list consumer after optional callback");
  }
  // Explicit ordered receipts fence the observer-free work. Global save signals
  // are observable notifications, not a request-identity or signal-count protocol.
  function fence(next) {
    var sync = true;
    Settings.saveResult(function (result) {
      try { check(!sync, "asynchronous completion"); next(result); } catch (error) { fail(error); }
    });
    sync = false;
  }
  function finalSave() {
    var invalid = 0;
    check(Settings.saveSetupWork({}, null, "") === false, "missing setup id without callback refuses");
    var sync = true;
    Settings.saveSetupWork({}, function (result) { check(!sync && result.status === "failed" && typeof result.error.code === "string", "ordered async native missing-ID failure"); invalid++; }, "");
    check(invalid === 0, "missing-ID completion is not inline");
    sync = false;
    var before = savedSignals;
    Settings.data.ui.fontFixed = "I4 Callback Mono final";
    fence(function (result) {
      check(result.status === "saved" && savedSignals > before && failedSignals > 0 && invalid === 1, "signal-before-callback and failure observability");
      finalChecks();
      console.log("I4_OPTIONAL_CALLBACKS: SAVED_PASS");
      Qt.exit(0);
    });
  }
  function recordCallbacks() {
    // This witness is introduced with scalar editors. The later selected-list
    // API is exercised as soon as its owning preparation commit is present.
    if (typeof root.commandOwner().createRecordListEditor !== "function") {
      finalSave();
      return;
    }
    Settings.data.bar.widgets.left = [{id: "Volume"}];
    recordWait.start();
  }
  Timer {
    id:recordWait;interval:20;repeat:true
    onTriggered:{try{
      var commands=root.commandOwner().createRecordListEditor(["bar","widgets","left"],[]);
      if(!commands)return;stop();root.recordReady(commands);
    }catch(error){stop();root.fail(error);}}
  }
  function recordReady(commands) {
    check(commands.submit([{op: "set", index: 0, field: "optionalCallback", value: true}]), "omitted list observer admission");
    fence(function (result) {
      check(result.status !== "failed" && Settings.data.bar.widgets.left[0].optionalCallback === true, "omitted list observer completes");
      commands.detach();
      check(commands.submit([{op: "remove", index: 0}], {}) === false, "closed list without callback refuses");
      fence(function (again) {
        check(again.status !== "failed" && Settings.data.bar.widgets.left.length === 1, "refusal does not mutate owner");
        finalSave();
      });
    });
  }
  function scalarCallback() {
    var editor = Settings.createEditor("ui.fontDefault");
    editor.apply("I4 Callback Sans final");
    fence(function (result) {
      check(result.status !== "failed" && editor.discard() === true, "omitted scalar observer settles busy state");
      editor.apply("must-not-land", false);
      check(seenDefault === "I4 Callback Sans final", "closed scalar without callback refuses");
      recordCallbacks();
    });
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    try {
      if (verifyOnly) {
        finalChecks();
        console.log("I4_OPTIONAL_CALLBACKS: RESTART_PASS");
        Qt.exit(0);
        return;
      }
      Settings.data.ui.fontDefault = "I4 Callback Sans";
      Settings.saveResult();
      fence(function (first) {
        check(first.status !== "failed" && seenDefault === "I4 Callback Sans", "omitted save observer completes");
        fault("block",function () {
        Settings.data.ui.fontFixed = "I4 Callback Mono failed receipt";
        Settings.saveResult({not: "a function"});
        fence(function (failed) {
          check(failed.status === "failed" && failedSignals > 0 && seenFixed === "I4 Callback Mono failed receipt", "failure and admitted work stay observable");
          fault("repair",function () {
          Settings.data.ui.fontFixed = "I4 Callback Mono";
          Settings.saveResult("not a callback");
          fence(function (retried) { check(retried.status !== "failed", "nonfunction observer save retry"); scalarCallback(); });
          });
        });
        });
      });
    } catch (error) { fail(error); }
  }
  Connections {
    target: Settings
    function onSettingsLoaded() { root.begin(); }
    function onSettingsSaved() { root.savedSignals++; }
    function onSettingsSaveFailed(message) { root.failedSignals++; }
  }
  Component.onCompleted: begin()
  function fault(mode,callback){afterFault=callback;faultProcess.command=["python3","-B",Quickshell.env("I5_DESKTOP_FAULT"),Quickshell.env("ATMOSPHERA_CONFIG_DIR"),mode];faultProcess.running=true;}
  Process {
    id:faultProcess
    onExited:code=>{try{
      root.check(code===0,"private real-IO fault prerequisite");root.faultBlocked=command[command.length-1]==="block";
      if(root.exitAfterRepair){Qt.exit(2);return;}var callback=root.afterFault;root.afterFault=null;callback();
    }catch(error){root.fail(error);}}
  }
  Timer { interval: 90000; running: true; onTriggered: root.fail("optional callback watchdog") }
}
