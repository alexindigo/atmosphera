pragma Singleton

import QtQuick
import Quickshell
import qs.Commons
import qs.Services.Locker

// Hot corners: one command per corner, run with bash -c after a dwell. The
// controller owns timing; this service binds it to settings and the session.
Singleton {
  id: root

  readonly property var cornerNames: ["topLeft", "topRight", "bottomLeft", "bottomRight"]
  readonly property var commands: {
    if (!Settings.isLoaded)
      return {};
    var corners = Settings.data.general.hotCorners;
    return {
      topLeft: corners.topLeft,
      topRight: corners.topRight,
      bottomLeft: corners.bottomLeft,
      bottomRight: corners.bottomRight
    };
  }
  // Corners with a command; [] until settings are loaded.
  readonly property var configuredCorners: cornerNames.filter(function (corner) {
    return typeof root.commands[corner] === "string" && root.commands[corner] !== "";
  })
  readonly property int delayMs: Settings.isLoaded ? Settings.data.general.hotCorners.delayMs : 200
  readonly property bool unlocked: !(LockerService.locked || (PanelService.lockScreen && PanelService.lockScreen.active))
  readonly property var activeZone: controller.activeZone

  signal fired(string corner, string screenName)

  HotCornersController {
    id: controller
    gateOpen: root.unlocked
    delayMs: root.delayMs
    commands: root.commands
    runSink: function (zone, command) {
      Logger.i("HotCorners", "run", zone.corner, zone.screenName);
      Quickshell.execDetached(["bash", "-c", command]);
      root.fired(zone.corner, zone.screenName);
    }
  }

  function enter(zone, buttons, source) {
    controller.enter(zone, buttons, source);
  }
  function leave(key, source) {
    controller.leave(key, source);
  }
  function buttonsChanged(buttons) {
    controller.buttonsChanged(buttons);
  }
  function leaveScreen(name) {
    controller.leaveScreen(name);
  }
  function cancel() {
    controller.cancel();
  }
}
