import QtQuick
import Quickshell
import qs.Commons
import qs.Modules.Panels.Settings.Tabs.Idle as Idle
import qs.Services.Power

ShellRoot {
  SettingsBootstrap {
    id: directories
  }
  Loader {
    active: directories.ready && Settings.isLoaded
    sourceComponent: Component {
      FloatingWindow {
        id: root
        implicitWidth: 1000
        implicitHeight: 850
        visible: true
        property int locks: 0
        property int suspends: 0
        property bool cold: Quickshell.env("IDLE_TOGGLES_COLD") === "1"
        property string testCase: Quickshell.env("IDLE_TOGGLES_CASE")

        function check(ok, label) {
          if (!ok)
            throw new Error("IDLE_TOGGLES_ASSERT: " + label);
        }
        function guard(callback) {
          try {
            callback();
          } catch (error) {
            console.error(String(error));
            Qt.exit(2);
          }
        }
        function find(item, predicate) {
          if (predicate(item))
            return item;
          for (var child of item.children || []) {
            var found = find(child, predicate);
            if (found)
              return found;
          }
          return null;
        }
        function toggle(item) {
          return find(item, function (child) {
            return String(child).indexOf("NToggle_QMLTYPE") === 0;
          });
        }
        function spin(item) {
          return find(item, function (child) {
            return String(child).indexOf("NSpinBox_QMLTYPE") === 0;
          });
        }
        function row(stage) {
          return find(behavior, function (child) {
            return child.actionName === stage;
          });
        }
        function begin() {
          guard(function () {
            if (cold) {
              check(Settings.data.idle.suspendTimeout === 0, "built-in zero survives cold load");
              check(JSON.parse(Settings.data.idle.customCommands)[0].timeout === 0, "custom zero survives cold load");
              custom._loadToModel();
              var loaded = find(custom, function (child) {
                return child.name === "disabled command" && child.timeout !== undefined;
              });
              check(loaded && loaded.timeout === 0 && !toggle(loaded).checked, "cold custom row stays off");
              check(Object.keys(IdleService._customMonitors).length === 0, "cold custom zero creates no monitor");
              console.log("IDLE_TOGGLES: COLD_PASS");
              Qt.exit(0);
              return;
            }
            Settings.data.idle.enabled = true;
            Settings.data.idle.screenOffTimeout = 0;
            Settings.data.idle.lockTimeout = 0;
            Settings.data.idle.suspendTimeout = 0;
            Settings.data.idle.customCommands = '[{"name":"disabled command","timeout":0,"command":"true","resumeCommand":"","opaque":"keep"}]';
            if (testCase === "native") {
              // Observe the stage signal, not an authenticated native lock.
              // The existing settings seams prohibit both physical lock/sleep.
              Settings.data.general.lockScreenEnabled = false;
              Settings.data.general.lockOnSuspend = false;
              Settings.data.sessionMenu.powerOptions = [
                    {
                      action: "suspend",
                      enabled: true,
                      keybind: "2",
                      command: "true"
                    }
                  ];
              Settings.data.idle.fadeDuration = 1;
              Settings.data.idle.lockTimeout = 2;
              check(IdleService._lockMonitor !== null && IdleService._suspendMonitor === null, "lock monitor on; suspend absent");
              check(IdleService._isStageEnabled("lock") && !IdleService._isStageEnabled("suspend"), "built-in zero contract");
              nativeFinish.start();
            } else if (testCase === "custom") {
              custom._loadToModel();
              var entry = find(custom, function (child) {
                return child.name === "disabled command" && child.timeout !== undefined;
              });
              check(entry && entry.timeout === 0, "custom zero survives model load");
              check(toggle(entry) && !toggle(entry).checked, "custom row has off toggle");
              toggle(entry).toggled(true);
              check(JSON.parse(Settings.data.idle.customCommands)[0].timeout === 60, "custom enable defaults to 60");
              toggle(entry).toggled(false);
              check(JSON.parse(Settings.data.idle.customCommands)[0].timeout === 0, "custom disable writes zero");
              check(JSON.parse(Settings.data.idle.customCommands)[0].opaque === "keep", "row toggle preserves unknown fields");
              Settings.data.idle.customCommands = '[{"name":"disabled command","timeout":75,"command":"true","resumeCommand":"","opaque":"keep"}]';
              custom._loadToModel();
              entry = find(custom, function (child) {
                return child.name === "disabled command" && child.timeout !== undefined;
              });
              toggle(entry).toggled(false);
              toggle(entry).toggled(true);
              check(JSON.parse(Settings.data.idle.customCommands)[0].timeout === 75, "custom row restores previous positive timeout");
              toggle(entry).toggled(false);
              Settings.data.idle.customCommands = '[{"name":"A","timeout":75,"command":"true"},{"name":"B","timeout":120,"command":"true"}]';
              custom._setEntryEnabled(0, false);
              custom._setEntryEnabled(1, false);
              Settings.data.idle.customCommands = '[{"name":"B","timeout":0,"command":"true"}]';
              custom._setEntryEnabled(0, true);
              check(JSON.parse(Settings.data.idle.customCommands)[0].timeout === 120, "external removal keeps the surviving command's remembered timeout");
              custom._setEntryEnabled(0, false);
              Settings.data.idle.customCommands = '[{"name":"replacement","timeout":0,"command":"false"}]';
              custom._setEntryEnabled(0, true);
              check(JSON.parse(Settings.data.idle.customCommands)[0].timeout === 60, "external replacement cannot inherit stale memory");
              Settings.data.idle.customCommands = '[{"name":"duplicate","timeout":75,"command":"true"},{"name":"duplicate","timeout":120,"command":"true"}]';
              custom._setEntryEnabled(0, false);
              custom._setEntryEnabled(1, false);
              custom._loadToModel();
              custom._setEntryEnabled(1, true);
              check(JSON.parse(Settings.data.idle.customCommands)[1].timeout === 120, "unchanged duplicate rows retain their own memory");
              custom._setEntryEnabled(1, false);
              Settings.data.idle.customCommands = '[{"name":"duplicate","timeout":0,"command":"true"}]';
              custom._setEntryEnabled(0, true);
              check(JSON.parse(Settings.data.idle.customCommands)[0].timeout === 60, "ambiguous surviving duplicate cannot inherit memory");
              Settings.data.idle.customCommands = '[{"name":"disabled command","timeout":75,"command":"true","resumeCommand":"","opaque":"keep"}]';
              custom._setEntryEnabled(0, false);
              Settings.saveResult(function (result) {
                root.guard(function () {
                  root.check(result.status === "saved", "settle owning leaf before opening editor");
                  var editor = custom.createEntryEditor(0);
                  root.check(editor !== null, "editor created from settled leaf");
                  popup.openEditor(editor, editor.initialValue, 0);
                  var time = root.spin(popup.contentItem);
                  root.check(time.from === 1 && !time.enabled && time.value === 75, "popup off shows remembered positive spin");
                  root.toggle(popup.contentItem).toggled(true);
                  time.value = 91;
                  time.valueModified(91);
                  root.toggle(popup.contentItem).toggled(false);
                  root.toggle(popup.contentItem).toggled(true);
                  root.check(time.value === 91 && popup.timeoutValue === 91, "popup restores edited timeout");
                  root.toggle(popup.contentItem).toggled(false);
                  popup.submit({
                                 name: "disabled command",
                                 timeout: 0,
                                 command: "true",
                                 resumeCommand: ""
                               });
                  savedPoll.start();
                });
              });
            } else {
              var stages = [I18n.tr("panels.idle.screen-off-label"), I18n.tr("panels.idle.lock-label"), I18n.tr("common.suspend")];
              var keys = ["screenOffTimeout", "lockTimeout", "suspendTimeout"];
              for (var i = 0; i < stages.length; i++) {
                var action = row(stages[i]);
                var control = toggle(action);
                var time = spin(action);
                check(control !== null, "built-in row has toggle: " + keys[i]);
                check(Math.abs(time.mapToItem(root.contentItem, 0, time.height / 2).y - control.mapToItem(root.contentItem, 0, control.height / 2).y) < 1, "timeout and toggle share a centerline");
                check(!control.checked && !time.enabled && time.value === Settings.getDefaultValue("idle." + keys[i]), "initial off displays schema default");
                control.toggled(true);
                check(Settings.data.idle[keys[i]] === Settings.getDefaultValue("idle." + keys[i]), "enable restores schema default");
                time.value = 37 + i;
                time.valueModified(time.value);
                check(Settings.data.idle[keys[i]] === 37 + i, "spin edits real timeout");
                control.toggled(false);
                check(Settings.data.idle[keys[i]] === 0 && !time.enabled && time.value === 37 + i, "off writes zero and remembers display");
                control.toggled(true);
                check(Settings.data.idle[keys[i]] === 37 + i && time.enabled && time.from === 1, "on restores remembered timeout");
                Settings.data.idle[keys[i]] = 83 + i;
                check(time.value === 83 + i, "external timeout update reaches edited spin");
                var input = find(time, function (child) {
                  return child.editText !== undefined && child.userEdited !== undefined;
                });
                input.forceActiveFocus();
                input.editText = "124";
                input.userEdited = true;
                control.toggled(false);
                check(Settings.data.idle[keys[i]] === 0, "disabling commits pending spin input without re-enabling the stage");
                control.toggled(true);
                check(time.value === 124, "pending spin input becomes remembered timeout");
                control.toggled(false);
              }
              save();
            }
          });
        }
        function save() {
          Settings.saveResult(function (result) {
            root.guard(function () {
              root.check(["saved", "nothing_to_save"].indexOf(result.status) !== -1, "real owner save receipt");
              root.check(JSON.parse(Settings.data.idle.customCommands)[0].timeout === 0, "custom save retains zero");
              root.check(Object.keys(IdleService._customMonitors).length === 0, "custom zero creates no monitor");
              console.log("IDLE_TOGGLES: SAVED_PASS " + root.testCase);
              Qt.exit(0);
            });
          });
        }
        Idle.BehaviorSubTab {
          id: behavior
          anchors.fill: parent
          visible: root.testCase !== "custom"
        }
        Idle.CustomSubTab {
          id: custom
          anchors.fill: parent
          visible: root.testCase === "custom"
        }
        Idle.IdleCommandEditPopup {
          id: popup
          parent: root.contentItem
        }
        Connections {
          target: IdleService
          function onLockRequested() {
            root.locks++;
          }
          function onSuspendRequested() {
            root.suspends++;
          }
        }
        Timer {
          id: nativeFinish
          interval: 7000
          onTriggered: root.guard(function () {
            root.check(root.locks > 0 && root.suspends === 0, "native idle ran lock stage and never suspend");
            root.check(IdleService._suspendMonitor === null, "suspend monitor remains absent");
            console.log("IDLE_TOGGLES: NATIVE_PASS " + JSON.stringify({
                                                                        locks: root.locks,
                                                                        suspends: root.suspends
                                                                      }));
            Qt.exit(0);
          })
        }
        Timer {
          id: savedPoll
          interval: 25
          repeat: true
          onTriggered: root.guard(function () {
            if (!popup.visible) {
              stop();
              root.save();
            } else
              root.check(!popup.saveFailed, "popup save accepted");
          })
        }
        Timer {
          interval: 250
          running: true
          onTriggered: root.begin()
        }
      }
    }
  }
  Timer {
    interval: 20000
    running: true
    onTriggered: {
      console.error("IDLE_TOGGLES_ASSERT: watchdog");
      Qt.exit(2);
    }
  }
}
