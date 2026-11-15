pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.UPower
import "../../Helpers/EdgeZones.js" as EdgeZones
import qs.Commons
import qs.Services.Compositor
import qs.Services.Power

Singleton {
  id: root

  readonly property bool enabled: controller.enabled
  readonly property var activeZone: controller.activeZone
  readonly property real progress: controller.progress
  readonly property bool reducedMotion: (Settings.isLoaded && Settings.data.general.animationDisabled) || PowerProfileService.atmospheraPerformanceMode || PowerProfileService.profile === PowerProfile.PowerSaver
  property var glowZone: null
  property bool stepPulse: false
  property int _pulseFrames: 0

  readonly property var screenZones: {
    if (!root.enabled)
      return {};
    var all = Quickshell.screens.map(function (screen) {
      return {
        name: screen.name,
        x: screen.x,
        y: screen.y,
        width: screen.width,
        height: screen.height
      };
    });
    var result = {};
    for (var screen of all) {
      var monitors = Settings.data.bar.monitors;
      if (root.enabled && (monitors.length === 0 || monitors.includes(screen.name))) {
        result[screen.name] = EdgeZones.zones(screen, all, Settings.data.bar.frameThickness, Settings.getBarPositionForScreen(screen.name), Style.getBarHeightForScreen(screen.name), DockGeometryService.revealRect(screen.name));
      }
    }
    return result;
  }

  signal stepped(var zone)

  onScreenZonesChanged: {
    if (activeZone && !(screenZones[activeZone.screenName] || []).some(function (zone) {
      return zone.key === root.activeZone.key;
    }))
      controller.cancel();
  }

  EdgeScrollController {
    id: controller
    gates: ({
              setting: Settings.isLoaded && Settings.data.bar.edgeScrolling === true,
              niri: CompositorService.isNiri,
              framed: Settings.data.bar.barType === "framed",
              barVisible: BarService.isVisible,
              overview: CompositorService.overviewActive,
              hideOnOverview: Settings.data.bar.hideOnOverview
            })
    holdMs: Settings.isLoaded ? Settings.data.bar.edgeScrollHoldMs : 400
    actionSink: function (zone) {
      var backend = CompositorService.niriBackend;
      if (!backend)
        return;
      if (zone.edge === "left")
        backend.focusColumnLeft(zone.screenName);
      else if (zone.edge === "right")
        backend.focusColumnRight(zone.screenName);
      else if (zone.edge === "top")
        backend.focusWorkspaceUp(zone.screenName);
      else if (zone.edge === "bottom")
        backend.focusWorkspaceDown(zone.screenName);
    }
    onActiveZoneChanged: {
      if (activeZone)
        root.glowZone = activeZone;
      else {
        root.stepPulse = false;
        pulseTimer.stop();
      }
    }
    onStepped: zone => {
      root.stepPulse = true;
      if (root.reducedMotion)
        root._pulseFrames = 1;
      else
        pulseTimer.restart();
      root.stepped(zone);
    }
  }

  Timer {
    id: pulseTimer
    interval: 75
    onTriggered: root.stepPulse = false
  }

  FrameAnimation {
    running: root.stepPulse && root.reducedMotion
    onTriggered: {
      if (--root._pulseFrames <= 0)
        root.stepPulse = false;
    }
  }

  function zonesForScreen(name) {
    return screenZones[name] || [];
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
    if (activeZone && activeZone.screenName === name)
      controller.cancel();
  }
}
