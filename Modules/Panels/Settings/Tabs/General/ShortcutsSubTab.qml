import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  width: parent.width

  NLabel {
    label: I18n.tr("panels.general.shortcuts-title")
    description: I18n.tr("panels.general.shortcuts-description")
    Layout.fillWidth: true
  }

  Repeater {
    model: [
      {
        "value": "none",
        "label": I18n.tr("setup.bindings.none-label"),
        "description": I18n.tr("setup.bindings.none-description")
      },
      {
        "value": "macos",
        "label": I18n.tr("setup.bindings.macos-label"),
        "description": I18n.tr("setup.bindings.macos-description")
      }
    ]
    delegate: Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 72
      radius: Style.radiusL
      color: Settings.data.bindings.environment === modelData.value ? Color.mPrimaryContainer : Color.mSurfaceVariant
      border.color: Settings.data.bindings.environment === modelData.value ? Color.mPrimary : Color.mOutline
      border.width: Settings.data.bindings.environment === modelData.value ? 2 : 1

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          if (Settings.data.bindings.environment === modelData.value)
            return;
          Settings.data.bindings.environment = modelData.value;
          Settings.saveImmediate();
          Quickshell.execDetached(["atmosphera-bindings-apply"]);
        }
      }

      RowLayout {
        anchors.fill: parent
        anchors.margins: Style.marginL
        spacing: Style.marginM

        Rectangle {
          width: 20
          height: 20
          radius: width / 2
          color: "transparent"
          border.color: Settings.data.bindings.environment === modelData.value ? Color.mPrimary : Color.mOutline
          border.width: 2

          Rectangle {
            anchors.centerIn: parent
            width: 10
            height: 10
            radius: width / 2
            color: Color.mPrimary
            visible: Settings.data.bindings.environment === modelData.value
          }
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.marginXS

          NText {
            text: modelData.label
            pointSize: Style.fontSizeM
            font.weight: Style.fontWeightBold
            color: Color.mPrimary
          }

          NText {
            text: modelData.description
            pointSize: Style.fontSizeS
            color: Color.mOnSurfaceVariant
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
          }
        }
      }
    }
  }
}
