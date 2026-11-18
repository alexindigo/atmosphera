import QtQml.Models
import QtQuick
import Quickshell

Item {
  id: root
  property var zones: []
  property bool active: false
  property bool includeInputRegions: true
  required property Item observationItem
  property real originX: 0
  property real originY: 0
  readonly property var inputRegions: _inputRegions
  property var _inputRegions: []
  property var _hoverZone: null

  signal zoneEntered(var zone, int buttons, var source)
  signal zoneLeft(string key, var source)
  signal buttonsChanged(int buttons)

  function clear() {
    if (_hoverZone)
      zoneLeft(_hoverZone.key, root);
    _hoverZone = null;
  }

  function observe(position, buttons) {
    var x = position.x + originX;
    var y = position.y + originY;
    var zone = zones.find(function (candidate) {
      var rect = candidate.rect;
      return x >= rect.x && x < rect.x + rect.width && y >= rect.y && y < rect.y + rect.height;
    }) || null;
    if (_hoverZone && _hoverZone.key !== zone?.key)
      clear();
    _hoverZone = zone;
    if (zone)
      // Qt synthesizes hover updates with cached (pre-press) button state.
      // The passive press observer is authoritative while its point is down.
      zoneEntered(zone, press.active ? 1 : buttons, root);
  }

  // Observe on the surface's ancestor, not a sibling behind bar widgets: a
  // MouseArea in a widget otherwise stops hover delivery to that sibling.
  HoverHandler {
    id: hover
    parent: root.observationItem
    enabled: root.active
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    blocking: false
    onHoveredChanged: {
      if (hovered)
        root.observe(point.position, point.pressedButtons);
      else
        root.clear();
    }
    onPointChanged: {
      if (hovered)
        root.observe(point.position, point.pressedButtons);
    }
  }

  // HoverHandler deliberately ignores press/release events in Qt. This passive
  // observer receives those too, without taking a widget's exclusive grab.
  PointHandler {
    id: press
    parent: root.observationItem
    enabled: root.active
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    acceptedButtons: Qt.AllButtons
    onActiveChanged: {
      root.buttonsChanged(active ? 1 : 0);
      if (!active && hover.hovered)
        root.observe(hover.point.position, 0);
    }
  }

  onZonesChanged: {
    // A neighbouring output or a dock can republish an equivalent list. Keep
    // the hold unless the actual active rectangle has changed/disappeared.
    if (_hoverZone && !zones.some(function (zone) {
      return zone.key === root._hoverZone.key;
    }))
      clear();
  }
  Component.onDestruction: clear()

  Instantiator {
    model: root.active && root.includeInputRegions ? root.zones : []
    delegate: Region {
      required property var modelData
      x: modelData.rect.x
      y: modelData.rect.y
      width: modelData.rect.width
      height: modelData.rect.height
      intersection: Intersection.Subtract
    }
    onObjectAdded: (index, object) => root._inputRegions = root._inputRegions.concat([object])
    onObjectRemoved: (index, object) => root._inputRegions = root._inputRegions.filter(function (region) {
      return region !== object;
    })
  }
}
