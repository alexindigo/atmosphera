import QtQuick

// Static backdrops keep their last presented texture while a replacement is
// decoded. Both slots are ordinary shared sources; only Ready can swap them.
Item {
  id: root
  property string source: ""
  property string sourceRevision: ""
  property bool active: true
  property bool normalize: true
  property int fillMode: Image.PreserveAspectCrop
  property size sourceSize: Qt.size(Math.max(1, Math.ceil(width * Screen.devicePixelRatio)), Math.max(1, Math.ceil(height * Screen.devicePixelRatio)))
  readonly property string imageState: _state
  readonly property int status: ({
                                   idle: Image.Null,
                                   loading: Image.Loading,
                                   ready: Image.Ready,
                                   unavailable: Image.Error
                                 })[_state]
  readonly property string errorReason: _error
  readonly property string displayedSource: _presentedSource
  readonly property string outputUrl: _front < 0 ? "" : (_front === 0 ? first.outputUrl : second.outputUrl)
  readonly property Item textureItem: _front < 0 ? null : (_front === 0 ? first.textureItem : second.textureItem)
  property int _front: -1
  property int _pending: -1
  property string _state: "idle"
  property string _error: ""
  property string _presentedSource: ""
  property bool _retry: false

  function _schedule() {
    _pending = -1;
    _state = active && source ? "loading" : "idle";
    begin.restart();
  }
  function retry() {
    _retry = true;
    _schedule();
  }
  function _begin() {
    _error = "";
    if (!active || !source) {
      _pending = _front = -1;
      _presentedSource = "";
      _state = "idle";
      first.active = second.active = false;
      first.source = second.source = "";
      return;
    }
    _pending = _front === 0 ? 1 : 0;
    _state = "loading";
    var image = _pending === 0 ? first : second;
    image.active = false;
    image.source = source;
    image.sourceRevision = sourceRevision;
    image.sourceSize = sourceSize;
    image.fillMode = fillMode;
    image.normalize = normalize;
    image.active = true;
    if (_retry)
      image.retry();
    _retry = false;
  }
  function _settle(index) {
    if (_pending !== index)
      return;
    var image = index === 0 ? first : second;
    if (image.status === Image.Ready) {
      _front = index;
      _presentedSource = image.source;
      _pending = -1;
      _state = "ready";
      var old = index === 0 ? second : first;
      old.active = false;
      old.source = "";
    } else if (image.status === Image.Error) {
      _error = image.errorReason;
      _pending = -1;
      _state = "unavailable";
    }
  }
  NImage {
    id: first
    anchors.fill: parent
    active: false
    opacity: root._front === 0 ? 1 : 0
    onStatusChanged: Qt.callLater(root._settle, 0)
  }
  NImage {
    id: second
    anchors.fill: parent
    active: false
    opacity: root._front === 1 ? 1 : 0
    onStatusChanged: Qt.callLater(root._settle, 1)
  }
  Timer {
    id: begin
    interval: 0
    onTriggered: root._begin()
  }
  onSourceChanged: _schedule()
  onSourceRevisionChanged: _schedule()
  onSourceSizeChanged: _schedule()
  onFillModeChanged: _schedule()
  onNormalizeChanged: _schedule()
  onActiveChanged: _schedule()
  Component.onCompleted: _schedule()
}
