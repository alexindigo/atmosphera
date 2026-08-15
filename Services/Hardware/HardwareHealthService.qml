pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.System
import qs.Services.UI

// HardwareHealthService — visibility + early warning layer over
// SystemStatService's hwmon inventory.
//
// - Thermal early-warning: per-sensor crit-derived thresholds (warn at
//   crit - warnOffsetC, sustained polls, hysteresis re-arm, rate-limited,
//   per-sensor "mute 1h" action). THERMTRIP gives no second chance; the
//   warning is the only userspace lever. The shell warns — it never acts.
// - Shell-owned thermal history: fsync'd 30s line log at
//   ~/.cache/atmosphera/thermal-history.log (user-space, no privileges),
//   self-trimming. Powers the long-range curve in the system stats panel.
// - Unclean-shutdown notice: reads /run/atmosphera/last-shutdown-unclean
//   (machine-side marker contract) at session start and toasts once.
Singleton {
  id: root

  // Per-sensor warning state: { id: { strikes, active, mutedUntil, lastWarnedAt } }
  property var _warnState: ({})
  property bool _uncleanNotified: false

  readonly property int hysteresisC: 10
  readonly property int rateLimitMs: 600000 // 10 min per sensor
  readonly property int muteDurationMs: 3600000 // 1 h

  function init() {
    Logger.i("HardwareHealth", "Service started");
  }

  // -------------------------------------------------------
  // Thermal early-warning

  Connections {
    target: SystemStatService
    function onSensorsChanged() {
      root._evaluate();
    }
  }

  function _evaluate() {
    if (!Settings.data.hardwareHealth.thermalWarnings) {
      return;
    }
    var now = Date.now();
    var offset = Settings.data.hardwareHealth.warnOffsetC;
    var need = Settings.data.hardwareHealth.sustainedPolls;
    var sensors = SystemStatService.sensors;
    var state = root._warnState;
    var newState = {};
    for (var i = 0; i < sensors.length; i++) {
      var s = sensors[i];
      if (s.crit <= 0 || s.temp <= 0) {
        continue;
      }
      var threshold = s.crit - offset;
      var prev = state[s.id] || {
        "strikes": 0,
        "active": false,
        "mutedUntil": 0,
        "lastWarnedAt": 0
      };
      var entry = Object.assign({}, prev);
      if (s.temp >= threshold) {
        entry.strikes = prev.strikes + 1;
        if (!prev.active && entry.strikes >= need && now >= prev.mutedUntil && now - prev.lastWarnedAt >= rateLimitMs) {
          entry.active = true;
          entry.lastWarnedAt = now;
          root._warn(s, threshold);
        }
      } else if (s.temp < threshold - hysteresisC) {
        entry.strikes = 0;
        entry.active = false;
      } else {
        // Below threshold but inside the hysteresis band — keep `active`,
        // reset strikes so re-crossing needs a fresh sustained run.
        entry.strikes = 0;
      }
      newState[s.id] = entry;
    }
    root._warnState = newState;
  }

  function _warn(sensor, threshold) {
    var label = sensor.label || sensor.chip;
    Logger.w("HardwareHealth", "Thermal warning:", label, sensor.temp + "°C", "(crit", sensor.crit + "°C)");
    ToastService.showWarning(I18n.tr("toast.hardware.thermal-title"), I18n.tr("toast.hardware.thermal-warning", {
                                                                                  "sensor": label,
                                                                                  "temp": sensor.temp,
                                                                                  "crit": sensor.crit
                                                                                }), 8000, I18n.tr("toast.hardware.mute-1h"), function () {
      root._mute(sensor.id);
    });
  }

  function _mute(sensorId) {
    var state = Object.assign({}, root._warnState);
    var entry = Object.assign({}, state[sensorId] || {});
    entry.mutedUntil = Date.now() + muteDurationMs;
    state[sensorId] = entry;
    root._warnState = state;
  }

  // -------------------------------------------------------
  // Shell-owned thermal history log (fsync'd, self-trimming)

  readonly property string _logPath: Settings.cacheDir + "thermal-history.log"

  Process {
    id: logShell
    command: ["sh"]
    stdinEnabled: true
    running: false

    onRunningChanged: {
      if (running) {
        // Write the read-loop program: append each stdin line, fsync,
        // self-trim to ~4 MB every 100 lines.
        logShell.write('f="' + root._logPath + '"; n=0\n' + 'while IFS= read -r line; do\n' + '  printf \'%s\\n\' "$line" >> "$f"\n' + '  sync -f "$f" 2>/dev/null || sync\n' + '  n=$((n+1)); if [ $((n % 100)) -eq 0 ]; then\n' + '    sz=$(stat -c %s "$f" 2>/dev/null || echo 0)\n' + '    [ "$sz" -gt 5242880 ] && { tail -c 4194304 "$f" > "$f.tmp" && mv "$f.tmp" "$f"; }\n' + '  fi\n' + 'done\n');
      }
    }
  }

  Timer {
    id: historyTimer
    interval: 30000
    repeat: true
    running: false
    onTriggered: root._writeHistoryLine()
  }

  Connections {
    target: Settings.data.hardwareHealth
    function onEnableHistoryLogChanged() {
      root._syncLogger();
    }
  }

  Connections {
    target: SystemStatService
    function onSensorsChanged() {
      root._syncLogger();
    }
  }

  function _syncLogger() {
    var want = Settings.data.hardwareHealth.enableHistoryLog && SystemStatService.sensors.length > 0;
    if (want && !logShell.running) {
      logShell.running = true;
    } else if (!want && logShell.running) {
      logShell.running = false;
    }
    historyTimer.running = want;
  }

  function _writeHistoryLine() {
    if (!logShell.running) {
      return;
    }
    var pkg = SystemStatService.cpuTemp;
    var hottest = SystemStatService.hottestCoreTemp || pkg;
    var fan = SystemStatService.fanRpm;
    var load = SystemStatService.loadAvg1;
    var bat = BatteryService.batteryReady ? Math.round(BatteryService.batteryPercentage) : "";
    var ac = BatteryService.batteryReady ? (BatteryService.batteryPluggedIn ? 1 : 0) : "";
    var line = new Date().toISOString() + " pkg=" + pkg + " hottest=" + hottest + " fan=" + fan + " load=" + load + " ac=" + ac + " bat=" + bat;
    logShell.write(line + "\n");
  }

  // -------------------------------------------------------
  // Unclean-shutdown notice (marker written by the machine-side
  // systemd pair; absent file = clean or unsupported, stay silent)

  FileView {
    id: uncleanMarker
    path: "/run/atmosphera/last-shutdown-unclean"
    printErrors: false
    onLoaded: {
      if (!root._uncleanNotified && Settings.data.hardwareHealth.uncleanShutdownNotice) {
        root._uncleanNotified = true;
        Logger.w("HardwareHealth", "Previous shutdown was not clean");
        ToastService.showWarning(I18n.tr("toast.hardware.unclean-shutdown-title"), I18n.tr("toast.hardware.unclean-shutdown"), 8000);
      }
    }
    onLoadFailed: {} // no marker — nothing to report
  }

  Component.onCompleted: {
    uncleanMarker.reload();
    root._syncLogger();
  }
}
