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
  property real leadingWidth: 26 * Style.uiScaleRatio
  property var widths: []
  readonly property real availableColumns: Math.max(0, width - Style.margin2M - leadingWidth - Style.marginM * 3)
  readonly property var boundaries: cellBounds.slice(0, 2).map(cell => cell.x + cell.width + columns.spacing / 2)
  readonly property var geometry: [nameSlot.x, sizeSlot.x, sizeSlot.width, modifiedSlot.x, modifiedSlot.width]
  readonly property var cellBounds: [nameSlot, sizeSlot, modifiedSlot].map(slot => ({
    x: columns.x + slot.x,
    width: slot.width
  }))
  readonly property var leadingMetrics: leadingSlot.item ? leadingSlot.item.metrics : null
  readonly property var leadingThumbnailState: leadingSlot.item ? leadingSlot.item.thumbnailState : ({})
  implicitWidth: (leadingWidth + 80 * Style.uiScaleRatio + 92 * Style.uiScaleRatio + 164 * Style.uiScaleRatio + Style.marginM * 3) + Style.margin2M
  RowLayout {
    id: columns
    anchors.fill: parent
    anchors.margins: Style.marginM
    spacing: Style.marginM
    Loader {
      id: leadingSlot
      Layout.preferredWidth: root.leadingWidth
      Layout.minimumWidth: Layout.preferredWidth
      Layout.fillHeight: true
      sourceComponent: root.leading
    }
    Loader {
      id: nameSlot
      Layout.fillWidth: root.widths.length !== 3
      Layout.preferredWidth: root.widths.length === 3 ? root.widths[0] : 80 * Style.uiScaleRatio
      Layout.minimumWidth: 0
      Layout.fillHeight: true
      sourceComponent: root.nameCell
    }
    Loader {
      id: sizeSlot
      Layout.preferredWidth: root.widths.length === 3 ? root.widths[1] : 92 * Style.uiScaleRatio
      Layout.minimumWidth: Layout.preferredWidth
      Layout.fillHeight: true
      sourceComponent: root.sizeCell
    }
    Loader {
      id: modifiedSlot
      Layout.preferredWidth: root.widths.length === 3 ? root.widths[2] : 164 * Style.uiScaleRatio
      Layout.minimumWidth: Layout.preferredWidth
      Layout.fillHeight: true
      sourceComponent: root.modifiedCell
    }
  }
}
