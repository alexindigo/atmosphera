import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pam
import Quickshell.Wayland
import qs.Commons
import qs.Services.Compositor
import qs.Services.Hardware
import qs.Services.Keyboard
import qs.Services.Media
import qs.Services.Noctalia
import qs.Services.UI
import qs.Widgets

Loader {
  id: root
  active: false

  // Track if the visualizer should be shown (lockscreen active + media playing + non-compact mode)
  readonly property bool needsSpectrum: root.active && !Settings.data.general.compactLockScreen && Settings.data.audio.visualizerType !== "" && Settings.data.audio.visualizerType !== "none"

  onActiveChanged: {
    // Suppress fcitx5 IME composition while locked — prevents CJK IME
    // leaks (JP mozc unmasked) and lock-client crashes on focus handoff
    // (noctalia#2212). Restore previous IM state on unlock.
    if (root.active) {
      InputMethodService.enterSecureMode();
    } else {
      InputMethodService.exitSecureMode();
    }

    if (!root.active) {
      root.previewMode = false;
    }

    if (root.active && root.needsSpectrum) {
      SpectrumService.registerComponent("lockscreen");
    } else {
      SpectrumService.unregisterComponent("lockscreen");
    }

    if (root.active) {
      LockKeysService.registerComponent("lockscreen");
    } else {
      LockKeysService.unregisterComponent("lockscreen");
    }
  }

  onNeedsSpectrumChanged: {
    if (root.needsSpectrum) {
      SpectrumService.registerComponent("lockscreen");
    } else {
      SpectrumService.unregisterComponent("lockscreen");
    }
  }

  Component.onCompleted: {
    PanelService.lockScreen = this;
    Qt.callLater(function () {
      var builtInComp = Qt.createComponent("BuiltInLockScreen.qml");
      if (builtInComp.status === Component.Ready) {
        LockScreenRegistry.register("default", builtInComp, "Built-in");
      }
    });
  }

  Component.onDestruction: {
    SpectrumService.unregisterComponent("lockscreen");
    LockKeysService.unregisterComponent("lockscreen");
  }

  property bool previewMode: false

  Timer {
    id: unloadAfterUnlockTimer
    interval: 250
    repeat: false
    onTriggered: root.active = false
  }

  function scheduleUnloadAfterUnlock() {
    unloadAfterUnlockTimer.start();
  }

  sourceComponent: Component {
    Item {
      id: lockContainer

      LockContext {
        id: lockContext
        onUnlocked: {
          lockSession.locked = false;
          root.scheduleUnloadAfterUnlock();
          lockContext.passwordText = "";
        }
        onFailed: {
          lockContext.passwordText = "";
        }
      }

      // Whether any monitor from the user's lockScreenMonitors list is currently connected.
      readonly property bool anyConfiguredMonitorConnected: {
        const configured = Settings.data.general.lockScreenMonitors;
        if (!configured || configured.length === 0)
          return false;
        return (Quickshell.screens || []).some(s => configured.includes(s.name));
      }

      WlSessionLock {
        id: lockSession

        Component.onCompleted: lockSession.locked = root.active

        WlSessionLockSurface {
          id: lockSurface

          Loader {
            anchors.fill: parent
            active: true
            sourceComponent: (!lockContainer.anyConfiguredMonitorConnected || Settings.data.general.lockScreenMonitors.includes(lockSurface.screen?.name)) ? pluginLockScreenComponent : blackScreenComponent
          }

          Component {
            id: pluginLockScreenComponent

            Item {
              id: pluginWrapper
              anchors.fill: parent

              Component.onCompleted: {
                var comp = LockScreenRegistry.selectedComponent();
                if (comp && comp.status === Component.Ready) {
                  var pluginId = Settings.data.general.lockScreenPlugin || "default";
                  var pluginApi = pluginId !== "default" ? PluginService.getPluginAPI(pluginId) : null;
                  var lockScreenApi = {
                    compactMode: Settings.data.general.compactLockScreen,
                    animationsEnabled: Settings.data.general.lockScreenAnimations,
                    clockStyle: Settings.data.general.clockStyle,
                    clockFormat: Settings.data.general.clockFormat,
                    passwordChars: Settings.data.general.passwordChars,
                    showSessionButtons: Settings.data.general.showSessionButtonsOnLockScreen,
                    showHibernate: Settings.data.general.showHibernateOnLockScreen,
                    showMediaControls: Settings.data.general.enableLockScreenMediaControls,
                    showCountdown: Settings.data.general.enableLockScreenCountdown,
                    countdownDuration: Settings.data.general.lockScreenCountdownDuration,
                    lockBlur: Settings.data.general.lockScreenBlur,
                    lockTint: Settings.data.general.lockScreenTint
                  };
                  var inst = comp.createObject(pluginWrapper, {
                                                 lockContext: lockContext,
                                                 screen: lockSurface.screen,
                                                 lockScreenApi: lockScreenApi,
                                                 pluginApi: pluginApi
                                               });
                  if (inst) {
                    inst.screen = Qt.binding(function () {
                      return lockSurface.screen;
                    });
                    inst.anchors.fill = pluginWrapper;
                  }
                }
              }
            }
          }

          Component {
            id: blackScreenComponent

            // Black surface for disabled monitors — still captures keyboard for password entry
            Rectangle {
              anchors.fill: parent
              color: "black"

              TextInput {
                id: blackScreenPasswordInput
                width: 0
                height: 0
                visible: false
                enabled: !lockContext.unlockInProgress
                echoMode: TextInput.Password
                passwordMaskDelay: 0

                onTextChanged: {
                  if (lockContext.passwordText !== text)
                    lockContext.passwordText = text;
                }
                Connections {
                  target: lockContext
                  function onPasswordTextChanged() {
                    if (blackScreenPasswordInput.text !== lockContext.passwordText)
                      blackScreenPasswordInput.text = lockContext.passwordText;
                  }
                }

                Keys.onPressed: function (event) {
                  if (Keybinds.checkKey(event, 'enter', Settings)) {
                    lockContext.tryUnlock();
                    event.accepted = true;
                  }
                }

                Component.onCompleted: forceActiveFocus()
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                onPositionChanged: blackScreenPasswordInput.forceActiveFocus()
              }
            }
          }
        }
      }

      Timer {
        id: previewTimer
        interval: 30000
        running: root.active && root.previewMode
        onTriggered: {
          lockSession.locked = false;
          root.active = false;
        }
      }

      Shortcut {
        sequence: "Escape"
        enabled: root.active && root.previewMode
        onActivated: {
          lockSession.locked = false;
          root.active = false;
        }
      }
    }
  }
}
