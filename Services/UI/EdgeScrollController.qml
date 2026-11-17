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
  property int holdMs: 600
  readonly property int repeatMs: Math.round(holdMs * 1.5)
  property var clock: function () {
    return Date.now();
  }
  property var actionSink: function (zone, requestId) {}
  property bool autoTick: true
  readonly property var activeZone: _leaving ? null : _zone
  readonly property real progress: _leaving ? 0 : _progress
  readonly property bool buttonDown: _buttonDown
  property var _zone: null
  property real _progress: 0
  property bool _buttonDown: false
  property real _startedAt: 0
  property real _deadline: 0
  property real _phaseMs: holdMs
  property int _nextRequestId: 0
  property int _pendingRequestId: 0
  property var _source: null
  property bool _leaving: false

  signal navigationFinished(var zone, string outcome)

  onEnabledChanged: {
    if (!enabled)
      cancel();
  }
  onHoldMsChanged: cancel()

  function cancel() {
    _zone = null;
    _progress = 0;
    _source = null;
    _leaving = false;
    _pendingRequestId = 0;
  }

  function buttonsChanged(buttons) {
    _buttonDown = buttons !== 0;
    if (_buttonDown)
      cancel();
  }

  function enter(zone, buttons, source) {
    buttonsChanged(buttons);
    if (!enabled || _buttonDown || !zone)
      return;
    if (_zone && _zone.key === zone.key && (!_leaving || (source && source !== _source))) {
      _source = source || null;
      _leaving = false;
      return;
    }
    cancel();
    _startedAt = clock();
    _phaseMs = holdMs + (zone.inner ? 200 : 0);
    _deadline = _startedAt + _phaseMs;
    _zone = zone;
    _source = source || null;
  }

  function leave(key, source) {
    if (_zone && _zone.key === key && (!source || source === _source)) {
      // Stop activity immediately, but retain timing for a replacement surface
      // entering this same zone before the next event-loop turn.
      _leaving = true;
      Qt.callLater(finishLeave);
    }
  }

  function finishLeave() {
    if (_leaving)
      cancel();
  }

  function tick() {
    if (!_zone || _leaving || !enabled || _buttonDown)
      return;
    var now = clock();
    if (now >= _deadline && !_pendingRequestId) {
      var zone = _zone;
      // No queued catch-up burst after a stalled GUI: each actual step starts
      // one new hold. There is never a free-running progress animation.
      _startedAt = now;
      _phaseMs = repeatMs;
      _deadline = now + _phaseMs;
      _progress = 0;
      _pendingRequestId = ++_nextRequestId;
      actionSink(zone, _pendingRequestId);
    } else {
      _progress = Math.min(1, Math.max(0, (now - _startedAt) / _phaseMs));
    }
  }

  function resolveNavigation(requestId, outcome) {
    if (!_pendingRequestId || requestId !== _pendingRequestId)
      return;
    _pendingRequestId = 0;
    if (activeZone)
      navigationFinished(activeZone, outcome);
  }

  Timer {
    interval: 16
    repeat: true
    running: root.autoTick && root.activeZone !== null
    onTriggered: root.tick()
  }
}
