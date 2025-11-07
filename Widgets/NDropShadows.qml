import QtQuick
import QtQuick.Effects
import qs.Commons

// Unified shadow system
Item {
  id: root
  required property var source

  layer.enabled: Settings.data.general.enableShadows
  layer.effect: MultiEffect {
    source: root.source
    shadowEnabled: true
    blurMax: Style.shadowBlurMax
    shadowBlur: Style.shadowBlur
    shadowOpacity: Style.shadowOpacity
    shadowColor: Color.black
    shadowHorizontalOffset: Settings.data.general.shadowOffsetX
    shadowVerticalOffset: Settings.data.general.shadowOffsetY
  }
}
