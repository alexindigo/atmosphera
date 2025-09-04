import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import Quickshell.Services.Notifications
import qs.Commons
import qs.Services
import qs.Widgets

// Simple notification popup - displays multiple notifications
Variants {
  model: Quickshell.screens

  delegate: Loader {
    id: root

    required property ShellScreen modelData
    readonly property real scaling: ScalingService.getScreenScale(modelData)

    // Access the notification model from the service
    property ListModel notificationModel: NotificationService.notificationModel

    // Track notifications being removed for animation
    property var removingNotifications: ({})

    // If no notification display activated in settings, then show them all
    active: Settings.isLoaded && modelData
            && (NotificationService.notificationModel.count > 0) ? (Settings.data.notifications.monitors.includes(
                                                                      modelData.name)
                                                                    || (Settings.data.notifications.monitors.length === 0)) : false

    visible: (NotificationService.notificationModel.count > 0)

    sourceComponent: PanelWindow {
      screen: modelData
      color: Color.transparent

      // Position based on bar location
      anchors.top: Settings.data.bar.position === "top"
      anchors.bottom: Settings.data.bar.position === "bottom"
      anchors.right: true
      margins.top: Settings.data.bar.position === "top" ? (Style.barHeight + Style.marginM) * scaling : 0
      margins.bottom: Settings.data.bar.position === "bottom" ? (Style.barHeight + Style.marginM) * scaling : 0
      margins.right: Style.marginM * scaling
      implicitWidth: 360 * scaling
      implicitHeight: Math.min(notificationStack.implicitHeight, (NotificationService.maxVisible * 120) * scaling)
      //WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.exclusionMode: ExclusionMode.Ignore

      // Connect to animation signal from service
      Component.onCompleted: {
        NotificationService.animateAndRemove.connect(function (notification, index) {
          // Prefer lookup by identity to avoid index mismatches
          var delegate = null
          if (notificationStack && notificationStack.children && notificationStack.children.length > 0) {
            for (var i = 0; i < notificationStack.children.length; i++) {
              var child = notificationStack.children[i]
              if (child && child.model && child.model.rawNotification === notification) {
                delegate = child
                break
              }
            }
          }

          // Fallback to index if identity lookup failed
          if (!delegate && notificationStack && notificationStack.children && notificationStack.children[index]) {
            delegate = notificationStack.children[index]
          }

          if (delegate && delegate.animateOut) {
            delegate.animateOut()
          } else {
            // As a last resort, force-remove without animation to avoid stuck popups
            NotificationService.forceRemoveNotification(notification)
          }
        })
      }

      // Main notification container
      Column {
        id: notificationStack
        // Position based on bar location
        anchors.top: Settings.data.bar.position === "top" ? parent.top : undefined
        anchors.bottom: Settings.data.bar.position === "bottom" ? parent.bottom : undefined
        anchors.right: parent.right
        spacing: Style.marginS * scaling
        width: 360 * scaling
        visible: true

        // Multiple notifications display
        Repeater {
          model: notificationModel
          delegate: Rectangle {
            width: 360 * scaling
            height: Math.max(80 * scaling, contentRow.implicitHeight + (Style.marginL * 2 * scaling))
            clip: true
            radius: Style.radiusL * scaling
            border.color: Color.applyOpacity(Color.mOutline, "33")
            border.width: Math.max(1, Style.borderS * scaling)
            color: Color.mSurface

            // Animation properties
            property real scaleValue: 0.8
            property real opacityValue: 0.0
            property bool isRemoving: false

            // Scale and fade-in animation
            scale: scaleValue
            opacity: opacityValue

            // Animate in when the item is created
            Component.onCompleted: {
              scaleValue = 1.0
              opacityValue = 1.0
            }

            // Animate out when being removed
            function animateOut() {
              isRemoving = true
              scaleValue = 0.8
              opacityValue = 0.0
            }

            // Timer for delayed removal after animation
            Timer {
              id: removalTimer
              interval: Style.animationSlow
              repeat: false
              onTriggered: {
                NotificationService.forceRemoveNotification(model.rawNotification)
              }
            }

            // Check if this notification is being removed
            onIsRemovingChanged: {
              if (isRemoving) {
                // Remove from model after animation completes
                removalTimer.start()
              }
            }

            // Animation behaviors
            Behavior on scale {
              NumberAnimation {
                duration: Style.animationSlow
                easing.type: Easing.OutExpo
                //easing.type: Easing.OutBack   looks better but notification get clipped on all sides
              }
            }

            Behavior on opacity {
              NumberAnimation {
                duration: Style.animationNormal
                easing.type: Easing.OutQuad
              }
            }

            RowLayout {
              id: contentRow
              anchors.fill: parent
              anchors.margins: Style.marginL * scaling
              spacing: Style.marginL * scaling

              // Right: header on top, then avatar + texts
              ColumnLayout {
                id: textColumn
                spacing: Style.marginS * scaling
                Layout.fillWidth: true

                RowLayout {
                  spacing: Style.marginS * scaling
                  id: appHeaderRow
                  NText {
                    text: `${(model.appName || model.desktopEntry)
                          || "Unknown App"} · ${NotificationService.formatTimestamp(model.timestamp)}`
                    color: Color.mSecondary
                    font.pointSize: Style.fontSizeXS * scaling
                  }
                  Rectangle {
                    width: 6 * scaling
                    height: 6 * scaling
                    radius: Style.radiusXS * scaling
                    color: (model.urgency === NotificationUrgency.Critical) ? Color.mError : (model.urgency === NotificationUrgency.Low) ? Color.mOnSurface : Color.mPrimary
                    Layout.alignment: Qt.AlignVCenter
                  }
                  Item {
                    Layout.fillWidth: true
                  }
                }

                RowLayout {
                  id: bodyRow
                  spacing: Style.marginM * scaling

                  NImageCircled {
                    id: appAvatar
                    Layout.preferredWidth: 40 * scaling
                    Layout.preferredHeight: 40 * scaling
                    Layout.alignment: Qt.AlignTop
                    // Start avatar aligned with body (below the summary)
                    anchors.topMargin: textContent.childrenRect.y
                    imagePath: Icons.iconFromName(model.appIcon, "application-x-executable")
                    fallbackIcon: "apps"
                    borderColor: Color.transparent
                    borderWidth: 0
                    visible: imagePath && imagePath !== ""
                  }

                  Column {
                    id: textContent
                    spacing: Style.marginS * scaling
                    Layout.fillWidth: true
                    // Ensure a concrete width so text wraps
                    width: (textColumn.width - (appAvatar.visible ? (appAvatar.width + Style.marginM * scaling) : 0))

                    NText {
                      text: model.summary || "No summary"
                      font.pointSize: Style.fontSizeL * scaling
                      font.weight: Style.fontWeightMedium
                      color: Color.mOnSurface
                      wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                      Layout.fillWidth: true
                      width: parent.width
                      maximumLineCount: 3
                      elide: Text.ElideRight
                    }

                    NText {
                      text: model.body || ""
                      font.pointSize: Style.fontSizeM * scaling
                      color: Color.mOnSurface
                      wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                      Layout.fillWidth: true
                      width: parent.width
                      maximumLineCount: 5
                      elide: Text.ElideRight
                    }
                  }
                }
              }

              // Actions removed
            }

            NIconButton {
              icon: "close"
              tooltipText: "Close"
              // Compact target (~24dp) and glyph (~16dp)
              sizeRatio: 0.75
              fontPointSize: 16
              anchors.top: parent.top
              anchors.right: parent.right
              anchors.margins: Style.marginS * scaling

              onClicked: {
                animateOut()
              }
            }
          }
        }
      }
    }
  }
}
