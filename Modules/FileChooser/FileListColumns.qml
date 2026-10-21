import QtQuick
import QtQuick.Layouts
import qs.Commons

// Headers and every row use this same column structure, including icon space.
Item {
  id: root
  property Component leading
  property Component nameCell
  property Component sizeCell
  property Component modifiedCell
  readonly property var geometry: [nameSlot.x, sizeSlot.x, sizeSlot.width, modifiedSlot.x, modifiedSlot.width]
  readonly property var leadingMetrics: leadingSlot.item ? leadingSlot.item.metrics : null
  implicitWidth: columns.Layout.minimumWidth + Style.margin2M
  RowLayout {
    id: columns
    anchors.fill: parent
    anchors.margins: Style.marginM
    spacing: Style.marginM
    Loader { id: leadingSlot; Layout.preferredWidth: 26 * Style.uiScaleRatio; Layout.minimumWidth: Layout.preferredWidth; Layout.fillHeight: true; sourceComponent: root.leading }
    Loader { id: nameSlot; Layout.fillWidth: true; Layout.fillHeight: true; sourceComponent: root.nameCell }
    Loader { id: sizeSlot; Layout.preferredWidth: 92 * Style.uiScaleRatio; Layout.minimumWidth: Layout.preferredWidth; Layout.fillHeight: true; sourceComponent: root.sizeCell }
    Loader { id: modifiedSlot; Layout.preferredWidth: 164 * Style.uiScaleRatio; Layout.minimumWidth: Layout.preferredWidth; Layout.fillHeight: true; sourceComponent: root.modifiedCell }
  }
}
