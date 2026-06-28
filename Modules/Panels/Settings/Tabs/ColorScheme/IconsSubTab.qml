import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Services.UI
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  Layout.fillWidth: true

  property string query: ""
  property var allIcons: Object.keys(Icons.icons)
  property var filteredIcons: {
    if (query === "")
      return allIcons;
    var q = query.toLowerCase();
    return allIcons.filter(function (name) {
      return name.toLowerCase().includes(q);
    });
  }

  readonly property int columns: 8
  readonly property int cellW: Math.floor(grid.width / columns)
  readonly property int cellH: Math.round(cellW * 0.6 + 32 * Style.uiScaleRatio)

  NHeader {
    label: I18n.tr("panels.icons.title")
    description: I18n.tr("panels.icons.description")
    Layout.fillWidth: true
  }

  NBox {
    visible: IconRegistry.activeOrder.length > 0
    Layout.fillWidth: true

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.marginM
      spacing: Style.marginS

      NText {
        text: "Icon Sets (" + IconRegistry.activeOrder.length + " active)"
        pointSize: Style.fontSizeS
        font.weight: Style.fontWeightBold
        color: Color.mOnSurface
      }

      Repeater {
        model: IconRegistry.activeOrder
        delegate: RowLayout {
          Layout.fillWidth: true
          spacing: Style.marginS

          NIcon {
            icon: Icon.palette
            pointSize: Style.fontSizeM
          }

          NText {
            text: modelData
            pointSize: Style.fontSizeS
            color: Color.mOnSurface
            Layout.fillWidth: true
          }

          NText {
            text: (IconRegistry.iconSets[modelData] && IconRegistry.iconSets[modelData].manifest && IconRegistry.iconSets[modelData].manifest.icons) ? Object.keys(IconRegistry.iconSets[modelData].manifest.icons).length + " icons" : ""
            pointSize: Style.fontSizeXS
            color: Color.mOnSurfaceVariant
          }
        }
      }
    }
  }

  NTextInput {
    id: searchInput
    Layout.fillWidth: true
    label: I18n.tr("common.search")
    placeholderText: I18n.tr("placeholders.search-icons")
    text: root.query
    onTextChanged: root.query = text.trim().toLowerCase()
  }

  NText {
    text: I18n.tr("panels.icons.count", {
                    "count": root.filteredIcons.length,
                    "total": root.allIcons.length
                  })
    pointSize: Style.fontSizeXS
    color: Color.mOnSurfaceVariant
  }

  NGridView {
    id: grid
    Layout.fillWidth: true
    Layout.fillHeight: true
    Layout.margins: Style.marginM
    cellWidth: root.cellW
    cellHeight: root.cellH
    model: root.filteredIcons

    delegate: Rectangle {
      width: grid.cellWidth
      height: grid.cellHeight
      radius: Style.iRadiusS
      color: "transparent"

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: parent.color = Qt.alpha(Color.mHover, 0.08)
        onExited: parent.color = "transparent"
      }

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: Style.marginS
        spacing: Style.marginXS

        Item {
          Layout.preferredHeight: 4
        }

        NIcon {
          Layout.alignment: Qt.AlignHCenter
          Layout.preferredWidth: 32 * Style.uiScaleRatio
          Layout.preferredHeight: 32 * Style.uiScaleRatio
          icon: modelData
          pointSize: Style.fontSizeXXL
        }

        NText {
          Layout.alignment: Qt.AlignHCenter
          Layout.fillWidth: true
          elide: Text.ElideRight
          wrapMode: Text.NoWrap
          maximumLineCount: 1
          horizontalAlignment: Text.AlignHCenter
          color: Color.mOnSurfaceVariant
          pointSize: Style.fontSizeXXS
          text: modelData
        }

        Item {
          Layout.preferredHeight: 4
        }
      }
    }
  }
}
