import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
  id: root
  readonly property string base: Quickshell.env("PHA_STEAM_CASE")
  property var main: null
  property string phase: "start"
  property double since: Date.now()
  onPhaseChanged: since = Date.now()
  QtObject {
    id: context
    property bool alive: true
    property var settingsView: ({
                                  gapSize: 30,
                                  friendsWidthPercent: 15,
                                  mainWidthPercent: 50,
                                  chatWidthPercent: 20,
                                  topMarginPercent: 4,
                                  windowHeightPercent: 80
                                })
    function current() {
      return alive;
    }
  }
  QtObject {
    id: api
    property var pluginSettings: ({
                                    gapSize: 10
                                  })
    property var settingsContext: context
    property var manifest: ({
                              metadata: {
                                defaultSettings: {}
                              }
                            })
  }
  Item {
    id: content
  }
  Process {
    id: release
  }
  Timer {
    id: driver
    interval: 40
    running: true
    repeat: true
    onTriggered: {
      try {
        if (Date.now() - root.since > 10000)
          throw new Error("finite startup admission");
        if (root.phase === "start") {
          const component = Qt.createComponent("file://" + root.base + "/config/plugins/hyprland-steam-overlay/Main.qml");
          if (component.status !== Component.Ready)
            throw new Error(component.errorString());
          root.main = component.createObject(content, {
                                               pluginApi: api
                                             });
          root.phase = "ready";
        } else if (root.phase === "ready" && root.main.steamRunning) {
          if (root.main.luaModeProbed || root.main.screenWidth !== 3440)
            throw new Error("startup probes were not held");
          root.main.toggleOverlay(context);
          context.settingsView = {
            gapSize: 0,
            useCustomLayout: true
          };
          if (Quickshell.env("PHA_STEAM_RETIRE") === "1")
            context.alive = false;
          release.command = ["touch", root.base + "/release-probes"];
          release.running = true;
          root.phase = "opening";
        } else if (root.phase === "opening" && (root.main.overlayActive || Quickshell.env("PHA_STEAM_RETIRE") === "1") && Date.now() - root.since > 1500) {
          if (Quickshell.env("PHA_STEAM_RETIRE") !== "1") {
            if (!root.main.toggleOverlay(context))
              throw new Error("current closing request refused");
            root.phase = "closing";
          } else {
            root.main.destroy();
            root.main = null;
            root.phase = "joined";
          }
        } else if (root.phase === "closing" && !root.main.overlayActive) {
          root.main.destroy();
          root.main = null;
          root.phase = "joined";
        } else if (root.phase === "joined" && Date.now() - root.since > 400) {
          driver.stop();
          console.log("STEAM_STARTUP: PASS");
          Qt.exit(0);
        }
      } catch (error) {
        driver.stop();
        console.error(String(error));
        Qt.exit(2);
      }
    }
  }
}
