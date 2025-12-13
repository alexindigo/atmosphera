import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

RowLayout {
  id: root

  property real minimumWidth: 200 * Style.uiScaleRatio
  property real popupHeight: 180 * Style.uiScaleRatio

  property string label: ""
  property string description: ""
  property var model
  property string currentKey: ""
  property string placeholder: ""

  readonly property real preferredHeight: Style.baseWidgetSize * 1.1 * Style.uiScaleRatio
  readonly property var comboBox: combo

  signal selected(string key)

  spacing: Style.marginL
  Layout.fillWidth: true
  opacity: enabled ? 1.0 : 0.6

  function itemCount() {
    if (!root.model)
      return 0;
    if (typeof root.model.count === 'number')
      return root.model.count;
    if (Array.isArray(root.model))
      return root.model.length;
    return 0;
  }

  function getItem(index) {
    if (!root.model)
      return null;
    if (typeof root.model.get === 'function')
      return root.model.get(index);
    if (Array.isArray(root.model))
      return root.model[index];
    return null;
  }

  function findIndexByKey(key) {
    for (var i = 0; i < itemCount(); i++) {
      var item = getItem(i);
      if (item && item.key === key)
        return i;
    }
    return -1;
  }

  NLabel {
    label: root.label
    description: root.description
  }

  ComboBox {
    id: combo

    Layout.minimumWidth: root.minimumWidth
    Layout.preferredHeight: root.preferredHeight
    model: root.model
    currentIndex: root.findIndexByKey(root.currentKey)

    onActivated: {
      var item = root.getItem(combo.currentIndex);
      if (item && item.key !== undefined)
        root.selected(item.key);
    }

    background: Rectangle {
      implicitWidth: Style.baseWidgetSize * 3.75
      implicitHeight: root.preferredHeight
      color: Color.mSurface
      border.color: combo.activeFocus ? Color.mSecondary : Color.mOutline
      border.width: Style.borderS
      radius: Style.iRadiusM

      Behavior on border.color {
        ColorAnimation {
          duration: Style.animationFast
        }
      }
    }

    contentItem: NText {
      leftPadding: Style.marginL
      rightPadding: combo.indicator.width + Style.marginL
      pointSize: Style.fontSizeM
      verticalAlignment: Text.AlignVCenter
      elide: Text.ElideRight
      color: combo.currentIndex >= 0 ? Color.mOnSurface : Color.mOnSurfaceVariant
      text: {
        if (combo.currentIndex >= 0 && combo.currentIndex < root.itemCount()) {
          var item = root.getItem(combo.currentIndex);
          return item ? item.name : root.placeholder;
        }
        return root.placeholder;
      }
    }

    indicator: NIcon {
      x: combo.width - width - Style.marginM
      y: combo.topPadding + (combo.availableHeight - height) / 2
      icon: "caret-down"
      pointSize: Style.fontSizeL
    }

    popup: Popup {
      y: combo.height
      implicitWidth: combo.width - Style.marginM
      implicitHeight: Math.min(root.popupHeight, listView.contentHeight + Style.marginM * 2)
      padding: Style.marginM

      contentItem: ListView {
        id: listView
        property var comboBox: combo
        clip: true
        model: combo.popup.visible ? root.model : null
        boundsBehavior: Flickable.StopAtBounds
        highlightMoveDuration: 0

        ScrollBar.vertical: ScrollBar {
          policy: listView.contentHeight > listView.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

          contentItem: Rectangle {
            implicitWidth: 6
            implicitHeight: 100
            radius: Style.iRadiusM
            color: parent.pressed ? Qt.alpha(Color.mHover, 0.9) : parent.hovered ? Qt.alpha(Color.mHover, 0.9) : Qt.alpha(Color.mHover, 0.8)
            opacity: parent.active ? 1.0 : 0.0

            Behavior on opacity {
              NumberAnimation {
                duration: Style.animationFast
              }
            }

            Behavior on color {
              ColorAnimation {
                duration: Style.animationFast
              }
            }
          }

          background: Rectangle {
            implicitWidth: 6
            implicitHeight: 100
            color: Color.transparent
            opacity: parent.active ? 0.3 : 0.0
            radius: Style.iRadiusM / 2

            Behavior on opacity {
              NumberAnimation {
                duration: Style.animationFast
              }
            }
          }
        }

        delegate: Rectangle {
          id: delegateRect
          required property int index
          property bool isHighlighted: listView.currentIndex === index

          width: listView.width
          height: delegateText.implicitHeight + Style.marginS * 2
          radius: Style.iRadiusS
          color: isHighlighted ? Color.mHover : Color.transparent

          Behavior on color {
            ColorAnimation {
              duration: Style.animationFast
            }
          }

          NText {
            id: delegateText
            anchors.fill: parent
            anchors.leftMargin: Style.marginM
            anchors.rightMargin: Style.marginM
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            pointSize: Style.fontSizeM
            color: delegateRect.isHighlighted ? Color.mOnHover : Color.mOnSurface
            text: {
              var item = root.getItem(delegateRect.index);
              return item && item.name ? item.name : "";
            }

            Behavior on color {
              ColorAnimation {
                duration: Style.animationFast
              }
            }
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onContainsMouseChanged: {
              if (containsMouse)
                listView.currentIndex = delegateRect.index;
            }
            onClicked: {
              var item = root.getItem(delegateRect.index);
              if (item && item.key !== undefined) {
                root.selected(item.key);
                listView.comboBox.currentIndex = delegateRect.index;
                listView.comboBox.popup.close();
              }
            }
          }
        }
      }

      background: Rectangle {
        color: Color.mSurfaceVariant
        border.color: Color.mOutline
        border.width: Style.borderS
        radius: Style.iRadiusM
      }
    }

    Connections {
      target: root
      function onCurrentKeyChanged() {
        combo.currentIndex = root.findIndexByKey(root.currentKey);
      }
    }
  }
}
