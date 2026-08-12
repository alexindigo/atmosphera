import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginM

  // Header
  RowLayout {
    Layout.fillWidth: true
    Layout.bottomMargin: Style.marginL
    spacing: Style.marginM

    Rectangle {
      width: 40
      height: 40
      radius: Style.radiusL
      color: Color.mSurfaceVariant
      opacity: 0.6

      AtmoIcon {
        icon: Icon.keyboard
        pointSize: Style.fontSizeL
        color: Color.mPrimary
        anchors.centerIn: parent
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.marginXS

      NText {
        text: I18n.tr("setup.bindings.title") || "Keyboard shortcuts"
        pointSize: Style.fontSizeXL
        font.weight: Style.fontWeightBold
        color: Color.mPrimary
      }

      NText {
        text: I18n.tr("setup.bindings.subtitle") || "Choose a shortcut environment"
        pointSize: Style.fontSizeM
        color: Color.mOnSurfaceVariant
      }
    }
  }

  // Choices
  ColumnLayout {
    Layout.fillWidth: true
    Layout.fillHeight: true
    spacing: Style.marginM

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
        Layout.preferredHeight: 80
        radius: Style.radiusL
        color: Settings.data.bindings.environment === modelData.value ? (Color.mPrimaryContainer || "transparent") : (Color.mSurfaceVariant || "transparent")
        border.color: Settings.data.bindings.environment === modelData.value ? (Color.mPrimary || "transparent") : (Color.mOutline || "transparent")
        border.width: Settings.data.bindings.environment === modelData.value ? 2 : 1

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: Settings.data.bindings.environment = modelData.value
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

  Item {
    Layout.fillWidth: true
    Layout.fillHeight: true
  }
}
