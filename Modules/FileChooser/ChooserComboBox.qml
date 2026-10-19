import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Widgets

// NComboBox uses the shell's secondary focus color. Keep the chooser on one
// accent without reaching into that component's private background/delegates.
ComboBox {
  id: root
  property string currentKey: ""
  property string accessibleName: ""
  property real minimumWidth: 150
  readonly property real compactWidth: indicator.implicitWidth + Style.margin2L
  readonly property bool valueElided: valueLabel.truncated
  signal selected(string key)
  implicitWidth: Math.max(minimumWidth * Style.uiScaleRatio, contentItem.implicitWidth)
  implicitHeight: Style.baseWidgetSize * 1.1 * Style.uiScaleRatio
  // The custom label owns horizontal padding, including indicator clearance.
  // Do not also inherit the platform style's indicator padding on the Control.
  leftPadding: 0
  rightPadding: 0
  textRole: "name"
  currentIndex: model ? model.findIndex(item => item.key === currentKey) : -1
  Accessible.name: accessibleName
  onActivated: if (model && currentIndex >= 0)
                 selected(model[currentIndex].key)
  contentItem: NText {
    id: valueLabel
    elide: Text.ElideRight
    text: root.currentText
    leftPadding: Style.marginL
    rightPadding: indicator.width + Style.marginL
    pointSize: Style.fontSizeM
  }
  indicator: AtmoIcon {
    id: indicator
    anchors.right: parent.right
    anchors.rightMargin: Style.marginM
    anchors.verticalCenter: parent.verticalCenter
    icon: Icon.caretDown
    pointSize: Style.fontSizeM
  }
  background: Rectangle {
    color: AtmoColor.mSurface
    radius: Style.iRadiusS
    border.width: root.activeFocus ? Style.borderM : Style.borderS
    border.color: root.activeFocus ? AtmoColor.mPrimary : AtmoColor.mOutline
  }
  delegate: ItemDelegate {
    required property var modelData
    required property int index
    width: root.width - Style.margin2M
    highlighted: root.highlightedIndex === index
    contentItem: NText {
      text: modelData.name
      pointSize: Style.fontSizeM
    }
    background: Rectangle {
      radius: Style.iRadiusXS
      color: parent.highlighted ? Qt.alpha(AtmoColor.mPrimary, 0.18) : "transparent"
    }
  }
  popup: Popup {
    y: root.height
    width: root.width
    padding: Style.marginM
    implicitHeight: Math.min(menu.contentHeight, 240 * Style.uiScaleRatio) + Style.margin2M
    contentItem: ListView {
      id: menu
      clip: true
      implicitHeight: contentHeight
      model: root.popup.visible ? root.delegateModel : null
      currentIndex: root.highlightedIndex
      ScrollIndicator.vertical: ScrollIndicator {}
    }
    background: Rectangle {
      color: AtmoColor.mSurfaceVariant
      radius: Style.iRadiusS
      border.color: AtmoColor.mOutline
      border.width: Style.borderS
    }
  }
}
