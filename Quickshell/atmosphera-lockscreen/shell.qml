// Atmosphera bundled lock screen — the class-1 locker (no-modes model).
//
// A standalone per-lock qs config: spawned by the shell as
// `qs -c atmosphera-lockscreen`, engages the ext_session_lock_v1 on
// startup (self-engage == the A.1.3 re-engage when respawned into a
// still-locked session), unlocks on PAM auth, exits after unlock.
// Serves nothing on D-Bus; the shell observes state via LockedHint.
//
// The config dir is assembled at install time: this shell.qml plus
// symlinks to the main shell tree (Commons, Services, Modules, Widgets,
// Helpers, Assets, Configs, builtin) so the shared lock UIs render
// identically with fresh per-process singleton instances.
//
// The env marker tells shared singletons (CompositorService lock
// machinery) that this process IS the locker — no recursive spawning.

//@ pragma Env ATMOSPHERA_LOCKSCREEN=1

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Modules.LockScreen
import qs.Services.Keyboard
import qs.Services.Media
import qs.Services.UI

ShellRoot {
  id: root

  property bool _settingsReady: false
  property bool _i18nReady: false
  readonly property bool ready: _settingsReady && _i18nReady

  // Set when PAM auth succeeded; the process exits only after the
  // compositor confirms the unlock (secure -> false) — exiting earlier
  // races niri and leaves the dead-client lock (red background).
  property bool _unlocking: false

  LockContext {
    id: lockContext

    onUnlocked: {
      root._unlocking = true;
      lockSession.locked = false;
    }
    onFailed: {
      lockContext.passwordText = "";
    }
  }

  Connections {
    target: lockSession
    function onSecureStateChanged() {
      if (root._unlocking && !lockSession.secure)
        quitTimer.start();
    }
  }

  // Margin for wayland teardown after the compositor's unlock confirm.
  Timer {
    id: quitTimer
    interval: 500
    repeat: false
    onTriggered: Qt.quit()
  }

  Connections {
    target: Settings
    function onSettingsLoaded() {
      root._settingsReady = true;
    }
  }
  Connections {
    target: I18n
    function onTranslationsLoaded() {
      root._i18nReady = true;
    }
  }

  Component.onCompleted: {
    AtmoSingletonCheck.verify("AtmoColor", AtmoColor, AtmoSingletonCheck.atmoColorContract);
    if (Settings.isLoaded)
      root._settingsReady = true;
    // I18n emits translationsLoaded even on the English fallback path

    // Fresh per-process singletons need the same init the main shell
    // gives them — the wallpaper cache file only loads in init().
    WallpaperService.init();
    ImageCacheService.init();

    // Icon sets (atmosphera-icons) are data-only IconRegistry
    // registrations performed by the shell's plugin system — which this
    // process does not boot. The FileView below registers the enabled
    // sets directly so AtmoIcon resolves here.

    // Parity with the in-process LockScreen's component registrations
    // (caps-lock indicator; audio visualizer when the UI wants it).
    LockKeysService.registerComponent("lockscreen");
    if (Settings.data.general.enableLockScreenMediaControls && !Settings.data.general.compactLockScreen && Settings.data.audio.visualizerType !== "" && Settings.data.audio.visualizerType !== "none")
      SpectrumService.registerComponent("lockscreen");

    lockSession.locked = true;
    Logger.i("LockScreen", "Bundled locker engaged");
  }

  Component.onDestruction: {
    LockKeysService.unregisterComponent("lockscreen");
    SpectrumService.unregisterComponent("lockscreen");
  }

  // --- icon-set bootstrap (see Component.onCompleted) ---
  FileView {
    id: pluginsJsonView
    path: Settings.configDir + "plugins.json"
    adapter: JsonAdapter {
      property var states: ({})
    }
    onLoaded: root._registerIconSets(adapter.states)
    onLoadFailed: {}
  }

  function _registerIconSets(states) {
    var keys = [];
    for (var key in states) {
      if (states[key] && states[key].enabled)
        keys.push(key);
    }
    if (keys.length === 0)
      return;
    var base = Settings.configDir + "plugins";
    var cmd = "for d in " + keys.map(function (k) {
      return "'" + base + "/" + k.replace(/'/g, "'\\''") + "'";
    }).join(" ") + "; do [ -f \"$d/manifest.json\" ] || continue; echo \"@@ID@@$(basename \"$d\")\"; cat \"$d/manifest.json\"; done";
    iconManifestProc.command = ["sh", "-c", cmd];
    iconManifestProc.running = true;
  }

  Process {
    id: iconManifestProc
    stdout: StdioCollector {}
    onExited: function () {
      var chunks = (stdout.text || "").split("@@ID@@");
      for (var i = 1; i < chunks.length; i++) {
        var nl = chunks[i].indexOf("\n");
        if (nl < 0)
          continue;
        var id = chunks[i].substring(0, nl).trim();
        var manifest;
        try {
          manifest = JSON.parse(chunks[i].substring(nl + 1));
        } catch (e) {
          continue;
        }
        if (manifest.entryPoints && manifest.entryPoints.icons)
          root._loadIconSet(id, Settings.configDir + "plugins/" + id, manifest.entryPoints.icons);
      }
    }
  }

  function _loadIconSet(pluginId, pluginDir, iconsFile) {
    var proc = Qt.createQmlObject('import QtQuick; import Quickshell.Io; Process { command: ["cat", "' + pluginDir + "/" + iconsFile + '"]; stdout: StdioCollector {} }', root, "iconRead_" + pluginId);
    proc.exited.connect(function () {
      try {
        IconRegistry.register(pluginId, JSON.parse(proc.stdout.text), pluginDir);
      } catch (e) {
        Logger.w("LockScreen", "Failed to load icon set for plugin:", pluginId);
      }
      proc.destroy();
    });
    proc.running = true;
  }

  // Which bundled UI to render. lockScreenPlugin selects: "default" (or
  // empty) → BuiltInLockScreen; "demo-custom-lockscreen" (bare or
  // composite-keyed) → the bundled plugin view. Anything else falls back
  // to the built-in UI (third-party plugin lock screens are out of scope
  // for the bundled locker, plan A.4).
  function _lockUiSource() {
    var id = (Settings.data.general.lockScreenPlugin || "default").replace(/^[a-f0-9]{6}:/, "");
    if (id === "demo-custom-lockscreen")
      return Quickshell.shellDir + "/builtin/plugins/demo-custom-lockscreen/LockScreenView.qml";
    return Quickshell.shellDir + "/Modules/LockScreen/BuiltInLockScreen.qml";
  }

  function _buildLockScreenApi() {
    return {
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
  }

  WlSessionLock {
    id: lockSession

    WlSessionLockSurface {
      id: lockSurface

      // Whether this screen gets the UI or a black surface (mirrors the
      // in-process lockScreenMonitors behavior).
      readonly property bool anyConfiguredMonitorConnected: {
        const configured = Settings.data.general.lockScreenMonitors;
        if (!configured || configured.length === 0)
          return false;
        return (Quickshell.screens || []).some(s => configured.includes(s.name));
      }
      readonly property bool showUi: !anyConfiguredMonitorConnected || Settings.data.general.lockScreenMonitors.includes(lockSurface.screen?.name)
      // The bundled UI built on this surface (never on black surfaces).
      property bool uiBuilt: false

      // Black backdrop from the first frame — the UI loads into it once
      // Settings + I18n are ready.
      Rectangle {
        anchors.fill: parent
        color: "black"
      }

      Loader {
        anchors.fill: parent
        active: root.ready && lockSurface.showUi
        sourceComponent: Component {
          Item {
            id: uiWrapper
            anchors.fill: parent

            Component.onCompleted: {
              var comp = Qt.createComponent(root._lockUiSource());
              if (comp.status === Component.Error) {
                Logger.e("LockScreen", "Failed to load lock UI:", comp.errorString());
                comp = Qt.createComponent(Quickshell.shellDir + "/Modules/LockScreen/BuiltInLockScreen.qml");
              }
              if (comp.status !== Component.Ready) {
                Logger.e("LockScreen", "Built-in lock UI unavailable:", comp.errorString());
                return; // hidden password entry below still unlocks
              }
              var inst = comp.createObject(uiWrapper, {
                                             lockContext: lockContext,
                                             screen: lockSurface.screen,
                                             lockScreenApi: root._buildLockScreenApi(),
                                             pluginApi: null
                                           });
              if (inst) {
                inst.screen = Qt.binding(function () {
                  return lockSurface.screen;
                });
                inst.anchors.fill = uiWrapper;
                lockSurface.uiBuilt = true;
              }
            }
          }
        }
      }

      // Hidden password entry: the only input on black surfaces, the
      // input while the UI loads, and the fallback if the UI never
      // builds. Disabled once the real UI owns input (focus fight).
      TextInput {
        id: passwordInput
        width: 0
        height: 0
        visible: false
        enabled: !lockSurface.uiBuilt && !lockContext.unlockInProgress
        echoMode: TextInput.Password
        passwordMaskDelay: 0

        onTextChanged: {
          if (lockContext.passwordText !== text)
            lockContext.passwordText = text;
        }
        Connections {
          target: lockContext
          function onPasswordTextChanged() {
            if (passwordInput.text !== lockContext.passwordText)
              passwordInput.text = lockContext.passwordText;
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
        enabled: !lockSurface.uiBuilt
        onPositionChanged: passwordInput.forceActiveFocus()
      }
    }
  }
}
