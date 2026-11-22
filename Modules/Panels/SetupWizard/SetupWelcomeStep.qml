import QtQuick
import QtQuick.Layouts
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
      color: AtmoColor.mPrimary
      opacity: 0.08
      scale: 1.3
    }

    // The brand glyph shipped in the shell's icon set
    AtmoIcon {
      anchors.centerIn: parent
      icon: Icon.atmosphera
      pointSize: 82
      applyUiScale: false
      color: AtmoColor.mPrimary

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
      color: AtmoColor.mOnSurface
      Layout.fillWidth: true
      horizontalAlignment: Text.AlignHCenter
    }

    NText {
      text: I18n.tr("setup.welcome-subtitle")
      pointSize: Style.fontSizeL
      color: AtmoColor.mOnSurfaceVariant
      Layout.fillWidth: true
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.topMargin: Style.marginL
      Layout.preferredHeight: childrenRect.height + Style.margin2M
      color: AtmoColor.mSurfaceVariant
      radius: Style.radiusL

      NText {
        anchors.centerIn: parent
        width: parent.width - Style.margin2L
        text: I18n.tr("common.privacy-no-telemetry") + "\n" + I18n.tr("common.feedback-use-github")
        pointSize: Style.fontSizeM
        color: AtmoColor.mOnSurfaceVariant
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
      }
    }
  }
}
