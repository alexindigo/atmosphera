import QtQuick
import Quickshell
import qs.Commons
import qs.Services.System
import qs.Services.UI

ShellRoot {
  id: root
  property var main: null
  property var first: null
  property var second: null
  property var retained: null
  property var firstApi: null
  property var secondApi: null
  property string phase: "startup"
  property double since: Date.now()
  property int tickStart: 0
  property int stops: 0
  property int checks: 0
  property int originalWork: 0
  property int originalSessions: 0
  Component {
    id: contextFactory
    QtObject {
      property bool alive: true
      property var settingsView: ({})
      function current() {
        return alive;
      }
    }
  }
  Component {
    id: apiFactory
    QtObject {
      property bool settingsReady: true
      property var settingsContext
      property var pluginSettings: ({})
      function tr(key) {
        return key;
      }
    }
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("POMO_LIFE_ASSERT: " + message);
    console.log("POMO_LIFE_CHECK: " + message);
    checks++;
  }
  function fail(error) {
    console.error(String(error) + "\n" + (error.stack || ""));
    Qt.exit(2);
  }
  function api(values) {
    var context = contextFactory.createObject(root, {
                                                settingsView: values
                                              });
    return apiFactory.createObject(root, {
                                     settingsContext: context
                                   });
  }
  function begin() {
    var component = Qt.createComponent(Quickshell.env("PHA_POMO_MAIN"));
    check(component.status === Component.Ready, component.errorString());
    firstApi = api({
                     workDuration: 2.51,
                     shortBreakDuration: 0.05,
                     longBreakDuration: 0.1,
                     sessionsBeforeLongBreak: 3.4,
                     autoStartBreaks: false,
                     autoStartWork: false,
                     compactMode: true,
                     playSound: false
                   });
    secondApi = api({
                      workDuration: 4,
                      shortBreakDuration: 1,
                      longBreakDuration: 2,
                      sessionsBeforeLongBreak: 4,
                      autoStartBreaks: false,
                      autoStartWork: false,
                      compactMode: false,
                      playSound: false
                    });
    main = component.createObject(root, {
                                    pluginApi: secondApi
                                  });
    check(main !== null, "actual Main constructs");
    first = main.timerFor(firstApi);
    second = main.timerFor(secondApi);
    check(first === main.timerFor(firstApi) && first !== second, "context cache shares views, not equal source values");
    originalWork = firstApi.settingsContext.settingsView.workDuration * 60;
    originalSessions = firstApi.settingsContext.settingsView.sessionsBeforeLongBreak;
    check(first.workDuration === originalWork && first.sessionsBeforeLongBreak === originalSessions, "original QML int conversion");
    first.pomodoroStart();
    check(first.pomodoroRemainingSeconds === originalWork && !second.pomodoroRunning, "selected start and independent sibling");
    first.pomodoroPause();
    var remaining = first.pomodoroRemainingSeconds;
    first.pomodoroStart();
    check(first.pomodoroRemainingSeconds === remaining, "resume retains remaining time");
    first.pomodoroPause();
    firstApi.settingsContext.settingsView = Object.assign({}, firstApi.settingsContext.settingsView, {
                                                            workDuration: 0.1
                                                          });
    phase = "source";
  }
  function drive() {
    if (phase === "source" && first.workDuration === 6) {
      check(first.pomodoroRemainingSeconds === originalWork, "source edit does not reset admitted countdown");
      first.pomodoroResetAll();
      first.pomodoroSetMode(first.modeWork);
      check(first.pomodoroRemainingSeconds === 6 && first.pomodoroTotalSeconds === 0, "reset/mode use current selected policy");
      for (var i = 0; i < first.sessionsBeforeLongBreak - 1; i++) {
        first.pomodoroSkip();
        check(first.pomodoroMode === first.modeShortBreak, "work selects short phase");
        first.pomodoroSkip();
        check(first.pomodoroMode === first.modeWork && first.pomodoroCompletedSessions === i + 1, "break advances completed sessions");
      }
      first.pomodoroSkip();
      check(first.pomodoroMode === first.modeLongBreak, "configured session count selects long break");
      first.pomodoroSkip();
      check(first.pomodoroMode === first.modeWork && first.pomodoroCompletedSessions === 0, "long break resets cycle");
      first.pomodoroOnFinished();
      check(first.pomodoroSoundPlaying && SoundService.plays === 0 && ToastService.notices === 1, "disabled audio preserves original alarm flag and notice");
      first.pomodoroStopAlarm();
      firstApi.settingsContext.settingsView = Object.assign({}, firstApi.settingsContext.settingsView, {
                                                              autoStartBreaks: true,
                                                              autoStartWork: true,
                                                              playSound: true
                                                            });
      phase = "automatic";
    } else if (phase === "automatic" && first.autoStartBreaks && first.autoStartWork && first.playSound) {
      first.pomodoroResetAll();
      first.pomodoroOnFinished();
      phase = "auto-break";
    } else if (phase === "auto-break") {
      check(first.pomodoroMode === first.modeShortBreak && first.pomodoroRunning && first.pomodoroRemainingSeconds === first.shortBreakDuration, "captured work completion auto-starts selected break");
      check(SoundService.plays === 1 && first.pomodoroSoundPlaying, "auto-start retains looping alarm");
      first.pomodoroOnFinished();
      phase = "auto-work";
    } else if (phase === "auto-work") {
      check(first.pomodoroMode === first.modeWork && first.pomodoroRunning, "break completion auto-starts work");
      first.pomodoroPause();
      check(!first.pomodoroRunning && !first.pomodoroSoundPlaying, "pause stops countdown and alarm");
      first.pomodoroRemainingSeconds = 20;
      first.pomodoroStart();
      tickStart = first.pomodoroRemainingSeconds;
      since = Date.now();
      phase = "tick";
    } else if (phase === "tick" && Date.now() - since >= 1150) {
      check(first.pomodoroRemainingSeconds === tickStart - 1 && !second.pomodoroRunning, "actual1000ms timer ticks only selected client");
      first.pomodoroPause();
      first.pomodoroSetMode(first.modeWork);
      first.pomodoroOnFinished();
      // Explicit pause in the same turn supersedes queued automatic start.
      first.pomodoroPause();
      phase = "cancel-auto";
    } else if (phase === "cancel-auto") {
      check(!first.pomodoroRunning, "later action fences delayed auto-start");
      firstApi.settingsContext.settingsView = Object.assign({}, firstApi.settingsContext.settingsView, {
                                                              autoStartBreaks: false,
                                                              autoStartWork: false
                                                            });
      phase = "alarm-ready";
    } else if (phase === "alarm-ready" && !first.autoStartBreaks && !first.autoStartWork) {
      first.pomodoroSetMode(first.modeWork);
      first.pomodoroOnFinished();
      since = Date.now();
      phase = "alarm";
    } else if (phase === "alarm" && Date.now() - since >= 5150) {
      check(!first.pomodoroSoundPlaying && SoundService.active === false, "actual5000ms alarm limit stops sound");
      // Retirement in this same turn must also fence the pending auto-start.
      first.pomodoroSetMode(first.modeWork);
      first.pomodoroOnFinished();
      retained = first;
      firstApi.settingsContext.alive = false;
      check(!retained.current, "retained context refuses after source retirement");
      retained.pomodoroStart();
      check(!retained.pomodoroRunning, "retired action and queued auto-start refuse");
      since = Date.now();
      phase = "retired-cache";
    } else if (phase === "retired-cache" && Date.now() - since >= 200) {
      check(main.timerFor(firstApi) === null && !main._settingsConsumers.has(firstApi.settingsContext), "retirement removes exact client");
      secondApi.settingsContext.settingsView = Object.assign({}, secondApi.settingsContext.settingsView, {
                                                               playSound: true
                                                             });
      phase = "destroy";
    } else if (phase === "destroy" && second.playSound) {
      second.pomodoroOnFinished();
      check(SoundService.active, "second client owns alarm before destruction");
      stops = SoundService.stops;
      main.destroy();
      phase = "destroyed";
    } else if (phase === "destroyed") {
      check(!SoundService.active && SoundService.stops > stops, "Main destruction joins owned alarm before engine exit");
      console.log("POMO_LIFETIME: PASS " + checks);
      Qt.exit(0);
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
  Timer {
    interval: 20000
    running: true
    onTriggered: root.fail("watchdog: " + root.phase)
  }
  Component.onCompleted: {
    try {
      begin();
    } catch (error) {
      fail(error);
    }
  }
}
