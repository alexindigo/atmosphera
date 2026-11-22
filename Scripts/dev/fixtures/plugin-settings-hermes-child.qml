import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
  id: root
  readonly property string base: Quickshell.env("PHA_HERMES_CHILD_CASE")
  property var main: null
  property string phase: "begin"
  property double since: Date.now()
  onPhaseChanged: since = Date.now()

  FileView {
    id: child
    path: root.base + "/child.json"
    printErrors: false
  }

  QtObject {
    id: api
    property var pluginSettings: ({
                                    stateFile: root.base + "/state/state.json",
                                    hermesHome: root.base + "/hermes-home",
                                    hermesCommand: root.base + "/hermes-cli",
                                    autoStartBridge: true,
                                    autoStartGateway: false,
                                    clientOnlyMode: false,
                                    configured: true,
                                    panelPinned: false,
                                    statusPollIntervalSec: 3600
                                  })
    property var manifest: ({
                              metadata: {
                                defaultSettings: {
                                  bridgePort: Number(Quickshell.env("PHA_HERMES_CHILD_PORT"))
                                }
                              }
                            })
    property string pluginDir: Quickshell.env("PHA_HERMES_CHILD_PLUGIN")
    property var mainInstance: null
    property var panelOpenScreen: null
    function tr(key) {
      return key;
    }
    function saveSettings() {
      throw new Error("child lifetime must not publish preferences");
    }
  }

  Item {
    id: content
  }

  function check(ok, message) {
    if (!ok)
      throw new Error("HERMES_CHILD_ASSERT: " + phase + ": " + message);
  }

  function begin() {
    const component = Qt.createComponent("file://" + api.pluginDir + "/Main.qml");
    check(component.status === Component.Ready, component.errorString());
    main = component.createObject(content, {
                                    pluginApi: api
                                  });
    check(main, "actual Main");
    api.mainInstance = main;
    phase = "online";
  }

  function drive() {
    check(Date.now() - since < 18000, "finite phase");
    if (phase === "online" && main.bridgeToken.length > 0 && main.state.bridge.status === "online") {
      main.oneShot("inert-held-oneshot");
      phase = "child";
    } else if (phase === "child") {
      child.reload();
      child.waitForJob();
      if (!child.loaded || !child.text().trim())
        return;
      const record = JSON.parse(child.text());
      check(record.argv.length === 2 && record.argv[0] === "-z" && record.argv[1] === "inert-held-oneshot", "actual helper child argv");
      console.log("HERMES_CHILD_BEFORE " + JSON.stringify(record));
      main.destroy();
      main = null;
      api.mainInstance = null;
      phase = "retired";
    } else if (phase === "retired" && Date.now() - since > 500) {
      driver.stop();
      console.log("HERMES_MAIN_DESTROYED: PASS");
      Qt.exit(0);
    }
  }

  Timer {
    id: driver
    interval: 40
    running: true
    repeat: true
    onTriggered: {
      try {
        root.drive();
      } catch (error) {
        driver.stop();
        console.error(String(error));
        Qt.exit(2);
      }
    }
  }

  Component.onCompleted: {
    try {
      begin();
    } catch (error) {
      console.error(String(error));
      Qt.exit(2);
    }
  }
}
