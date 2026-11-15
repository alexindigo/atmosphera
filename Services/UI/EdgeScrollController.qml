import QtQuick

// Timing owner. No settings, compositor or view dependencies: the service injects
// gates and the action sink; tests use this same controller with a fake clock.
Item {
  id: root

  property var gates: ({
                         setting: false,
                         niri: false,
                         framed: false,
                         barVisible: false,
                         overview: false,
                         hideOnOverview: false
                       })
  enabled: gates.setting && gates.niri && gates.framed && gates.barVisible && !(gates.overview && gates.hideOnOverview)
  property int holdMs: 400
  property var clock: function () {
    return Date.now();
  }
  property var actionSink: function (zone) {}
  property bool autoTick: true
  readonly property var activeZone: _zone
  readonly property real progress: _progress
  readonly property bool buttonDown: _buttonDown
  property var _zone: null
  property real _progress: 0
  property bool _buttonDown: false
  property real _startedAt: 0
  property real _deadline: 0

  signal stepped(var zone)

  onEnabledChanged: {
    if (!enabled)
      cancel();
  }
  onHoldMsChanged: cancel()

  function cancel() {
    _zone = null;
    _progress = 0;
  }

  function buttonsChanged(buttons) {
    _buttonDown = buttons !== 0;
    if (_buttonDown)
      cancel();
  }

  function enter(zone, buttons) {
    buttonsChanged(buttons);
    if (!enabled || _buttonDown || !zone)
      return;
    if (_zone && _zone.key === zone.key)
      return;
    cancel();
    _startedAt = clock();
    _deadline = _startedAt + holdMs + (zone.inner ? 200 : 0);
    _zone = zone;
  }

  function leave(key) {
    if (_zone && _zone.key === key)
      cancel();
  }

  function tick() {
    if (!_zone || !enabled || _buttonDown)
      return;
    var now = clock();
    if (now >= _deadline) {
      var zone = _zone;
      // No queued catch-up burst after a stalled GUI: each actual step starts
      // one new hold. There is never a free-running progress animation.
      _startedAt = now;
      _deadline = now + holdMs;
      _progress = 0;
      actionSink(zone);
      stepped(zone);
    } else {
      _progress = Math.min(1, Math.max(0, (now - _startedAt) / holdMs));
    }
  }

  Timer {
    interval: 16
    repeat: true
    running: root.autoTick && root.activeZone !== null
    onTriggered: root.tick()
  }
}
