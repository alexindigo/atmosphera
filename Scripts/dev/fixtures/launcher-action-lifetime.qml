import QtQuick
import Quickshell
import "../../../Modules/Panels/Launcher/Providers"

ShellRoot {
  id: root
  property bool destroyed: false

  Loader {
    id: transient
    sourceComponent: Item {
      id: launcher
      function closeImmediately() {
        transient.active = false;
      }
      Component.onDestruction: {
        root.destroyed = true;
      }
      ApplicationsProvider {
        id: apps
        launcher: launcher
      }
      CommandProvider {
        id: commands
        launcher: launcher
      }
      function commit() {
        var command = Quickshell.env("LAUNCHER_ACTION_COMMAND");
        if (Quickshell.env("LAUNCHER_ACTION_KIND") === "application") {
          apps.createResultEntry({
                                   id: "lifetime-app",
                                   name: "Lifetime app",
                                   command: [Quickshell.env("LAUNCHER_ACTION_EXECUTABLE")],
                                   runInTerminal: false
                                 }).onActivate();
        } else {
          commands.getResults(">cmd " + command)[0].onActivate();
        }
      }
    }
  }
  Timer {
    interval: 300
    running: true
    onTriggered: transient.item.commit()
  }
  Timer {
    interval: 1000
    running: true
    onTriggered: {
      console.log("LAUNCHER_LIFETIME_DESTROYED|" + root.destroyed);
      Qt.exit(root.destroyed ? 0 : 1);
    }
  }
}
