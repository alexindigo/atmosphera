import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins
import qs.Widgets

ShellRoot {
  id: root
  readonly property string scope: Quickshell.env("PHA_POMO_SCOPE")
  readonly property string mode: Quickshell.env("PHA_POMO_MODE")
  readonly property string boundary: Quickshell.env("PHA_POMO_BOUNDARY")
  readonly property string casePath: Quickshell.env("PHA_POMO_CASE")
  readonly property bool oldRed: Quickshell.env("PHA_POMO_RED") === "1"
  readonly property var keys: ["workDuration", "shortBreakDuration", "longBreakDuration", "sessionsBeforeLongBreak", "autoStartBreaks", "autoStartWork", "compactMode", "playSound"]
  readonly property var edits: [30, 7, 20, 3, true, true, true, false]
  readonly property var following: [35, 8, 25, 5, false, false, false, false]
  property bool started: false
  property string phase: "startup"
  property double since: Date.now()
  onPhaseChanged: since = Date.now()
  property var api: null
  property var selected: null
  property var sibling: null
  property var inherited: null
  property var main: null
  property var bar: null
  property var panel: null
  property var receipt: null
  property string afterDisk: ""
  property string diskBoundary: ""
  property var retainedTimer: null
  property var retainedContext: null
  property var retirementObserver: null
  FileView {
    id: manifest
    path: Settings.configDir + "plugins/pomodoro/manifest.json"
    blockLoading: true
  }
  FileView {
    id: dictionary
    path: Settings.configDir + "plugins/pomodoro/i18n/en.json"
    blockLoading: true
  }
  FileView {
    id: expectations
    path: root.casePath + "/expectations.json"
    blockLoading: true
  }
  Process {
    id: disk
    onExited: code => {
      if (code !== 0)
        root.fail("independent complete documents: " + root.diskBoundary);
      else
        root.phase = root.afterDisk;
    }
  }
  PanelWindow {
    visible: true
    implicitWidth: 1200
    implicitHeight: 950
    Item {
      id: content
      width: 1200
      height: 950
    }
    NPluginSettingsPopup {
      id: popup
      screen: Quickshell.screens[0]
      onSettingsCompleted: result => root.receipt = result
    }
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("POMO_ASSERT: " + scope + "/" + mode + "/" + phase + ": " + message);
  }
  function fail(error) {
    console.error(String(error) + "\n" + (error.stack || ""));
    Qt.exit(2);
  }
  function find(object, predicate) {
    if (object && predicate(object))
      return object;
    for (var list of [object?.data, object?.children]) {
      if (!list || typeof list === "function" || typeof list.length !== "number")
        continue;
      for (var child of list) {
        var found = find(child, predicate);
        if (found)
          return found;
      }
    }
    return null;
  }
  function create(entry, context) {
    var component = Qt.createComponent("file://" + api.pluginDir + "/" + api.manifest.entryPoints[entry]);
    check(component.status === Component.Ready, component.errorString());
    var item = PluginLoader.createObject("pomodoro", entry, component, content, context, {});
    check(item, "actual " + entry + " constructs");
    return item;
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    manifest.waitForJob();
    dictionary.waitForJob();
    var descriptor = JSON.parse(manifest.text()), dict = JSON.parse(dictionary.text());
    Registry.installedPlugins = {
      pomodoro: descriptor
    };
    Service._openSettingsOwner("pomodoro", function (owner) {
      try {
        check(owner, "actual native owner");
        api = Service.createPluginAPI("pomodoro", descriptor, owner, dict, dict, {});
        Service.loadedPlugins = {
          pomodoro: {
            api: api
          }
        };
        main = create("main", api);
        api.mainInstance = main;
        selected = PluginInstances.apiFor("pomodoro", {
                                            kind: "bar",
                                            list: "global",
                                            section: "left",
                                            index: 0
                                          });
        sibling = PluginInstances.apiFor("pomodoro", {
                                           kind: "bar",
                                           list: "global",
                                           section: "left",
                                           index: 1
                                         });
        inherited = PluginInstances.apiFor("pomodoro", {
                                             kind: "bar",
                                             list: "global",
                                             section: "left",
                                             index: 2
                                           });
        phase = "runtime";
      } catch (error) {
        fail(error);
      }
    });
  }
  function cfg(name, index) {
    expectations.reload();
    expectations.waitForJob();
    var e = JSON.parse(expectations.text())[name];
    return Object.assign({
                           compactMode: false,
                           playSound: true
                         }, api.manifest.metadata.defaultSettings, e.shared, index < 0 ? {} : e.bar.widgets.left[index].instanceSettings);
  }
  function ready(name) {
    var values = cfg(name, scope === "instance" ? 0 : -1), target = scope === "instance" ? selected : api;
    function matches(runtime, expected) {
      return keys.every(key => (key === "compactMode" ? runtime.pluginSettings[key] ?? false : key === "playSound" ? runtime.pluginSettings[key] ?? true : runtime.pluginSettings[key]) === expected[key]);
    }
      return matches(target, values) && matches(sibling, cfg(name, 1)) && matches(inherited, cfg(name, 2));
    }
      function probe(name, next) {
      diskBoundary = name;
      afterDisk = next;
      phase = "disk";
      disk.command = ["python3", "-B", Quickshell.env("PHA_POMO_DISK"), casePath, Quickshell.env("PHA_POMO_OUTPUT") + "/persisted", name];
      disk.running = true;
    }
      function open(next) {
      check(scope === "shared" ? popup.openPluginSettings(api.manifest, "settings") : popup.openInstanceSettings(api.manifest, selected, "settings"), "actual scoped page opens");
      phase = next;
    }
      function edit() {
      for (var i = 0; i < 4; ++i) {
      var names = ["editWorkDuration", "editShortBreakDuration", "editLongBreakDuration", "editSessionsBeforeLongBreak"];
      var input = find(popup.settingsPage, item => item.objectName === "settings-range-" + names[i]);
      check(input, "actual duration/session control " + keys[i]);
      input.valueModified(edits[i]);
    }
      var labels = [api.tr("settings.auto-start-breaks"), api.tr("settings.auto-start-work"), api.tr("settings.compact-mode"), "Play Alarm Sound"];
      for (var j = 0; j < labels.length; ++j) {
      var toggle = find(popup.settingsPage, item => item.label === labels[j] && item.toggled !== undefined);
      check(toggle, "actual toggle");
      toggle.toggled(edits[j + 4]);
    }
    }
      function apply(next) {
      receipt = null;
      check(popup.applySettings(), "native Apply");
      phase = next;
    }
      function accepted() {
      return receipt && !popup.busy && receipt.status === "saved" && receipt.refreshState === "current";
    }
      function consumers(name) {
      var values = cfg(name, scope === "instance" ? 0 : -1), timer = oldRed ? main : main.timerFor(scope === "instance" ? selected : api);
      check(timer && timer.workDuration === values.workDuration * 60, oldRed ? "original timer consumes saved selected duration" : "selected duration");
      check(panel.compactMode === values.compactMode && panel.sessionsBeforeLongBreak === values.sessionsBeforeLongBreak, "actual Panel selected policy");
      check(!oldRed && bar.mainInstance === timer && panel.mainInstance === timer, "both entries share exact timer");
      for (var key of keys)
      check((key.endsWith("Duration") ? timer[key] / 60 : timer[key]) === values[key], "every selected field " + key);
      var siblingTimer = main.timerFor(sibling), inheritedTimer = main.timerFor(inherited);
      check(siblingTimer !== timer && siblingTimer.workDuration === 45 * 60, "overridden sibling independent");
      check(inheritedTimer !== timer && inheritedTimer.workDuration === cfg(name, 2).workDuration * 60, "inherited timer follows base");
      panel.startTimer();
      check(timer.pomodoroRunning && timer.pomodoroRemainingSeconds === values.workDuration * 60, "actual Panel starts selected timer");
      check(!siblingTimer.pomodoroRunning && !inheritedTimer.pomodoroRunning, "other timers stay stopped");
      check(find(bar, item => item.text === bar.formatTime(values.workDuration * 60)), "actual Bar time Text");
      panel.pauseTimer();
      panel.resetAll();
      if (Quickshell.env("PHA_POMO_LIFETIME") === "1") {
      retainedTimer = timer;
      retainedContext = selected.settingsContext;
      retirementObserver = find(timer, item => item.interval === 100 && item.repeat !== undefined);
      check(retirementObserver, "actual selected retirement Timer");
      retirementObserver.stop();
      selected.destroy();
      phase = "native-retire-queued";
      return;
    }
      console.log("POMO_NATIVE: PASS " + scope + " " + mode + " " + boundary);
      Qt.exit(0);
    }
      function drive() {
      check(Date.now() - since < 18000, "finite native phase");
      if (phase === "runtime" && selected.settingsReady && sibling.settingsReady && inherited.settingsReady) {
      var context = scope === "instance" ? selected : api;
      bar = create("barWidget", context);
      panel = create("panel", context);
      phase = "initial";
    } else if (phase === "initial") {
      var name = mode === "edit" ? "initial" : mode === "reset" ? "edited" : mode === "follow" ? "reset" : boundary;
      if (!ready(name))
      return;
      if (mode === "cold")
      consumers(boundary);
      else if (mode === "edit")
      probe("initial", "open-discard");
      else if (mode === "follow")
      phase = "change-base";
      else
      open("reset-page");
    } else if (phase === "open-discard")
      open("discard-page");
      else if (phase === "discard-page" && popup.opened && popup.settingsPage) {
      check(!popup.dirty, "construction has no intent");
      edit();
      check(!popup.requestClose(), "dirty Close refuses");
      popup.confirmDiscard();
      phase = "discarded";
    } else if (phase === "discarded" && !popup.opened && !popup._editor)
      probe("discarded", "open-edit");
      else if (phase === "open-edit")
      open("edit-page");
      else if (phase === "edit-page" && popup.opened && popup.settingsPage) {
      edit();
      apply("applied");
    } else if (phase === "applied" && accepted() && ready("edited"))
      probe("edited", "edited-consumers");
      else if (phase === "edited-consumers")
      consumers("edited");
      else if (phase === "reset-page" && popup.opened && popup.settingsPage && !popup.busy) {
      check(popup._pageApi.resetFields(keys), "staged native Reset");
      phase = "reset-staging";
    } else if (phase === "reset-staging" && !popup.busy && keys.every(key => popup._pageApi.field(key).pendingIntent === "reset"))
      probe("reset-staged", "reset-apply");
      else if (phase === "reset-apply")
      apply("reset-applied");
      else if (phase === "reset-applied" && accepted() && ready("reset"))
      probe("reset", "reset-consumers");
      else if (phase === "reset-consumers")
      consumers("reset");
      else if (phase === "change-base") {
      for (var i = 0; i < keys.length; ++i)
      api.pluginSettings[keys[i]] = following[i];
      phase = "base-saving";
      api.saveSettings(result => {
      try {
      check(result.status === "saved", "native base propagation");
      phase = "base-changed";
    } catch (error) {
      fail(error);
    }
    });
    } else if (phase === "base-changed" && ready("following"))
      probe("following", "following-consumers");
      else if (phase === "following-consumers")
      consumers("following");
      else if (phase === "native-retire-queued") {
      check(!retainedContext.current() && !retainedTimer.current, "actual native origin retires");
      retainedTimer.pomodoroStart();
      check(!retainedTimer.pomodoroRunning, "retained native timer action refuses");
      retirementObserver.restart();
      phase = "native-retired";
    } else if (phase === "native-retired" && Date.now() - since > 200) {
      check(retainedTimer === null && !main._settingsConsumers.has(retainedContext) && panel.mainInstance === null, "native retirement destroys selected timer and view reference");
      check(main.timerFor(sibling).current && main.timerFor(api).current, "other native timers remain available");
      retainedTimer = main.timerFor(sibling);
      main.destroy();
      phase = "native-main-destroyed";
    } else if (phase === "native-main-destroyed" && Date.now() - since > 200) {
      check(main === null && retainedTimer === null, "actual Main destroys native timer children");
      probe("edited", "native-life-done");
    } else if (phase === "native-life-done") {
      console.log("POMO_NATIVE_LIFETIME: PASS");
      console.log("POMO_NATIVE: PASS " + scope + " " + mode);
      Qt.exit(0);
    }
    }
      Connections {
      target: Settings
      function onSettingsLoaded() {
      root.begin();
    }
    }
      Timer {
      interval: 50
      repeat: true
      running: true
      onTriggered: {
      try {
      root.drive();
    } catch (error) {
      root.fail(error);
    }
    }
    }
      Component.onCompleted: begin()
    }
