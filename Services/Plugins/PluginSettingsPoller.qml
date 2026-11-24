import QtQuick

// A Main-owned scheduling client, not a second observation or preference owner.
Item {
  id: root
  required property var settingsContext
  required property int sourceInterval
  property int intervalScale: 1
  readonly property int interval: sourceInterval * intervalScale
  required property var requestRefresh
  required property var retire
  property bool pollingEnabled: true
  property bool requirePositiveInterval: false
  readonly property bool current: settingsContext.current()
  readonly property bool running: poll.running
  property bool _constructed: false

  function refresh() {
    if (current)
      requestRefresh();
  }

  Timer {
    id: poll
    interval: root.interval
    running: root.current && root.pollingEnabled && (!root.requirePositiveInterval || interval > 0)
    repeat: true
    onTriggered: root.refresh()
  }
  onCurrentChanged: {
    if (!current && _constructed) {
      poll.stop();
      retire(root);
    }
  }
  Component.onCompleted: _constructed = true
  Component.onDestruction: poll.stop()
}
