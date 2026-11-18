pragma Singleton

import QtQuick
import Quickshell
import "../../Helpers/EdgeZones.js" as EdgeZones
import qs.Commons

// The only publisher of per-screen pointer zones. Sensors report zone events
// here; each event goes to the consumer that owns that zone kind. Consumers
// never reference this service.
Singleton {
  id: root

  readonly property var screens: Quickshell.screens.map(function (screen) {
    return {
      name: screen.name,
      x: screen.x,
      y: screen.y,
      width: screen.width,
      height: screen.height
    };
  })

  // Edge zones: framed bar monitors, only while edge scrolling is enabled.
  readonly property var edgeZones: {
    if (!EdgeScrollService.enabled)
      return {};
    var result = {};
    var monitors = Settings.data.bar.monitors;
    for (var screen of root.screens) {
      if (monitors.length === 0 || monitors.includes(screen.name))
        result[screen.name] = EdgeZones.zones(screen, root.screens, Settings.data.bar.frameThickness, Settings.getBarPositionForScreen(screen.name), Style.getBarHeightForScreen(screen.name), DockGeometryService.revealRect(screen.name));
    }
    return result;
  }

  onEdgeZonesChanged: {
    var active = EdgeScrollService.activeZone;
    if (active && !(edgeZones[active.screenName] || []).some(function (zone) {
      return zone.key === active.key;
    }))
      EdgeScrollService.cancel();
  }

  // Corner zones: configured corners on every output.
  readonly property var cornerZones: {
    var result = {};
    for (var screen of root.screens)
      result[screen.name] = EdgeZones.corners(screen, HotCornersService.configuredCorners);
    return result;
  }

  onCornerZonesChanged: {
    var active = HotCornersService.activeZone;
    if (active && !(cornerZones[active.screenName] || []).some(function (zone) {
      return zone.key === active.key;
    }))
      HotCornersService.cancel();
  }

  function edgeZonesForScreen(name) {
    return edgeZones[name] || [];
  }
  function cornerZonesForScreen(name) {
    return cornerZones[name] || [];
  }

  function enter(zone, buttons, source) {
    if (!zone)
      return;
    if (zone.kind === "corner")
      HotCornersService.enter(zone, buttons, source);
    else if (zone.kind === "edge")
      EdgeScrollService.enter(zone, buttons, source);
  }
  function leave(key, source) {
    if (HotCornersService.activeZone && HotCornersService.activeZone.key === key)
      HotCornersService.leave(key, source);
    else
      EdgeScrollService.leave(key, source);
  }
  function buttonsChanged(buttons) {
    EdgeScrollService.buttonsChanged(buttons);
    HotCornersService.buttonsChanged(buttons);
  }
  function leaveScreen(name) {
    EdgeScrollService.leaveScreen(name);
    HotCornersService.leaveScreen(name);
  }
}
