import QtQuick

// Dwell owner for hot corners. No settings, process or view dependencies: the
// service injects the gate, delay, commands and run sink; tests use this same
// controller with a fake clock.
Item {
  id: root

  property bool gateOpen: false
  property int delayMs: 200
  // Corner name -> command string; "" means the corner does nothing.
  property var commands: ({})
  property var clock: function () {
    return Date.now();
  }
  property var runSink: function (zone, command) {}
  property bool autoTick: true

  // The corner the pointer is in, while dwelling or after it fired.
  readonly property var activeZone: _leaving ? null : _zone
  readonly property bool dwelling: activeZone !== null && !_disarmed
  property var _zone: null
  property var _sources: []
  property bool _disarmed: false
  property bool _leaving: false
  property var _leftSource: null
  property real _deadline: 0
  property string _command: ""

  onGateOpenChanged: {
    if (!gateOpen)
      cancel();
  }
  onDelayMsChanged: cancel()
  onCommandsChanged: {
    if (_zone && commandFor(_zone) !== _command)
      cancel();
  }

  function commandFor(zone) {
    var command = zone ? commands[zone.corner] : "";
    return typeof command === "string" ? command : "";
  }

  // Forget the corner entirely; the next enter starts a fresh dwell.
  function cancel() {
    _zone = null;
    _sources = [];
    _disarmed = false;
    _leaving = false;
    _leftSource = null;
    _deadline = 0;
    _command = "";
  }

  // Stop the dwell but keep the corner disarmed until the pointer leaves it.
  function disarm() {
    _disarmed = true;
    _deadline = 0;
  }

  function buttonsChanged(buttons) {
    if (buttons !== 0 && _zone)
      disarm();
  }

  function enter(zone, buttons, source) {
    if (!zone)
      return;
    var key = source || null;
    // Same corner from another (replacement) surface: keep the dwell or the
    // disarmed state. The surface that just left re-entering is a new visit.
    if (_zone && _zone.key === zone.key && !(_leaving && key === _leftSource)) {
      _leaving = false;
      _leftSource = null;
      if (_sources.indexOf(key) < 0)
        _sources = _sources.concat([key]);
      if (buttons !== 0)
        disarm();
      return;
    }
    cancel();
    if (!gateOpen)
      return;
    _zone = zone;
    _sources = [key];
    _command = commandFor(zone);
    if (buttons !== 0) {
      // Entered with a button held: the press belongs to a drag, not a dwell.
      disarm();
      return;
    }
    _deadline = clock() + delayMs;
  }

  function leave(key, source) {
    if (!_zone || _zone.key !== key)
      return;
    var remaining = _sources.filter(function (candidate) {
      return candidate !== (source || null);
    });
    _sources = remaining;
    if (remaining.length > 0)
      return;
    // Re-arm only once no surface reports the corner. A replacement surface
    // entering the same corner before the next event-loop turn keeps the state.
    _leaving = true;
    _leftSource = source || null;
    Qt.callLater(finishLeave);
  }

  function finishLeave() {
    if (_leaving)
      cancel();
  }

  function leaveScreen(name) {
    if (_zone && _zone.screenName === name)
      cancel();
  }

  function tick() {
    if (!_zone || _leaving || _disarmed || !gateOpen || _deadline === 0)
      return;
    if (clock() < _deadline)
      return;
    var zone = _zone;
    var command = _command;
    disarm();
    if (command !== "")
      runSink(zone, command);
  }

  Timer {
    interval: 16
    repeat: true
    running: root.autoTick && root.dwelling
    onTriggered: root.tick()
  }
}
