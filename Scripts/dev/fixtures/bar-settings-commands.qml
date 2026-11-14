// Inert real BarService field-command contract, run only in the assigned VM.
import QtQuick
import Quickshell
import qs.Commons
import qs.Modules.Panels.Settings.Bar as Bar
import qs.Services.UI

PanelWindow {
  id: root
  implicitWidth: 800
  implicitHeight: 700
  color: "transparent"
  property int dialogStage: 0
  Item {
    id: dialogParent
    anchors.fill: parent
    Bar.BarWidgetSettingsDialog {
      id: dialog
      parent: dialogParent
      screen: root.testScreen
      onSettingsSaveCompleted: result => root.dialogResult(result)
    }
  }
  readonly property var testScreen: Quickshell.screens[0]
  property bool started: false
  property int route: 0
  property var editor: null
  function check(ok, name) {
    if (!ok)
      throw new Error("I4_BAR_ASSERT: " + name);
  }
  function fail(error) {
    console.error(String(error));
    Qt.exit(2);
  }
  function rows() {
    return Settings.getBarWidgetsForScreen(testScreen.name).left;
  }
  function assign(value) {
    if (route === 0)
      Settings.data.bar.widgets.left = value;
    else
      Settings.data.bar.screenOverrides = [
            {
              name: testScreen.name,
              opaque: "monitor",
              widgets: {
                left: value,
                center: [],
                right: [
                  {
                    id: "sibling"
                  }
                ]
              }
            }
          ];
  }
  function seed() {
    assign([
             {
               id: "Volume",
               opaque: "first"
             },
             {
               id: "Volume",
               opaque: "second"
             }
           ]);
  }
  function capture() {
    if (typeof BarService.createWidgetSettingsEditor === "function")
      editor = BarService.createWidgetSettingsEditor(testScreen.name, "left", 0);
    else
      editor = {
        submit: function (fields, callback) {
          return BarService.updateWidgetSettings(testScreen.name, "left", 0, fields, callback);
        }
      };
    check(editor !== null, "capture " + route);
  }
  function rejected(result, code) {
    check(result.status === "failed" && result.error.code === code, code + " " + route);
  }
  function stale() {
    seed();
    capture();
    var old = JSON.parse(JSON.stringify(rows()));
    assign([old[1], old[0]]);
    var before = JSON.stringify(rows());
    editor.submit({
                    displayMode: "alwaysShow"
                  }, function (result) {
                    try {
                      rejected(result, "list-edit-conflict");
                      aba();
                    } catch (error) {
                      fail(error);
                    }
                  });
    check(JSON.stringify(rows()) === before, "captured bar refuses repeated-ID replacement " + route);
  }
  function aba() {
    seed();
    capture();
    var old = JSON.parse(JSON.stringify(rows()));
    assign([
             {
               id: "intervening"
             }
           ]);
    assign(old);
    check(editor.submit({
                          displayMode: "alwaysShow"
                        }, function (result) {
                          try {
                            rejected(result, "list-edit-conflict");
                            if (route === 0)
                              routing();
                            else
                              failedSave();
                          } catch (error) {
                            fail(error);
                          }
                        }) === false, "notified ABA refused " + route);
    check(rows()[0].displayMode === undefined, "ABA unchanged consumer " + route);
  }
  function routing() {
    seed();
    capture();
    Settings.data.bar.screenOverrides = [
          {
            name: testScreen.name,
            widgets: {
              left: [
                {
                  id: "Volume"
                }
              ],
              center: [],
              right: []
            }
          }
        ];
    check(editor.submit({
                          displayMode: "alwaysShow"
                        }, function (result) {
                          try {
                            rejected(result, "list-edit-conflict");
                            check(rows()[0].displayMode === undefined && Settings.data.bar.widgets.left[0].displayMode === undefined, "both routes unchanged");
                            Settings.data.bar.screenOverrides = [
                                  {
                                    name: testScreen.name,
                                    enabled: false,
                                    widgets: {
                                      left: [
                                        {
                                          id: "Volume"
                                        }
                                      ],
                                      center: [],
                                      right: []
                                    }
                                  }
                                ];
                            seed();
                            capture();
                            editor.submit({
                                            displayMode: "alwaysHide"
                                          }, function (disabled) {
                                            try {
                                              check(disabled.status !== "failed", "disabled override receipt");
                                              check(Settings.data.bar.widgets.left[0].displayMode === "alwaysHide", "disabled override displayed global consumer");
                                              check(Settings.data.bar.screenOverrides[0].widgets.left[0].displayMode === undefined, "disabled override untouched");
                                              Settings.data.bar.screenOverrides = [];
                                              failedSave();
                                            } catch (error) {
                                              fail(error);
                                            }
                                          });
                          } catch (error) {
                            fail(error);
                          }
                        }) === false, "route change refused");
  }
  function failedSave() {
    seed();
    capture();
    Settings.setBindingsUnresolved(true);
    check(editor.submit({
                          displayMode: "alwaysShow"
                        }, function (result) {
                          try {
                            check(result.status === "failed", "failed aggregate receipt " + route);
                            check(rows()[0].displayMode === "alwaysShow", "failed save retains admitted input " + route);
                            Settings.setBindingsUnresolved(false);
                            check(editor.submit({
                                                  displayMode: "alwaysShow"
                                                }, function (retry) {
                                                  try {
                                                    check(retry.status !== "failed", "same session retry " + route);
                                                    saved();
                                                  } catch (error) {
                                                    fail(error);
                                                  }
                                                }) === true, "retry admitted " + route);
                          } catch (error) {
                            fail(error);
                          }
                        }) === true, "failure input admitted " + route);
  }
  function saved() {
    seed();
    capture();
    var fields = {
      id: "legacy page id is not field intent",
      displayMode: "alwaysHide"
    };
    check(editor.submit(fields, function (result) {
      try {
        check(result.status === "saved" || result.status === "nothing_to_save", "acknowledged field edit " + route);
        check(rows()[0].displayMode === "alwaysHide" && rows()[0].id === "Volume", "actual edited consumer " + route);
        check(rows()[0].opaque === "first" && rows()[1].opaque === "second" && rows()[1].displayMode === undefined, "unrelated fields and repeated sibling preserved " + route);
        var held = editor;
        held.detach();
        check(held.submit({
                            displayMode: "onhover"
                          }, function (detached) {
                            try {
                              rejected(detached, "list-editor-closed");
                              if (route === 0) {
                                route = 1;
                                stale();
                              } else {
                                finalChecks();
                                dialogCases();
                              }
                            } catch (error) {
                              fail(error);
                            }
                          }) === false, "detached refuses new input " + route);
      } catch (error) {
        fail(error);
      }
    }) === true, "edit admitted " + route);
    fields.displayMode = "mutated after submission";
    check(editor.submit({
                          displayMode: "onhover"
                        }, function (busy) {
                          try {
                            rejected(busy, "list-editor-busy");
                          } catch (error) {
                            fail(error);
                          }
                        }) === false, "busy refusal " + route);
  }
  function dialogCases() {
    seed();
    dialog.settingsEditor = BarService.createWidgetSettingsEditor(testScreen.name, "left", 0);
    dialog.widgetData = dialog.settingsEditor.initialValue;
    dialog.open();
    Settings.setBindingsUnresolved(true);
    check(dialog.queueSettings({
                                 displayMode: "alwaysHide"
                               }), "dialog queues owned fields");
    dialog.saveAndClose();
    check(dialog.visible && dialog.saveBusy, "close waits for actual receipt");
  }
  function dialogResult(result) {
    try {
      if (dialogStage === 0) {
        check(result.status === "failed" && dialog.visible && dialog.settingsDirty && dialog.saveFailed, "failed receipt retains real dialog work");
        check(rows()[0].displayMode === "alwaysHide", "failure retains admitted consumer");
        dialogStage = 1;
        Settings.setBindingsUnresolved(false);
        Qt.callLater(function () {
          dialog.saveAndClose();
        });
      } else if (dialogStage === 1) {
        check(result.status !== "failed" && !dialog.settingsDirty, "real dialog retry receipt");
        Qt.callLater(function () {
          try {
            check(!dialog.visible, "real dialog closes after successful retry");
            seed();
            dialog.settingsEditor = BarService.createWidgetSettingsEditor(testScreen.name, "left", 0);
            dialog.widgetData = dialog.settingsEditor.initialValue;
            dialog.open();
            var old = JSON.parse(JSON.stringify(rows()));
            assign([old[1], old[0]]);
            dialogStage = 2;
            dialog.queueSettings({
                                   displayMode: "alwaysHide"
                                 });
            dialog.saveAndClose();
          } catch (error) {
            root.fail(error);
          }
        });
      } else if (dialogStage === 2) {
        rejected(result, "list-edit-conflict");
        check(dialog.visible && dialog.settingsDirty && rows()[0].displayMode === undefined, "stale dialog retains local work and unchanged consumer");
        check(dialog.confirmDiscard() === false && dialog.visible, "discard requires explicit confirmation");
        dialog.requestDiscard();
        check(dialog.discardPending, "discard confirmation opens");
        dialog.keepEditing();
        check(!dialog.discardPending && dialog.visible && dialog.settingsDirty, "cancel discard retains dialog work");
        dialog.requestDiscard();
        check(dialog.confirmDiscard() === true, "explicitly confirmed discard");
        Qt.callLater(function () {
          try {
            check(!dialog.visible && !dialog.settingsDirty && rows()[0].displayMode === undefined, "confirmed local discard does not roll back or write settings");
            dialog.settingsEditor = BarService.createWidgetSettingsEditor(testScreen.name, "left", 0);
            dialog.widgetData = dialog.settingsEditor.initialValue;
            dialog.open();
            dialogStage = 3;
            dialog.queueSettings({
                                   displayMode: "alwaysHide"
                                 });
            dialog.saveAndClose();
            // A second user edit arrives while the first actual save is pending.
            check(dialog.saveBusy, "actual save is held across queued input");
            dialog.queueSettings({
                                   iconColor: "primary"
                                 });
          } catch (error) {
            root.fail(error);
          }
        });
      } else if (dialogStage === 3) {
        check(result.status !== "failed" && dialog.visible && dialog.settingsDirty, "first receipt retains newer queued work and pending close");
        dialogStage = 4;
      } else if (dialogStage === 4) {
        check(result.status !== "failed" && !dialog.settingsDirty, "queued input receives its own actual receipt");
        check(rows()[0].displayMode === "alwaysHide" && rows()[0].iconColor === "primary", "newer fields reach actual consumer before close");
        Qt.callLater(function () {
          try {
            check(!dialog.visible, "close follows final queued receipt");
            // Restore the deliberately reversed rows while retaining the observed
            // queued field for independent parsed-file and cold-restart checks.
            assign([
                     {
                       id: "Volume",
                       opaque: "first",
                       displayMode: "alwaysHide",
                       iconColor: "primary"
                     },
                     {
                       id: "Volume",
                       opaque: "second"
                     }
                   ]);
            Settings.saveResult(function (finalResult) {
              try {
                check(finalResult.status !== "failed", "final ordering save");
                finalChecks();
                console.log("I4_BAR_COMMANDS: SAVED_PASS");
                Qt.exit(0);
              } catch (error) {
                root.fail(error);
              }
            });
          } catch (error) {
            root.fail(error);
          }
        });
      }
    } catch (error) {
      fail(error);
    }
  }
  function finalChecks() {
    var globalRow = Settings.data.bar.widgets.left[0];
    var screenRow = rows()[0];
    check(globalRow.displayMode === "alwaysHide" && globalRow.opaque === "first" && globalRow.id === "Volume", "global cold consumer");
    check(screenRow.displayMode === "alwaysHide" && screenRow.opaque === "first" && screenRow.id === "Volume", "screen cold consumer");
    if (dialogStage === 4 || Quickshell.env("I4_VERIFY") === "1")
      check(screenRow.iconColor === "primary", "queued field cold consumer");
    check(Settings.data.bar.screenOverrides[0].opaque === "monitor" && Settings.getBarWidgetsForScreen(testScreen.name).right[0].id === "sibling", "monitor ancestry preserved");
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    try {
      if (Quickshell.env("I4_VERIFY") === "1") {
        finalChecks();
        console.log("I4_BAR_COMMANDS: RESTART_PASS");
        Qt.exit(0);
      } else {
        Settings.data.bar.screenOverrides = [];
        stale();
      }
    } catch (error) {
      fail(error);
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
    interval: 120000
    running: true
    onTriggered: root.fail("bar commands watchdog")
  }
}
