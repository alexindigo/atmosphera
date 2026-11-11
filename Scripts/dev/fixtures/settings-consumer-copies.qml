// Inert entrypoint copied to the candidate config root by the VM driver.
// Calls production components/services, then saves and verifies in a cold process.
import QtQuick
import Quickshell
import qs.Commons
import qs.Modules.Bar.Extras as Extras
import qs.Modules.Panels.Settings.Bar as BarSettings
import qs.Modules.Panels.Settings.Tabs.Audio as AudioSettings
import qs.Services.Plugins
import qs.Services.UI
import "../../../Helpers/SettingsListCommands.js" as NativeLists

Item {
  id: root
  readonly property var testScreen: Quickshell.screens[0]
  property bool started: false
  property bool verifyOnly: Quickshell.env("I4_VERIFY") === "1"
  property var waiters: []
  readonly property var commandPaths: [["bar", "widgets", "left"], ["bar", "widgets", "center"],
    ["bar", "widgets", "right"], ["bar", "screenOverrides"], ["desktopWidgets", "monitorWidgets"]]

  function waitFor(predicate) {
    return new Promise(function (resolve) {
      root.waiters = root.waiters.concat([{predicate: predicate, resolve: resolve}]);
    });
  }
  function settled() {
    return commandPaths.every(function (path) { return NativeLists.settled(Settings.store.info(path)); });
  }
  function action(name, submit, observed) {
    return waitFor(settled).then(function () {
      console.log("I5_CONSUMER_ACTION|" + name + "|submit|" + JSON.stringify(commandPaths.map(function (path) { return Settings.store.info(path); })));
      check(submit() === true, name + " admitted for worker processing");
      return waitFor(function () { return settled() && observed(); });
    }).then(function () {
      console.log("I5_CONSUMER_ACTION|" + name + "|observed");
      // A writer may still be saving after its live value appears. An action
      // ends at publication, so every following capture sees its settled source.
      return save();
    });
  }
  function save() {
    return new Promise(function (resolve, reject) {
      Settings.saveImmediate(function (result) {
        if (result.status === "failed") reject(new Error("I4_CONSUMER_ASSERT: save " + JSON.stringify(result)));
        else resolve(result);
      });
    });
  }

  BarSettings.MonitorWidgetsConfig {
    id: monitor
    screen: root.testScreen
  }
  AudioSettings.MediaSubTab {
    id: media
  }
  Extras.TrayMenu {
    id: tray
    shellScreen: root.testScreen
    widgetSection: "left"
    widgetIndex: 0
    trayItem: ({
                 "tooltipTitle": "I4 synthetic tray",
                 "menu": null
               })
  }

  function check(ok, name) {
    if (!ok)
      throw new Error("I4_CONSUMER_ASSERT: " + name);
  }

  function finishProcess(code) {
    // A cold consumer may finish before the application's main exec starts.
    // Queue every terminal path through the same process-lifecycle boundary.
    Qt.callLater(function () {
      Qt.exit(code);
    });
  }

  function screenWidgets() {
    return Settings.getBarWidgetsForScreen(testScreen.name);
  }

  function finalChecks() {
    check(Settings.data.audio.mprisBlacklist.join(",") === "alpha,gamma", "blacklist owner");
    check(screenWidgets().left[0].id === "Tray" && screenWidgets().left[0].pinned.length === 0, "tray unpin owner");
    check(screenWidgets().left[0].compact === true && screenWidgets().left[0].opaque === "keep", "screen dialog patch");
    check(Settings.data.bar.widgets.left[0].compact === true && Settings.data.bar.widgets.left[0].opaque === "keep", "global dialog patch");
    check(Settings.data.bar.widgets.right.length === 0 && screenWidgets().right.length === 0, "plugin removals");
    check(Settings.data.desktopWidgets.monitorWidgets[0].widgets.length === 1, "desktop removal");
    check(Settings.data.desktopWidgets.monitorWidgets[0].opaque === "monitor" && Settings.data.desktopWidgets.monitorWidgets[0].widgets[0].opaque === "widget", "desktop ancestry retained");
  }

  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    try {
      if (verifyOnly) {
        finalChecks();
        console.log("I4_CONSUMER_COPIES: RESTART_PASS");
        finishProcess(0);
        return;
      }
      Settings.data.bar.widgets.left = [
            {
              "id": "Tray",
              "pinned": [],
              "opaque": "keep"
            }
          ];
      Settings.data.bar.widgets.center = [];
      Settings.data.bar.widgets.right = [];
      Settings.data.bar.screenOverrides = [];
      Settings.data.audio.mprisBlacklist = ["alpha", "beta", "gamma"];
      Settings.data.desktopWidgets.monitorWidgets = [
            {
              "name": "offline",
              "opaque": "monitor",
              "widgets": [
                {
                  "id": "plugin:i4-keep",
                  "opaque": "widget"
                },
                {
                  "id": "plugin:i4-remove"
                }
              ]
            }
          ];

      // Establish the seeded source preimage before capturing commands. A
      // concurrent startup autosave legitimately changes native provenance.
      save().then(function () { return waitFor(settled); }).then(runMonitorWriters).catch(fail);
    } catch (error) {
      fail(error);
    }
  }

  function runMonitorWriters() {
      var copy = monitor._getWidgetsContainer();
      check(Object.keys(copy).sort().join(",") === "center,left,right", "namespace copy contains only declared data leaves");
      copy.right.push({
                        "id": "unpublished"
                      });
      check(!Settings.hasScreenOverride(testScreen.name, "widgets"), "copy getter creates no choice");
      check(Settings.data.bar.widgets.right.length === 0, "copy getter does not alias global");
      return action("monitor add A", function () { return monitor._addWidgetToSection("I4-A", "right"); },
        function () { return screenWidgets().right.length === 1; })
      .then(function () { return action("monitor add B", function () { return monitor._addWidgetToSection("I4-B", "right"); },
        function () { return screenWidgets().right.length === 2; }); })
      .then(function () { return action("monitor reorder", function () { return monitor._reorderWidgetInSection("right", 0, 1); },
        function () { return screenWidgets().right[0].id === "I4-B"; }); })
      .then(function () { return action("monitor update", function () { return monitor._updateWidgetSettingsInSection("right", 0, {
                                               "id": "I4-B",
                                               "opaque": "updated"
                                              }); }, function () { return screenWidgets().right[0].opaque === "updated"; }); })
      .then(function () { return action("monitor atomic move", function () { return monitor._moveWidgetBetweenSections("right", 0, "center"); },
        function () { return screenWidgets().center.length === 1 && screenWidgets().right.length === 1; }); })
      .then(function () {
      check(screenWidgets().center[0].opaque === "updated" && screenWidgets().right[0].id === "I4-A", "monitor atomic move");
      return action("monitor remove center", function () { return monitor._removeWidgetFromSection("center", 0); },
        function () { return screenWidgets().center.length === 0; }); })
      .then(function () { return action("monitor remove right", function () { return monitor._removeWidgetFromSection("right", 0); },
        function () { return screenWidgets().right.length === 0; }); })
      .then(function () { return action("global dialog patch", function () { return BarService.updateWidgetSettings("", "left", 0, {
                                        "compact": true
                                      }); }, function () { return Settings.data.bar.widgets.left[0].compact === true; }); })
      .then(function () { return action("screen dialog patch", function () { return BarService.updateWidgetSettings(testScreen.name, "left", 0, {
                                        "compact": true
                                      }); }, function () { return screenWidgets().left[0].compact === true; }); })
      .then(pinAndUnpin);
  }

  function pinAndUnpin() {
      tray.addToPinned(function (pin) {
        try {
          check(pin.status !== "failed", "tray pin receipt");
          check(tray._pinEditor === null, "successful immediate pin releases its action editor before callback");
          check(screenWidgets().left[0].pinned[0] === "I4 synthetic tray", "tray pin owner");
          tray.removeFromPinned(function (unpin) {
            try {
              check(unpin.status !== "failed", "tray unpin receipt");
              check(tray._pinEditor === null, "successful immediate unpin releases its action editor before callback");
              root.finishOtherWriters();
            } catch (error) {
              root.fail(error);
            }
          });
        } catch (error) {
          root.fail(error);
        }
      });
  }

  function finishOtherWriters() {
    try {
      media.removeBlacklistedPlayer("beta");
      action("plugin add command", function () { return Service.addWidgetToBar("plugin:i4-added", "right"); },
        function () { return Settings.data.bar.widgets.right.length === 1 && screenWidgets().right.length === 1; })
      .then(function () {
      check(Settings.data.bar.widgets.right[0].id === "plugin:i4-added" && screenWidgets().right[0].id === "plugin:i4-added", "plugin global and screen add");
        return save();
      }).then(function (result) {
          check(result.status === "saved" || result.status === "nothing_to_save", "add receipt");
          return action("plugin remove command", function () { return Service.removeWidgetFromBar("plugin:i4-added"); },
            function () { return Settings.data.bar.widgets.right.length === 0 && screenWidgets().right.length === 0; });
      }).then(function () {
          return action("desktop remove command", function () { return Service.removePluginDesktopWidgetsFromSettings("i4-remove"); },
            function () { return Settings.data.desktopWidgets.monitorWidgets[0].widgets.length === 1; });
      }).then(save).then(function (finalResult) {
              check(finalResult.status === "saved" || finalResult.status === "nothing_to_save", "final receipt");
              finalChecks();
              console.log("I4_CONSUMER_COPIES: SAVED_PASS");
              root.finishProcess(0);
      }).catch(fail);
    } catch (error) {
      fail(error);
    }
  }

  function fail(error) {
    console.error(String(error));
    finishProcess(2);
  }

  Connections {
    target: Settings
    function onSettingsLoaded() {
      root.begin();
    }
  }
  Connections {
    target: Settings.store
    function onCompleted(result) {
      console.log("I5_CONSUMER_RECEIPT|" + JSON.stringify(result));
      if (result.operation === "editRecordList") console.log("I5_CONSUMER_STATE|" + JSON.stringify(commandPaths.map(function (path) { return Settings.store.info(path); })) + "|" + JSON.stringify(Settings.store.copyValue(Settings.data.bar.screenOverrides)));
      if (result.operation === "editRecordList" && result.status === "failed") root.fail(JSON.stringify(result));
    }
  }
  Component.onCompleted: begin()
  Timer {
    interval: 10
    running: true
    repeat: true
    onTriggered: {
      var current = root.waiters;
      root.waiters = [];
      current.forEach(function (entry) {
        try {
          if (entry.predicate()) entry.resolve();
          else root.waiters = root.waiters.concat([entry]);
        } catch (error) { root.fail(error); }
      });
    }
  }
  Timer {
    // Several real controls enqueue full old-owner saves before our fence. This
    // is a functional witness, not I6's separate GUI-thread timing gate.
    interval: 90000
    running: true
    onTriggered: root.fail("I4 consumer watchdog")
  }
}
