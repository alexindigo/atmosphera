import QtQuick
import Quickshell

// A tile's subscription. Registration/cancellation belongs here rather than in
// a delegate's lifecycle handlers. The provider deduplicates shared paths.
Scope {
  id: root
  required property FileThumbnails provider
  property string path: ""
  property bool active: false
  property real pixels: 128
  property string stamp: ""
  readonly property string url: active ? (provider.urls[path] || "") : ""
  property int _token: 0
  function _sync() {
    if (_token)
      provider.update(_token, active ? path : "", Math.ceil(pixels), stamp);
  }
  Timer {
    id: flush
    interval: 0
    onTriggered: root._sync()
  }
  onPathChanged: flush.restart()
  onActiveChanged: flush.restart()
  onPixelsChanged: flush.restart()
  onStampChanged: flush.restart()
  Component.onCompleted: {
    _token = provider.acquire();
    _sync();
  }
  Component.onDestruction: provider.release(_token)
}
