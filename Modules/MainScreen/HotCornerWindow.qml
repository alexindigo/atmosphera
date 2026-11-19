import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Services.UI

/**
* HotCornerWindow - one configured corner zone on an Overlay layer surface
*
* Only the Overlay layer receives the pointer above a fullscreen window, so the
* corner works there too. The zone geometry comes from ScreenZonesService.
*/
PanelWindow {
  id: root

  required property var zone

  color: "transparent"
  focusable: false
  exclusionMode: ExclusionMode.Ignore

  WlrLayershell.namespace: "atmosphera-hot-corner-" + root.zone.screenName + "-" + root.zone.corner
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  anchors {
    top: root.zone.corner === "topLeft" || root.zone.corner === "topRight"
    bottom: root.zone.corner === "bottomLeft" || root.zone.corner === "bottomRight"
    left: root.zone.corner === "topLeft" || root.zone.corner === "bottomLeft"
    right: root.zone.corner === "topRight" || root.zone.corner === "bottomRight"
  }

  implicitWidth: root.zone.rect.width
  implicitHeight: root.zone.rect.height

  mask: Region {
    item: root.contentItem
  }

  // No item here accepts presses: an accepting item would take the press
  // before the sensors' passive observer, so a press would not cancel a dwell.
  ScreenZoneSensors {
    observationItem: root.contentItem
    zones: [root.zone]
    active: true
    includeInputRegions: false
    originX: root.zone.rect.x
    originY: root.zone.rect.y
    onZoneEntered: (zone, buttons, source) => ScreenZonesService.enter(zone, buttons, source)
    onZoneLeft: (key, source) => ScreenZonesService.leave(key, source)
    onButtonsChanged: buttons => ScreenZonesService.buttonsChanged(buttons)
  }
}
