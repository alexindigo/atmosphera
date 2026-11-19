import ConfigQml 1.0
import QtQuick
import Quickshell
import qs.Commons as Main

ShellRoot {
  id: root
  property bool started: false
  readonly property bool verifyOnly: Quickshell.env("I4_VERIFY") === "1"
  readonly property var cfg: store.values
  readonly property string consumer: store.ready ? cfg.sessionMenu.powerOptions[0]?.command || "" : "waiting"
  function check(ok, label) {
    if (!ok)
      throw new Error("I4_RECORD_SCHEMA_ASSERT: " + label);
  }
  function verify() {
    var row = cfg.bar.widgets.left[0];
    check(row.showIcon === false && row.pinned[0] === "fixture-app" && row.unknown.keep, "known widget fields and unknown extension consumer");
    check(row.maxTextLength.horizontal === 12 && row.environmentVars[0].key === "I4_INERT", "nested record/list consumers");
    check(cfg.controlCenter.shortcuts.left[0].showIcon === false, "shortcut widget contract");
    var monitor = cfg.bar.screenOverrides[0];
    check(monitor.enabled === false && monitor.density === "compact" && monitor.displayMode === "onhover" && monitor.widgets.right[0].pinned[0] === "fixture-app", "screen fields and nested widget consumer");
    var desktop = cfg.desktopWidgets.monitorWidgets;
    check(desktop[0].widgets[0].x === 1.25 && desktop[0].widgets[0].scale === 0.9 && desktop[1].widgets === undefined, "desktop placement and absent optional container");
    check(consumer === "inert-command" && cfg.sessionMenu.powerOptions[0].countdownEnabled === false, "power-option consumer");
    check(cfg.wallpaper.monitorDirectories[0].wallpaper === "inert-wallpaper", "authored monitor-directory field consumer");
  }
  function begin() {
    if (started || !store.ready)
      return;
    started = true;
    try {
      if (verifyOnly) {
        verify();
        console.log("I4_RECORD_SCHEMA: RESTART_PASS");
        Qt.exit(0);
        return;
      }
      var row = {
        id: "Tray",
        showIcon: false,
        pinned: ["fixture-app"],
        maxTextLength: {
          horizontal: 12,
          vertical: 8
        },
        environmentVars: [
          {
            key: "I4_INERT",
            value: "yes"
          }
        ],
        params: ["--inert"],
        unknown: {
          keep: true
        }
      };
      cfg.bar.widgets.left = [row];
      cfg.controlCenter.shortcuts.left = [row];
      cfg.bar.screenOverrides = [
            {
              name: "inert-screen",
              enabled: false,
              density: "compact",
              displayMode: "onhover",
              widgets: {
                right: [row]
              }
            }
          ];
      cfg.desktopWidgets.monitorWidgets = [
            {
              name: "inert-screen",
              widgets: [Object.assign({}, row, {
                                        x: 1.25,
                                        y: 2.5,
                                        scale: 0.9
                                      })]
            },
            {
              name: "unassigned"
            }
          ];
      cfg.sessionMenu.powerOptions = [
            {
              action: "lock",
              enabled: true,
              keybind: "1",
              countdownEnabled: false,
              command: "inert-command"
            }
          ];
      cfg.wallpaper.monitorDirectories = [
            {
              name: "inert-screen",
              directory: "inert-directory",
              wallpaper: "inert-wallpaper"
            }
          ];
      var rejected = 0;
      try {
        cfg.bar.widgets.left = [
              {
                id: "Tray",
                pinned: true
              }
            ];
      } catch (error) {
        rejected++;
      }
      try {
        cfg.controlCenter.shortcuts.left = [
              {
                id: "CustomButton",
                environmentVars: [false]
              }
            ];
      } catch (error) {
        rejected++;
      }
      try {
        cfg.sessionMenu.powerOptions = [
              {
                action: "lock",
                enabled: true,
                keybind: "1",
                countdownEnabled: []
              }
            ];
      } catch (error) {
        rejected++;
      }
      try {
        cfg.bar.screenOverrides = [
              {
                name: "inert-screen",
                enabled: []
              }
            ];
      } catch (error) {
        rejected++;
      }
      try {
        cfg.wallpaper.monitorDirectories = [
              {
                name: "inert-screen",
                directory: "inert-directory",
                wallpaper: []
              }
            ];
      } catch (error) {
        rejected++;
      }
      check(rejected === 5, "authored fields are validated declarations, not unknown-data preservation");
      verify();
      store.save(function (result) {
        try {
          check(result.status === "saved", "actual persistence receipt");
          verify();
          console.log("I4_RECORD_SCHEMA: SAVED_PASS");
          Qt.exit(0);
        } catch (error) {
          console.error(String(error));
          Qt.exit(2);
        }
      });
    } catch (error) {
      console.error(String(error));
      Qt.exit(2);
    }
  }
  ConfigStore {
    id: store
    schema: Main.SettingsSchema {}
    autoSave: false
    sources: [
      JsonFileSource {
        sourceId: "records"
        layerId: "user"
        path: Quickshell.env("I4_RECORD_SCHEMA_FILE")
        writable: true
        optional: true
      }
    ]
    onReadyChanged: if (ready)
                      Qt.callLater(root.begin)
    onSourceError: error => {
      console.error("I4_RECORD_SCHEMA_ASSERT: source", error.code);
      Qt.exit(2);
    }
  }
  Component.onCompleted: begin()
  Timer {
    interval: 15000
    running: true
    onTriggered: {
      console.error("I4_RECORD_SCHEMA_ASSERT: watchdog");
      Qt.exit(2);
    }
  }
}
