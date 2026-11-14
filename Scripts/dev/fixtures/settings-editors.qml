// Inert real-component witness, copied to the candidate root by the VM driver.
import QtQuick
import Quickshell
import qs.Commons
import qs.Widgets
import qs.Modules.Panels.Settings.Tabs.Hooks as Hooks
import qs.Modules.Panels.Settings.Tabs.Idle as Idle

FloatingWindow {
  id: root
  implicitWidth: 900
  implicitHeight: 700
  visible: true
  property bool started: false
  property bool verifyOnly: Quickshell.env("I4_VERIFY") === "1"
  property var continuation: null
  property var predicate: null
  property int savedCount: 0
  property int signals: 0
  property int failures: 0
  property var heldCallback: null
  property string submitted: ""
  property string consumer: Settings.data.hooks.listeners.startup

  Item {
    id: container
    anchors.fill: parent
    Hooks.HookEditPopup {
      id: hook
      parent: container
      onSaved: root.savedCount++
    }
    Idle.IdleCommandEditPopup {
      id: idle
      parent: container
      onSaved: root.savedCount++
    }
    Idle.CustomSubTab {
      id: owner
      visible: false
    }
  }

  function check(ok, label) {
    if (!ok)
      throw new Error("I4_EDITOR_ASSERT: " + label);
  }

  function guard(callback) {
    try { callback(); } catch (error) { fail(error); }
  }

  function waitFor(condition, callback) {
    predicate = condition;
    continuation = callback;
    poll.start();
  }

  function finalChecks() {
    check(consumer === "printf I4-hook", "hook bound consumer");
    var entries = JSON.parse(Settings.data.idle.customCommands);
    check(entries.length === 1 && entries[0].name === "edited" && entries[0].timeout === 75 && entries[0].opaque === "keep", "idle final consumer and unknown field");
  }

  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    guard(function () {
      if (verifyOnly) {
        finalChecks();
        console.log("I4_EDITORS: RESTART_PASS");
        Qt.exit(0);
        return;
      }
      Settings.data.hooks.listeners.startup = "";
      Settings.data.idle.customCommands = '[{"name":"original","timeout":60,"command":"","resumeCommand":"","opaque":"keep"}]';
      var returned = false;
      Settings.saveResult(function (result) {
        root.guard(function () {
          root.check(returned && result.status === "saved" && root.signals > 0, "async saved receipt and signal-before-callback");
          var noOpReturned = false;
          Settings.saveResult(function (clean) {
            root.guard(function () {
              root.check(noOpReturned && clean.status === "nothing_to_save", "async truthful no-op");
              Settings.setBindingsUnresolved(true);
              var failedReturned = false;
              Settings.saveResult(function (failed) {
                root.guard(function () {
                  root.check(failedReturned && failed.status === "failed" && root.failures > 0, "async failed receipt and signal-before-callback");
                  Settings.setBindingsUnresolved(false);
                  root.cancelCase();
                });
              });
              failedReturned = true;
            });
          });
          noOpReturned = true;
        });
      });
      returned = true;
    });
  }

  function cancelCase() {
    var handle = Settings.createEditor("hooks.listeners.startup");
    check(hook.openEditor(handle, handle.initialValue), "open hook");
    hook.setValue("must not persist");
    hook.requestClose();
    check(hook.discardPending && hook.visible && consumer === "", "dirty close asks without writing");
    hook.keepEditing();
    check(!hook.discardPending && hook.visible, "keep editing retains popup");
    hook.requestClose();
    hook.confirmDiscard();
    check(!hook.visible && consumer === "" && savedCount === 0, "confirmed discard no owning write");
    heldCase();
  }

  function heldCase() {
    var fake = {
      apply: function (value, callback) {
        if (value === "reject input")
          throw new Error("injected ingress rejection");
        root.submitted = value;
        root.heldCallback = callback;
      },
      discard: function () { return true; }
    };
    hook.openEditor(fake, "base");
    hook.submit("owned submission");
    hook.setValue("later caller mutation");
    hook.submit("competing apply");
    hook.requestClose();
    check(hook.busy && hook.visible && !hook.discardPending && submitted === "owned submission", "busy retains submitted input and blocks competition");
    heldCallback({status: "failed", error: {code: "injected"}});
    check(!hook.busy && hook.visible && hook.saveFailed && savedCount === 0, "failure retains editor without saved");
    hook.submit("reject input");
    check(!hook.busy && hook.visible && hook.saveFailed && savedCount === 0, "synchronous rejection retains input and allows retry");
    hook.submit("retry");
    heldCallback({status: "saved", refreshState: "stale"});
    check(hook.visible && hook.saveFailed && savedCount === 0, "stale refresh does not close");
    hook.submit("retry");
    heldCallback({status: "nothing_to_save", refreshState: "current"});
    check(!hook.visible && savedCount === 1, "current no-op closes after receipt");
    conflictCase();
  }

  function conflictCase() {
    var editor = owner.createEntryEditor(0);
    check(editor !== null, "idle owner captures JSON leaf");
    idle.openEditor(editor, editor.initialValue, 0);
    Settings.data.idle.customCommands = '[{"name":"replacement","timeout":60,"command":"","resumeCommand":"","opaque":"keep"}]';
    idle.submit({name: "stale", timeout: 70, command: "", resumeCommand: ""});
    waitFor(function () { return idle.saveFailed; }, function () {
      root.check(idle.visible && root.savedCount === 1 && JSON.parse(Settings.data.idle.customCommands)[0].name === "replacement", "stale index cannot overwrite replacement");
      idle.requestClose();
      root.check(idle.discardPending, "failed input needs explicit discard");
      idle.confirmDiscard();
      root.realSaveCase();
    });
  }

  function realSaveCase() {
    var handle = Settings.createEditor("hooks.listeners.startup");
    hook.openEditor(handle, handle.initialValue);
    hook.submit("printf I4-hook");
    check(hook.busy && hook.visible && consumer === "printf I4-hook", "live preview waits for disk acknowledgement");
    waitFor(function () { return !hook.visible; }, function () {
      var editor = owner.createEntryEditor(0);
      idle.openEditor(editor, editor.initialValue, 0);
      idle.submit({name: "edited", timeout: 75, command: "", resumeCommand: ""});
      root.waitFor(function () { return !idle.visible; }, function () {
        root.finalChecks();
        root.check(root.savedCount === 3, "exact successful save signals");
        console.log("I4_EDITORS: SAVED_PASS");
        Qt.exit(0);
      });
    });
  }

  function fail(error) {
    console.error(String(error));
    Qt.exit(2);
  }

  Connections {
    target: Settings
    function onSettingsLoaded() { root.begin(); }
    function onSettingsSaved() { root.signals++; }
    function onSettingsSaveFailed() { root.failures++; }
  }
  Component.onCompleted: begin()
  Timer {
    id: poll
    interval: 25
    repeat: true
    onTriggered: root.guard(function () {
      if (root.predicate()) {
        poll.stop();
        var callback = root.continuation;
        root.continuation = null;
        root.predicate = null;
        callback();
      }
    })
  }
  Timer {
    interval: 90000
    running: true
    onTriggered: root.fail("I4 editor watchdog")
  }
}
