import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import qs.Commons
import qs.Services
import qs.Widgets

// Notification History panel
NPanel {
  id: root

  panelWidth: 380 * scaling
  panelHeight: 500 * scaling
  panelAnchorRight: true

  panelContent: Rectangle {
    id: notificationRect
    color: Color.transparent

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.marginL * scaling
      spacing: Style.marginM * scaling

      // Header section
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM * scaling

        NIcon {
          text: "notifications"
          font.pointSize: Style.fontSizeXXL * scaling
          color: Color.mPrimary
        }

        NText {
          text: "Notification History"
          font.pointSize: Style.fontSizeL * scaling
          font.weight: Style.fontWeightBold
          color: Color.mOnSurface
          Layout.fillWidth: true
        }

        NIconButton {
          icon: Settings.data.notifications.doNotDisturb ? "notifications_off" : "notifications_active"
          tooltipText: Settings.data.notifications.doNotDisturb ? "'Do Not Disturb' is enabled." : "'Do Not Disturb' is disabled."
          sizeRatio: 0.8
          onClicked: Settings.data.notifications.doNotDisturb = !Settings.data.notifications.doNotDisturb
        }

        NIconButton {
          icon: "delete"
          tooltipText: "Clear history"
          sizeRatio: 0.8
          onClicked: NotificationService.clearHistory()
        }

        NIconButton {
          icon: FontService.icons["close"]
          tooltipText: "Close"
          sizeRatio: 0.8
          onClicked: {
            root.close()
          }
        }
      }

      NDivider {
        Layout.fillWidth: true
      }

      // Empty state when no notifications
      ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.alignment: Qt.AlignHCenter
        visible: NotificationService.historyModel.count === 0
        spacing: Style.marginL * scaling

        Item {
          Layout.fillHeight: true
        }

        NIcon {
          text: "notifications_off"
          font.pointSize: 64 * scaling
          color: Color.mOnSurfaceVariant
          Layout.alignment: Qt.AlignHCenter
        }

        NText {
          text: "No notifications"
          font.pointSize: Style.fontSizeL * scaling
          color: Color.mOnSurfaceVariant
          Layout.alignment: Qt.AlignHCenter
        }

        NText {
          text: "Your notifications will show up here as they arrive."
          font.pointSize: Style.fontSizeS * scaling
          color: Color.mOnSurfaceVariant
          Layout.alignment: Qt.AlignHCenter
        }

        Item {
          Layout.fillHeight: true
        }
      }

      // Notification list
      ListView {
        id: notificationList
        Layout.fillWidth: true
        Layout.fillHeight: true
        model: NotificationService.historyModel
        spacing: Style.marginM * scaling
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        visible: NotificationService.historyModel.count > 0

        delegate: Rectangle {
          width: notificationList.width
          height: notificationLayout.implicitHeight + (Style.marginM * scaling * 2)
          radius: Style.radiusM * scaling
          color: notificationMouseArea.containsMouse ? Color.mSecondary : Color.mSurfaceVariant
          border.color: Qt.alpha(Color.mOutline, Style.opacityMedium)
          border.width: Math.max(1, Style.borderS * scaling)

          RowLayout {
            id: notificationLayout
            anchors.fill: parent
            anchors.margins: Style.marginM * scaling
            spacing: Style.marginM * scaling

            // Notification content column
            ColumnLayout {
              Layout.fillWidth: true
              Layout.alignment: Qt.AlignVCenter
              spacing: Style.marginXXS * scaling

              NText {
                text: (summary || "No summary").substring(0, 100)
                font.pointSize: Style.fontSizeM * scaling
                font.weight: Font.Medium
                color: notificationMouseArea.containsMouse ? Color.mSurface : Color.mPrimary
                wrapMode: Text.Wrap
                Layout.fillWidth: true
                Layout.maximumWidth: parent.width
                maximumLineCount: 2
                elide: Text.ElideRight
              }

              NText {
                text: (body || "").substring(0, 150)
                font.pointSize: Style.fontSizeXS * scaling
                color: notificationMouseArea.containsMouse ? Color.mSurface : Color.mOnSurface
                wrapMode: Text.Wrap
                Layout.fillWidth: true
                Layout.maximumWidth: parent.width
                maximumLineCount: 3
                elide: Text.ElideRight
                visible: text.length > 0
              }

              NText {
                text: NotificationService.formatTimestamp(timestamp)
                font.pointSize: Style.fontSizeXS * scaling
                color: notificationMouseArea.containsMouse ? Color.mSurface : Color.mOnSurface
                Layout.fillWidth: true
              }
            }

            // Delete button
            NIconButton {
              icon: "delete"
              tooltipText: "Delete notification"
              sizeRatio: 0.7
              Layout.alignment: Qt.AlignTop

              onClicked: {
                Logger.log("NotificationHistory", "Removing notification:", summary)
                NotificationService.historyModel.remove(index)
                NotificationService.saveHistory()
              }
            }
          }

          MouseArea {
            id: notificationMouseArea
            anchors.fill: parent
            anchors.rightMargin: Style.marginXL * scaling
            hoverEnabled: true
          }
        }
      }
    }
  }
}
