pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.UPower
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
  property bool wallFeedback: false
  property int _pulseFrames: 0

  signal stepped(var zone)
  signal navigationFinished(var zone, string outcome)

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
    holdMs: Settings.isLoaded ? Settings.data.bar.edgeScrollHoldMs : 600
    actionSink: function (zone, requestId) {
      var backend = CompositorService.niriBackend;
      if (!backend) {
        controller.resolveNavigation(requestId, "unknown");
        root.navigationFinished(zone, "unknown");
        return;
      }
      backend.navigateEdge(zone.screenName, zone.edge, requestId, function (result) {
        controller.resolveNavigation(result.requestId, result.outcome);
        // Outcomes remain observable even if niri's monitor-focus pointer warp
        // ended the hold. Only the still-correlated active hold gets feedback.
        root.navigationFinished(zone, result.outcome);
      });
    }
    onActiveZoneChanged: {
      if (activeZone)
        root.glowZone = activeZone;
      else {
        root.stepPulse = false;
        root._pulseFrames = 0;
        root.wallFeedback = false;
        pulseTimer.stop();
        wallTimer.stop();
      }
    }
    onNavigationFinished: (zone, outcome) => {
      if (outcome === "moved") {
        if (root.reducedMotion)
          root._pulseFrames = 1;
        else {
          root.stepPulse = true;
          pulseTimer.restart();
        }
        root.stepped(zone);
      } else if (outcome === "boundary") {
        root.wallFeedback = true;
        wallTimer.restart();
      }
    }
  }

  Timer {
    id: wallTimer
    interval: 160
    onTriggered: root.wallFeedback = false
  }

  Timer {
    id: pulseTimer
    interval: 75
    onTriggered: root.stepPulse = false
  }

  FrameAnimation {
    running: root.activeZone !== null && root.reducedMotion
    onTriggered: {
      // Publish on frame boundaries, independent of whether the asynchronous
      // compositor reply arrived before or after this frame's callbacks.
      root.stepPulse = root._pulseFrames > 0;
      root._pulseFrames = Math.max(0, root._pulseFrames - 1);
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
  function cancel() {
    controller.cancel();
  }
  function leaveScreen(name) {
    if (activeZone && activeZone.screenName === name)
      controller.cancel();
  }
}
