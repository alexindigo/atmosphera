// Real plugin placement owner: captured at batches and registration-before-add.
import QtQuick
import Quickshell
import qs.Commons
import qs.Services.Plugins
import qs.Services.UI

Scope {
  id: root
  property bool started: false
  property bool verifyOnly: Quickshell.env("I4_VERIFY") === "1"
  readonly property bool registrationOnly: Quickshell.env("I4_REGISTRATION_ONLY") === "1"
  property int screenWrites: 0
  property int desktopWrites: 0
  property int leftWrites: 0
  property int centerWrites: 0
  property int rightWrites: 0
  property int stage: 0
  property int polls: 0
  property bool registrationObserved: false
  readonly property string removed: "plugin:i4-remove"
  readonly property string added: "plugin:i4-add"
  function check(ok, text) {
    if (!ok)
      throw new Error("I4_PLUGIN_PLACEMENT_ASSERT: " + text);
  }
  function fail(error) {
    console.error(String(error));
    Qt.exit(2);
  }
  function receipt(next) {
    Settings.saveResult(function (result) {
      try {
        check(result.status !== "failed", "save receipt");
        next();
      } catch (error) {
        fail(error);
      }
    });
  }
  function seedBar() {
    Settings.data.bar.widgets.left = [
          {
            id: removed,
            tag: "one"
          },
          {
            id: "Clock",
            opaque: {
              keep: true
            }
          },
          {
            id: removed,
            tag: "two"
          }
        ];
    Settings.data.bar.widgets.center = [
          {
            id: removed
          }
        ];
    Settings.data.bar.widgets.right = [];
    Settings.data.bar.screenOverrides = [
          {
            name: "i4-a",
            opaque: "monitor-a",
            widgets: {
              left: [
                {
                  id: removed
                },
                {
                  id: "Clock",
                  opaque: {
                    keep: true
                  }
                }
              ]
            }
          },
          {
            name: "i4-b",
            opaque: "monitor-b",
            widgets: {
              right: [
                {
                  id: removed
                }
              ]
            }
          },
          {
            name: "i4-a",
            opaque: "later-duplicate",
            widgets: {
              left: [
                {
                  id: removed,
                  tag: "duplicate"
                }
              ]
            }
          },
          {
            name: "i4-empty",
            opaque: "empty",
            widgets: {}
          },
          {
            name: "i4-none",
            opaque: "none"
          },
          {
            name: "i4-existing",
            widgets: {
              center: [
                {
                  id: added,
                  opaque: "existing"
                }
              ]
            }
          }
        ];
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    try {
      if (verifyOnly) {
        finalChecks();
        console.log("I4_PLUGIN_PLACEMENTS: RESTART_PASS");
        Qt.exit(0);
        return;
      }
      if (registrationOnly) {
        Settings.data.bar.widgets.left = [];
        Settings.data.bar.widgets.center = [];
        Settings.data.bar.widgets.right = [];
        Settings.data.bar.screenOverrides = [];
        startRegistration();
        return;
      }
      seedBar();
      if (Quickshell.env("I4_PARENT") === "1") {
        Service.removeWidgetFromBar(removed);
        check(Settings.data.bar.screenOverrides[0].widgets.center === undefined, "absent removal section stays absent");
        Qt.exit(3);
        return;
      }
      var command = Service.createBarWidgetInsertion(added, "right");
      check(command !== null, "capture insertion batch");
      command.detach();
      check(Settings.data.bar.screenOverrides[0].widgets.right === undefined, "cancel does not ensure a section");
      staleInsert();
    } catch (error) {
      fail(error);
    }
  }
  function staleInsert() {
    var command = Service.createBarWidgetInsertion(added, "right");
    var current = Settings.data.bar.screenOverrides;
    Settings.data.bar.screenOverrides = current.concat([
                                                         {
                                                           name: "intervening"
                                                         }
                                                       ]);
    Settings.data.bar.screenOverrides = current;
    var before = JSON.stringify(Settings.data.bar.screenOverrides);
    check(!command.submit(function (result) {
      try {
        check(result.status === "failed" && result.error.code === "list-edit-conflict", "insertion target ABA refuses");
        check(JSON.stringify(Settings.data.bar.screenOverrides) === before && Settings.data.bar.widgets.right.length === 0, "stale insertion changes no owner");
        invalidInsert();
      } catch (error) {
        fail(error);
      }
    }), "stale insertion admission false");
  }
  function invalidInsert() {
    Settings.data.bar.screenOverrides = [
          {
            name: "i4-good",
            widgets: {}
          },
          {
            name: "i4-null",
            widgets: {
              right: null
            }
          }
        ];
    var before = JSON.stringify(Settings.data.bar.screenOverrides), count = rightWrites;
    check(!Service.addWidgetToBar(added, "right"), "late null destination refuses");
    check(rightWrites === count && JSON.stringify(Settings.data.bar.screenOverrides) === before, "invalid target causes no global or earlier target write");
    seedBar();
    var screens = screenWrites, right = rightWrites;
    check(Service.addWidgetToBar(added, "right"), "actual immediate insertion");
    check(screenWrites === screens + 1 && rightWrites === right + 1, "one assignment per insertion owner");
    var rows = Settings.data.bar.screenOverrides;
    check(rows[0].widgets.right[0].id === added && rows[1].widgets.right[1].id === added && rows[3].widgets.right[0].id === added, "all selected targets inserted");
    check(rows[0].opaque === "monitor-a" && rows[0].widgets.left[1].opaque.keep && rows[2].opaque === "later-duplicate" && rows[2].widgets.right === undefined, "unknowns and first duplicate preserved");
    check(rows[4].widgets === undefined && rows[5].widgets.right === undefined, "nonconfigured and already-present targets unchanged");
    var noChange = screenWrites + leftWrites + centerWrites + rightWrites;
    check(!Service.addWidgetToBar(added, "left") && noChange === screenWrites + leftWrites + centerWrites + rightWrites, "duplicate add is inert");
    receipt(staleRemove);
  }
  function staleRemove() {
    var command = Service.createBarWidgetRemoval(removed);
    Settings.data.bar.widgets.center = [
          {
            id: removed,
            tag: "foreign"
          }
        ];
    var before = JSON.stringify(Settings.data.bar.screenOverrides), count = screenWrites, left = leftWrites;
    check(!command.submit(function (result) {
      try {
        check(result.status === "failed" && screenWrites === count && leftWrites === left && JSON.stringify(Settings.data.bar.screenOverrides) === before, "one stale supplied owner prevents every removal");
        removeBar();
      } catch (error) {
        fail(error);
      }
    }), "stale removal admission false");
  }
  function removeBar() {
    var count = screenWrites, left = leftWrites, center = centerWrites, right = rightWrites;
    check(Service.removeWidgetFromBar(removed), "actual bar removal");
    check(screenWrites === count + 1 && leftWrites === left + 1 && centerWrites === center + 1 && rightWrites === right, "each touched leaf once, untouched global not assigned");
    var rows = Settings.data.bar.screenOverrides;
    check(rows[0].widgets.center === undefined && rows[1].widgets.left === undefined && rows[1].widgets.center === undefined, "absent removal section stays absent");
    check(rows[2].widgets.left[0].tag === "duplicate" && rows[0].widgets.left[0].opaque.keep, "duplicate and surviving unknown row preserved");
    check(Settings.data.bar.widgets.left.length === 1 && Settings.data.bar.widgets.center.length === 0, "reverse-index repeated removals");
    receipt(desktop);
  }
  function desktop() {
    Settings.data.desktopWidgets.monitorWidgets = [
          {
            name: "i4-a",
            opaque: "desktop-a",
            widgets: [
              {
                id: removed
              },
              {
                id: "Clock",
                opaque: {
                  keep: true
                }
              },
              {
                id: removed
              }
            ]
          },
          {
            name: "i4-b",
            opaque: "desktop-b",
            widgets: [
              {
                id: removed
              }
            ]
          },
          {
            name: "i4-a",
            opaque: "desktop-duplicate",
            widgets: [
              {
                id: removed,
                tag: "duplicate"
              }
            ]
          },
          {
            name: "i4-absent",
            opaque: "desktop-absent"
          }
        ];
    var command = Service.createPluginDesktopRemoval("i4-remove");
    var current = Settings.data.desktopWidgets.monitorWidgets;
    Settings.data.desktopWidgets.monitorWidgets = current.concat([
                                                                   {
                                                                     name: "intervening",
                                                                     widgets: []
                                                                   }
                                                                 ]);
    Settings.data.desktopWidgets.monitorWidgets = current;
    var count = desktopWrites;
    check(!command.submit(function (result) {
      try {
        check(result.status === "failed" && desktopWrites === count, "stale desktop batch changes nothing");
        check(Service.removePluginDesktopWidgetsFromSettings("i4-remove"), "actual desktop cleanup");
        check(desktopWrites === count + 1, "desktop cleanup is one owning-leaf assignment across monitors");
        var rows = Settings.data.desktopWidgets.monitorWidgets;
        check(rows[0].opaque === "desktop-a" && rows[0].widgets[0].opaque.keep && rows[1].widgets.length === 0, "desktop unknown ancestry and empty list retained");
        check(rows[2].widgets[0].tag === "duplicate" && rows[3].widgets === undefined, "later duplicate and missing widgets untouched");
        check(!Service.removePluginDesktopWidgetsFromSettings("i4-remove") && desktopWrites === count + 1, "duplicate-only leftover does not cause a second cleanup");
        receipt(startRegistration);
      } catch (error) {
        fail(error);
      }
    }), "stale desktop admission false");
  }
  function startRegistration() {
    stage = 1;
    polls = 0;
    registrationWait.start();
  }
  Timer {
    id: registrationWait
    interval: 10
    repeat: true
    onTriggered: {
      try {
        root.check(++root.polls < 2000, "bounded manifest discovery");
        if (Registry.getPluginManifest("i4-registration")) {
          stop();
          root.stage = 2;
          root.check(Service.enablePlugin("i4-registration"), "real enable accepted");
          root.check(!BarWidgetRegistry.hasWidget("plugin:i4-registration"), "data load is asynchronous");
        }
      } catch (error) {
        stop();
        root.fail(error);
      }
    }
  }
  Connections {
    target: BarWidgetRegistry
    function onPluginWidgetRegistryUpdated() {
      if (root.stage === 2 && BarWidgetRegistry.hasWidget("plugin:i4-registration")) {
        root.registrationObserved = true;
        // The row becomes visible with registration metadata, before auto-add.
        var rows = Settings.data.bar.widgets.left.slice();
        rows.push({
                    id: "plugin:i4-registration",
                    tag: "registered-retained"
                  });
        Settings.data.bar.widgets.left = rows;
      }
    }
  }
  Connections {
    target: Service
    function onPluginLoaded(key) {
      if (key === "i4-registration" && root.stage === 2) {
        root.stage = 3;
        Qt.callLater(function () {
          try {
            root.check(root.registrationObserved && BarWidgetRegistry.hasWidget("plugin:i4-registration"), "actual registration consumer");
            root.check(Settings.data.bar.widgets.right.length === (root.registrationOnly ? 0 : 1) && (root.registrationOnly || Settings.data.bar.widgets.right[0].id === root.added), "duplicate check followed metadata visibility");
            if (root.registrationOnly) {
              console.log("I4_PLUGIN_REGISTRATION: PASS");
              Qt.exit(0);
            } else {
              root.finish();
            }
          } catch (error) {
            root.fail(error);
          }
        });
      }
    }
  }
  function finalChecks() {
    check(Settings.data.bar.widgets.left.length === 2 && Settings.data.bar.widgets.left[0].opaque.keep && Settings.data.bar.widgets.left[1].tag === "registered-retained", "final global consumer");
    check(Settings.data.bar.widgets.center.length === 0 && Settings.data.bar.widgets.right.length === 1 && Settings.data.bar.widgets.right[0].id === added, "final global removal/registration order");
    var screens = Settings.data.bar.screenOverrides;
    check(screens[0].opaque === "monitor-a" && screens[0].widgets.left[0].opaque.keep && screens[0].widgets.center === undefined, "final screen ancestry/absence");
    check(screens[1].widgets.right.length === 1 && screens[1].widgets.center === undefined && screens[2].widgets.left[0].tag === "duplicate", "final first-duplicate rule");
    check(screens[3].widgets.right[0].id === added && screens[4].widgets === undefined && screens[5].widgets.right === undefined, "final insertion targets");
    var desktops = Settings.data.desktopWidgets.monitorWidgets;
    check(desktops[0].opaque === "desktop-a" && desktops[0].widgets.length === 1 && desktops[0].widgets[0].opaque.keep && desktops[1].widgets.length === 0, "final desktop cleanup consumer");
    check(desktops[2].widgets[0].tag === "duplicate" && desktops[3].widgets === undefined, "final desktop duplicate/absence");
  }
  function finish() {
    receipt(function () {
      finalChecks();
      console.log("I4_PLUGIN_PLACEMENTS: SAVED_PASS");
      Qt.exit(0);
    });
  }
  Connections {
    target: Settings.data.bar
    function onScreenOverridesChanged() {
      root.screenWrites++;
    }
  }
  Connections {
    target: Settings.data.bar.widgets
    function onLeftChanged() {
      root.leftWrites++;
    }
    function onCenterChanged() {
      root.centerWrites++;
    }
    function onRightChanged() {
      root.rightWrites++;
    }
  }
  Connections {
    target: Settings.data.desktopWidgets
    function onMonitorWidgetsChanged() {
      root.desktopWrites++;
    }
  }
  Connections {
    target: Settings
    function onSettingsLoaded() {
      root.begin();
    }
  }
  Component.onCompleted: begin()
  Timer {
    interval: 90000
    running: true
    onTriggered: root.fail("plugin placement watchdog")
  }
}
