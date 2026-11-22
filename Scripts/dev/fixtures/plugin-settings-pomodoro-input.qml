// P169 green: the actual Pomodoro page and Main, all four toggles activated by
// a real Wayland pointer click, real Tab focus plus Space/Return, and AT-SPI
// toggle actions. Each input pass must produce the same field intents, native
// Apply result, persisted values and Main consumer state.
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
  property var toggles: []
  property int pass: 0
  property int current: 0
  property int ticks: 0
  property int tabs: 0
  property int pointerAcks: 0
  property bool a11yComplete: false
  property var acceptedReceipt: null
  readonly property var passes: ["pointer", "keyboard", "accessibility"]
  readonly property var keys: ["autoStartBreaks", "autoStartWork", "compactMode", "playSound"]
  readonly property var labels: ["settings.auto-start-breaks", "settings.auto-start-work", "settings.compact-mode", "Play Alarm Sound"]
  readonly property var initial: [false, false, false, true]
  readonly property var keyNames: ["space", "Return", "space", "Return"]

  FileView {
    id: reader
    blockLoading: true
    printErrors: false
  }
  function check(condition, message) {
    if (!condition)
      throw new Error("P169_ASSERT: " + message);
  }
  function fail(error) {
    console.error(String(error) + "\n" + (error.stack || ""));
    Qt.exit(2);
  }
  function expected(index) {
    // Every pass flips all four values from the previous pass.
    return pass % 2 === 0 ? !initial[index] : initial[index];
  }
  function stored() {
    reader.path = "";
    reader.path = Settings.configDir + "settings/plugins/pomodoro.json";
    reader.waitForJob();
    return JSON.parse(reader.text());
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
    reader.path = Settings.configDir + "plugins/pomodoro/manifest.json";
    reader.waitForJob();
    var manifest = JSON.parse(reader.text());
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
  function locate() {
    var selected = [];
    for (var i = 0; i < labels.length; ++i) {
      var label = i === 3 ? labels[i] : api.tr(labels[i]);
      var toggle = find(popup.settingsPage, function (item) {
        return item.label === label && typeof item.toggled === "function" && typeof item.activate === "function";
      });
      check(toggle !== null, "actual NToggle " + labels[i]);
      selected.push(toggle);
    }
    toggles = selected;
  }
  function switchArea(toggle) {
    return find(toggle, function (item) {
      return item !== toggle && item.hoverEnabled === true && typeof item.clicked === "function" && item.cursorShape !== undefined;
    });
  }
  // Bring the control into the popup's scrolled viewport, as a user would
  // scroll to it, before pointing at it.
  function reveal(item) {
    var flick = item.parent;
    while (flick && !(flick.contentY !== undefined && flick.contentHeight !== undefined && typeof flick.flick === "function"))
      flick = flick.parent;
    check(flick !== null, "control lies in a scrollable view");
    var y = item.mapToItem(flick.contentItem, 0, 0).y;
    flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, y - (flick.height - item.height) / 2));
    var top = item.mapToItem(flick, 0, 0).y;
    return top >= 0 && top + item.height <= flick.height;
  }
  function startPass() {
    current = 0;
    ticks = 0;
    acceptedReceipt = null;
    for (var i = 0; i < toggles.length; ++i) {
      check(toggles[i].checked === !expected(i), passes[pass] + " baseline " + keys[i]);
      check(popup._pageApi.field(keys[i]).pendingIntent === "", passes[pass] + " no pending intent before input " + keys[i]);
    }
    if (passes[pass] === "accessibility") {
      accessibility.command = [Quickshell.env("PHA_A11Y_PYTHON"), "-B", Quickshell.env("PHA_A11Y_PROBE"), String(pass)];
      accessibility.running = true;
      phase = "a11y";
    } else {
      phase = passes[pass] === "pointer" ? "point" : "tab";
    }
  }
  function activated(index) {
    var field = popup._pageApi.field(keys[index]);
    return toggles[index].checked === expected(index) && field.pendingIntent === "set" && field.value === expected(index);
  }
  function drive() {
    if (phase === "page" && popup.visible && popup.settingsPage) {
      check(host.width === Quickshell.screens[0].width && host.height === Quickshell.screens[0].height, "full-output dialog host maps item to output coordinates");
      locate();
      startPass();
    } else if (phase === "point" && !pointer.running) {
      pointer.running = true;
    } else if (phase === "point" && pointer.ready && !pointer.busy) {
      var area = switchArea(toggles[current]);
      check(area !== null, "toggle switch pointer area");
      if (!reveal(area)) {
        check(++ticks < 20, "toggle scrolled into view " + keys[current]);
        return;
      }
      var center = area.mapToItem(null, area.width / 2, area.height / 2);
      var layout = JSON.parse(Quickshell.env("PHA_P169_LAYOUT"));
      console.log("P169_POINTER_TARGET: " + keys[current] + " " + Math.round(center.x) + "," + Math.round(center.y));
      pointer.send(["move " + Math.round(layout.x + center.x) + " " + Math.round(layout.y + center.y) + " " + layout.width + " " + layout.height]);
      phase = "point-hover";
      ticks = 0;
    } else if (phase === "point-hover" && !pointer.busy) {
      var target = switchArea(toggles[current]);
      check(target !== null, "hover target remains the actual toggle switch");
      if (!target.containsMouse) {
        check(++ticks < 60, "pointer reaches the mapped toggle switch " + keys[current]);
        var mapped = target.mapToItem(null, target.width / 2, target.height / 2);
        var outputs = JSON.parse(Quickshell.env("PHA_P169_LAYOUT"));
        pointer.send(["move " + Math.round(outputs.x + mapped.x) + " " + Math.round(outputs.y + mapped.y) + " " + outputs.width + " " + outputs.height]);
        return;
      }
      pointer.send(["button 272 1", "button 272 0"]);
      phase = "point-wait";
      ticks = 0;
    } else if (phase === "point-wait" && !pointer.busy) {
      if (!activated(current)) {
        check(++ticks < 60, "pointer click produced the toggle intent " + keys[current]);
        return;
      }
      console.log("P169_POINTER_INTENT: " + keys[current]);
      phase = ++current < toggles.length ? "point" : "apply";
    } else if (phase === "tab" && !typing.running) {
      if (toggles[current].activeFocus) {
        tabs = 0;
        typing.command = [Quickshell.env("PHA_INPUT_INJECTOR"), "-k", keyNames[current]];
        typing.running = true;
        phase = "key-wait";
        ticks = 0;
        return;
      }
      check(++tabs < 80, "Tab reaches toggle " + keys[current]);
      typing.command = [Quickshell.env("PHA_INPUT_INJECTOR"), "-k", "Tab"];
      typing.running = true;
    } else if (phase === "key-wait" && !typing.running) {
      if (!activated(current)) {
        check(++ticks < 60, keyNames[current] + " produced the toggle intent " + keys[current]);
        return;
      }
      console.log("P169_KEYBOARD_INTENT: " + keys[current] + " via Tab + " + keyNames[current]);
      phase = ++current < toggles.length ? "tab" : "apply";
    } else if (phase === "a11y" && a11yComplete) {
      for (var i = 0; i < toggles.length; ++i) {
        check(activated(i), "AT-SPI toggle action produced the intent " + keys[i]);
        console.log("P169_ACCESSIBILITY_INTENT: " + keys[i]);
      }
      a11yComplete = false;
      phase = "apply";
    } else if (phase === "apply") {
      check(popup.dirty, passes[pass] + " intents dirty the selected session");
      check(popup.applySettings(), passes[pass] + " Apply admitted");
      phase = "applied";
      ticks = 0;
    } else if (phase === "applied") {
      if (!acceptedReceipt || popup.busy) {
        check(++ticks < 200, passes[pass] + " Apply receipt");
        return;
      }
      var values = stored();
      check(values.opaque && values.opaque.keep === true, "opaque sibling retained");
      for (var k = 0; k < keys.length; ++k) {
        check(values[keys[k]] === expected(k), passes[pass] + " persisted " + keys[k]);
        // Main reads playSound from its runtime settings when the alarm fires.
        var consumed = keys[k] === "playSound" ? api.pluginSettings.playSound : main[keys[k]];
        check(consumed === expected(k), passes[pass] + " Main consumer " + keys[k]);
        check(toggles[k].checked === expected(k), passes[pass] + " presentation follows saved value " + keys[k]);
      }
      check(!main.pomodoroRunning && !main.pomodoroSoundPlaying, "timer and sound were never started");
      console.log("P169_PASS_APPLIED: " + passes[pass] + " " + JSON.stringify(keys.map(function (key) {
        return values[key];
      })));
      if (++pass < passes.length) {
        startPass();
        return;
      }
      console.log("P169_INPUT: PASS (pointer, Tab+Space/Return and AT-SPI toggle actions submit identical intents; native Apply, file and Main agree)");
      pointer.finish();
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
    id: pointer
    property bool ready: false
    property bool busy: false
    property int pending: 0
    command: [Quickshell.env("PHA_POINTER")]
    stdinEnabled: true
    function send(lines) {
      busy = true;
      pending = lines.length;
      for (var line of lines)
        write(line + "\n");
    }
    function finish() {
      stdinEnabled = false;
    }
    stdout: SplitParser {
      onRead: line => {
        if (line === "READY")
          pointer.ready = true;
        else if (line === "OK" && --pointer.pending === 0)
          pointer.busy = false;
        else if (line !== "OK")
          root.fail("unexpected pointer reply " + line);
      }
    }
    onExited: exitCode => {
      if (exitCode !== 0 && root.phase !== "opening")
        root.fail("virtual pointer exited: " + exitCode);
    }
  }
  Process {
    id: accessibility
    onExited: exitCode => {
      if (exitCode !== 0)
        root.fail("AT-SPI toggle actions failed: " + exitCode);
      else
        root.a11yComplete = true;
    }
    stderr: StdioCollector {
      onStreamFinished: console.log(this.text)
    }
  }
  PopupMenuWindow {
    id: host
    shellScreen: Quickshell.screens.find(item => item.name === Quickshell.env("PHA_P169_SCREEN"))
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
    interval: 90000
    running: true
    onTriggered: root.fail("watchdog at " + root.phase + " pass " + root.pass + " control " + root.current)
  }
  Component.onCompleted: begin()
}
