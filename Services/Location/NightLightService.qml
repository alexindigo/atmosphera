pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI

Singleton {
  id: root

  // Night Light properties - directly bound to settings
  readonly property var params: Settings.data.nightLight
  property var lastCommand: []

  function apply() {
    // If using LocationService, wait for it to be ready
    if (!params.forced && params.autoSchedule && !LocationService.coordinatesReady) {
      return;
    }

    var command = buildCommand();

    // Compare with previous command to avoid unnecessary restart
    if (JSON.stringify(command) !== JSON.stringify(lastCommand)) {
      lastCommand = command;
      runner.command = command;
      // Set running to false so it may restart below if still enabled
      runner.running = false;
    }

    runner.running = params.enabled;
  }

  function parseTime(timeStr) {
    var parts = timeStr.split(':');
    return {
      hour: parseInt(parts[0]),
      minute: parseInt(parts[1])
    };
  }

  function timeToMinutes(timeObj) {
    return timeObj.hour * 60 + timeObj.minute;
  }

  function buildCommand() {
    var cmd = ["wlsunset"];

    if (params.forced) {
      // Force immediate full night temperature regardless of time
      // Keep distinct day/night temps but set times so we're effectively always in "night"
      cmd.push("-t", `${params.nightTemp}`, "-T", `${params.dayTemp}`);
      // Night spans from sunset (00:00) to sunrise (23:59) covering almost the full day
      cmd.push("-S", "23:59"); // sunrise very late
      cmd.push("-s", "00:00"); // sunset at midnight
      // Near-instant transition
      cmd.push("-d", 1);
    } else {
      cmd.push("-t", `${params.nightTemp}`, "-T", `${params.dayTemp}`);
      if (params.autoSchedule) {
        cmd.push("-l", `${LocationService.stableLatitude}`, "-L", `${LocationService.stableLongitude}`);
      } else {
        // Manual schedule - we need to handle the edge case at midnight
        var now = new Date();
        var currentMinutes = now.getHours() * 60 + now.getMinutes();

        var sunrise = parseTime(params.manualSunrise);
        var sunset = parseTime(params.manualSunset);
        var sunriseMinutes = timeToMinutes(sunrise);
        var sunsetMinutes = timeToMinutes(sunset);

        // Determine if we're currently in night period
        var inNightPeriod = false;
        if (sunsetMinutes < sunriseMinutes) {
          // Normal case: sunset before sunrise (e.g., 20:00 to 06:00)
          inNightPeriod = currentMinutes >= sunsetMinutes || currentMinutes < sunriseMinutes;
        } else {
          // Edge case: sunset after sunrise (e.g., 06:00 to 20:00 means night is inverted)
          inNightPeriod = currentMinutes >= sunsetMinutes && currentMinutes < sunriseMinutes;
        }

        // Always pass times as-is - wlsunset handles day transitions
        cmd.push("-S", params.manualSunrise);
        cmd.push("-s", params.manualSunset);
      }
      cmd.push("-d", 60 * 15); // 15min progressive fade at sunset/sunrise
    }

    return cmd;
  }

  // Timer to restart wlsunset at midnight (only for manual schedule)
  // This ensures it recalculates times for the new day without visible flicker
  Timer {
    id: midnightTimer
    running: false
    repeat: false

    function scheduleNextMidnight() {
      if (!params.enabled || params.autoSchedule || params.forced) {
        running = false;
        return;
      }

      var now = new Date();
      var midnight = new Date(now);
      midnight.setHours(24, 0, 1, 0); // Next midnight + 1 second

      var msUntilMidnight = midnight.getTime() - now.getTime();
      interval = msUntilMidnight;
      running = true;

      Logger.i("NightLight", "Scheduled midnight restart in", Math.floor(msUntilMidnight / 1000), "seconds");
    }

    onTriggered: {
      Logger.i("NightLight", "Midnight reached - restarting wlsunset");
      apply();
      scheduleNextMidnight();
    }
  }

  // Observe setting changes and location readiness
  Connections {
    target: Settings.data.nightLight
    function onEnabledChanged() {
      apply();
      midnightTimer.scheduleNextMidnight();
      // Toast: night light toggled
      const enabled = !!Settings.data.nightLight.enabled;
      ToastService.showNotice(I18n.tr("settings.display.night-light.section.label"), enabled ? I18n.tr("toast.night-light.enabled") : I18n.tr("toast.night-light.disabled"), enabled ? "nightlight-on" : "nightlight-off");
    }
    function onForcedChanged() {
      apply();
      midnightTimer.scheduleNextMidnight();
      if (Settings.data.nightLight.enabled) {
        ToastService.showNotice(I18n.tr("settings.display.night-light.section.label"), Settings.data.nightLight.forced ? I18n.tr("toast.night-light.forced") : I18n.tr("toast.night-light.normal"), Settings.data.nightLight.forced ? "nightlight-forced" : "nightlight-on");
      }
    }
    function onNightTempChanged() {
      apply();
    }
    function onDayTempChanged() {
      apply();
    }
    function onAutoScheduleChanged() {
      apply();
      midnightTimer.scheduleNextMidnight();
    }
    function onManualSunriseChanged() {
      apply();
    }
    function onManualSunsetChanged() {
      apply();
    }
  }

  Connections {
    target: LocationService
    function onCoordinatesReadyChanged() {
      if (LocationService.coordinatesReady) {
        apply();
      }
    }
  }

  Component.onCompleted: {
    midnightTimer.scheduleNextMidnight();
  }

  // Foreground process runner
  Process {
    id: runner
    running: false
    onStarted: {
      Logger.i("NightLight", "Wlsunset started:", runner.command);
    }
    onExited: function (code, status) {
      Logger.i("NightLight", "Wlsunset exited:", code, status);
    }
  }
}
