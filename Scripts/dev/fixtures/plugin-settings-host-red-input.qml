// P169: actual Pomodoro page and Main, real Wayland Space keys and AT-SPI.
// The ordinary Qt Button canary proves both injection channels are live.
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Modules.MainScreen
import qs.Services.Plugins
import qs.Widgets

ShellRoot {
  id: root
  property bool started: false
  property string phase: "opening"
  property var api: null
  property var main: null
  property var controls: []
  property int nextControl: 0
  property int canaryPresses: 0
  property bool a11yComplete: false
  property int ticks: 0
  property var acceptedReceipt: null
  readonly property var labels: ["settings.auto-start-breaks", "settings.auto-start-work", "settings.compact-mode", "Play Alarm Sound"]
  readonly property var buffers: ["editAutoStartBreaks", "editAutoStartWork", "editCompactMode", "editPlaySound"]
  readonly property var before: [false, false, false, true]

  FileView {
    id: manifestFile
    path: Settings.configDir + "plugins/pomodoro/manifest.json"
    blockLoading: true
    printErrors: false
  }
  function check(condition, message) {
    if (!condition)
      throw new Error("P169_RED_ASSERT: " + message);
  }
  function fail(error) {
    console.error(String(error) + "\n" + (error.stack || ""));
    Qt.exit(2);
  }
  function find(item, predicate) {
    if (!item)
      return null;
    if (predicate(item))
      return item;
    for (var child of item.children || []) {
      var result = find(child, predicate);
      if (result)
        return result;
    }
    return null;
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    manifestFile.waitForJob();
    var manifest = JSON.parse(manifestFile.text());
    Registry.installedPlugins = {
      pomodoro: manifest
    };
    Service._openSettingsOwner("pomodoro", function (owner) {
      try {
        check(owner !== null, "native owner opened");
        api = Service.createPluginAPI("pomodoro", manifest, owner, {}, {}, {});
        Service.loadedPlugins = {
          pomodoro: {
            api: api
          }
        };
        var component = Qt.createComponent("file://" + api.pluginDir + "/" + manifest.entryPoints.main);
        check(component.status === Component.Ready, "actual Main compiles: " + component.errorString());
        main = PluginLoader.createObject("pomodoro", "main", component, root, api, {});
        check(main !== null, "actual Main constructed");
        api.mainInstance = main;
        check(host.showDialog(popup), "popup host admitted");
        check(popup.openPluginSettings(manifest), "actual settings popup opening");
        phase = "page";
      } catch (error) {
        fail(error);
      }
    });
  }
  function drive() {
    if (phase === "page" && popup.visible && popup.settingsPage) {
      var selected = [];
      for (var i = 0; i < labels.length; ++i) {
        var label = i === 3 ? labels[i] : api.tr(labels[i]);
        var toggle = find(popup.settingsPage, function (item) {
          return item.label === label && typeof item.toggled === "function";
        });
        check(toggle !== null && toggle.checked === before[i], "actual toggle baseline " + labels[i]);
        selected.push(toggle);
      }
      controls = selected;
      canary.forceActiveFocus();
      typing.command = [Quickshell.env("PHA_INPUT_INJECTOR"), "-k", "space"];
      typing.running = true;
      phase = "key-canary";
    } else if (phase === "key-canary" && !typing.running && canaryPresses === 1) {
      controls[nextControl].forceActiveFocus();
      check(controls[nextControl].activeFocus, "selected toggle receives keyboard focus");
      typing.command = [Quickshell.env("PHA_INPUT_INJECTOR"), "-k", "space"];
      typing.running = true;
      phase = "key";
      ticks = 0;
    } else if (phase === "key" && !typing.running && ++ticks > 3) {
      check(controls[nextControl].checked === before[nextControl] && popup.settingsPage[buffers[nextControl]] === before[nextControl], "Space carries no intent for " + labels[nextControl]);
      console.log("P169_KEYBOARD_NO_INTENT: " + labels[nextControl]);
      nextControl++;
      if (nextControl < controls.length) {
        controls[nextControl].forceActiveFocus();
        typing.command = [Quickshell.env("PHA_INPUT_INJECTOR"), "-k", "space"];
        typing.running = true;
        ticks = 0;
      } else {
        const observedLabels = controls.map(toggle => toggle.label);
        console.log("P169_A11Y_LABELS: " + JSON.stringify(observedLabels));
        accessibility.command = [Quickshell.env("PHA_A11Y_PYTHON"), "-B", Quickshell.env("PHA_A11Y_PROBE"), ...observedLabels];
        accessibility.running = true;
        phase = "a11y";
      }
    } else if (phase === "a11y" && a11yComplete && canaryPresses === 2) {
      check(!popup.settingsPage.settingsDirty, "ignored keyboard actions are absent from page intent");
      popup.applySettings();
      phase = "applied";
    } else if (phase === "applied" && acceptedReceipt && !popup.busy) {
      check(!main.autoStartBreaks && !main.autoStartWork && !main.compactMode && api.pluginSettings.playSound, "actual runtime consumer still receives original settings after Apply");
      check(!main.pomodoroRunning && !main.pomodoroSoundPlaying, "timer and sound were never started");
      console.log("RED_CONTROL P169: REPRODUCED (four keyboard intents absent; AT-SPI observation recorded; native Apply and Main unchanged)");
      Qt.exit(0);
    }
  }
  Connections {
    target: Settings
    function onSettingsLoaded() {
      root.begin();
    }
  }
  Process {
    id: typing
    onExited: exitCode => {
      if (exitCode !== 0)
        root.fail("Wayland key injection failed: " + exitCode);
    }
  }
  Process {
    id: accessibility
    onExited: exitCode => {
      if (exitCode !== 0)
        root.fail("AT-SPI action observation failed: " + exitCode);
      else
        root.a11yComplete = true;
    }
    stderr: StdioCollector {
      onStreamFinished: console.log(this.text)
    }
  }
  PopupMenuWindow {
    id: host
    shellScreen: Quickshell.screens[0]
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    NPluginSettingsPopup {
      id: popup
      parent: host.dialogParent
      screen: Quickshell.screens[0]
      onSettingsCompleted: result => {
        if ((result.status === "saved" || result.status === "nothing_to_save") && result.refreshState === "current")
          root.acceptedReceipt = result;
        else
          root.fail("native Apply was not accepted");
      }
      Button {
        id: canary
        text: "PHA-input-canary"
        anchors.bottom: parent.bottom
        onClicked: root.canaryPresses++
      }
    }
  }
  Timer {
    interval: 50
    running: true
    repeat: true
    onTriggered: {
      try {
        root.drive();
      } catch (error) {
        root.fail(error);
      }
    }
  }
  Timer {
    interval: 45000
    running: true
    onTriggered: root.fail("watchdog at " + root.phase)
  }
  Component.onCompleted: begin()
}
