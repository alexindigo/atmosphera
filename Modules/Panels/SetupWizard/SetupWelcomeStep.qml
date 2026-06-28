import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root

  anchors.centerIn: parent
  width: Math.round(Math.max(parent.width * 0.5, 420))
  spacing: Style.marginXL

  // Logo with subtle glow effect
  Item {
    Layout.fillWidth: true
    Layout.preferredHeight: 120
    Layout.alignment: Qt.AlignHCenter

    Rectangle {
      anchors.centerIn: parent
      width: 120
      height: 120
      radius: width / 2
      color: Color.mPrimary
      opacity: 0.08
      scale: 1.3
    }

    Image {
      anchors.centerIn: parent
      width: 110
      height: 110
      source: Qt.resolvedUrl(Quickshell.shellDir + "/Assets/atmosphera.svg")
      fillMode: Image.PreserveAspectFit
      smooth: true

      Rectangle {
        anchors.fill: parent
        color: Color.mSurfaceVariant
        radius: width / 2
        border.color: Color.mOutline
        border.width: Style.borderM
        visible: parent.status === Image.Error

        NIcon {
          icon: Icon.featured
          pointSize: Style.fontSizeXXL * 1.5
          color: Color.mPrimary
          anchors.centerIn: parent
        }
      }

      SequentialAnimation on scale {
        running: true
        loops: Animation.Infinite
        NumberAnimation {
          from: 1.0
          to: 1.05
          duration: 2000
          easing.type: Easing.InOutQuad
        }
        NumberAnimation {
          from: 1.05
          to: 1.0
          duration: 2000
          easing.type: Easing.InOutQuad
        }
      }
    }
  }

  // Welcome text
  ColumnLayout {
    Layout.fillWidth: true
    Layout.alignment: Qt.AlignHCenter
    spacing: Style.marginM

    NText {
      text: I18n.tr("setup.welcome-title")
      pointSize: Style.fontSizeXXL * 1.4
      font.weight: Style.fontWeightBold
      color: Color.mOnSurface
      Layout.fillWidth: true
      horizontalAlignment: Text.AlignHCenter
    }

    NText {
      text: I18n.tr("setup.welcome-subtitle")
      pointSize: Style.fontSizeL
      color: Color.mOnSurfaceVariant
      Layout.fillWidth: true
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.topMargin: Style.marginL
      Layout.preferredHeight: childrenRect.height + Style.margin2M
      color: Color.mSurfaceVariant
      radius: Style.radiusL

      NText {
        anchors.centerIn: parent
        width: parent.width - Style.margin2L
        text: I18n.tr("common.privacy-no-telemetry") + "\n" + I18n.tr("common.feedback-use-github")
        pointSize: Style.fontSizeM
        color: Color.mOnSurfaceVariant
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
      }
    }
  }
}
