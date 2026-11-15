pragma Singleton

import QtQuick
import Quickshell
import qs.Commons
import qs.Services.Compositor

Singleton {
  id: root

  readonly property bool enabled: controller.enabled
  readonly property var activeZone: controller.activeZone
  readonly property real progress: controller.progress

  signal stepped(var zone)

  EdgeScrollController {
    id: controller
    gates: ({
              setting: Settings.data.bar.edgeScrolling,
              niri: CompositorService.isNiri,
              framed: Settings.data.bar.barType === "framed",
              barVisible: BarService.isVisible,
              overview: CompositorService.overviewActive,
              hideOnOverview: Settings.data.bar.hideOnOverview
            })
    holdMs: Settings.data.bar.edgeScrollHoldMs
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
    onStepped: zone => root.stepped(zone)
  }

  function enter(zone, buttons) {
    controller.enter(zone, buttons);
  }
  function leave(key) {
    controller.leave(key);
  }
  function buttonsChanged(buttons) {
    controller.buttonsChanged(buttons);
  }
  function leaveScreen(name) {
    if (activeZone && activeZone.screenName === name)
      controller.cancel();
  }
}
