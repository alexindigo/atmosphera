import QtQuick
import QtQuick.Layouts
import qs.Commons

ColumnLayout {
  id: root
  property var queueStatus: ({ "state": "Idle", "queueCount": 0, "error": "" })
  property var retry: null
  spacing: Style.marginS

  NText {
    Layout.fillWidth: true
    wrapMode: Text.WordWrap
    pointSize: Style.fontSizeS
    text: root.queueStatus.state === "WaitingStartup" ? "Waiting for startup"
          : root.queueStatus.state === "Stopped" ? "Stopped at " + root.queueStatus.headEnvironment + ": " + root.queueStatus.error
          : root.queueStatus.state === "Running" ? "Running " + root.queueStatus.headEnvironment + " · " + root.queueStatus.stage
          : "Saved/deployed requests complete; niri handoff accepted where applicable"
  }
  NText {
    Layout.fillWidth: true
    wrapMode: Text.WordWrap
    pointSize: Style.fontSizeS
    text: "Requested: " + (root.queueStatus.requestedEnvironment || "none") + " · waiting: " + (root.queueStatus.waitingCount || 0)
  }
  NButton {
    objectName: "bindingsQueueRetry"
    visible: root.queueStatus.state === "Stopped"
    text: "Retry retained head"
    onClicked: {
      if (typeof root.retry === "function") root.retry();
    }
  }
}
