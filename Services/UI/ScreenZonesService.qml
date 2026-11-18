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

  function edgeZonesForScreen(name) {
    return edgeZones[name] || [];
  }

  function enter(zone, buttons, source) {
    if (zone && zone.kind === "edge")
      EdgeScrollService.enter(zone, buttons, source);
  }
  function leave(key, source) {
    EdgeScrollService.leave(key, source);
  }
  function buttonsChanged(buttons) {
    EdgeScrollService.buttonsChanged(buttons);
  }
  function leaveScreen(name) {
    EdgeScrollService.leaveScreen(name);
  }
}
