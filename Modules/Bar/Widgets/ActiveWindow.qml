import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Commons
import qs.Services
import qs.Widgets

Item {
  id: root
  property ShellScreen screen
  property real scaling: 1.0

  // Widget properties passed from Bar.qml for per-instance settings
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0
  property string barPosition: "top"

  property var widgetMetadata: BarWidgetRegistry.widgetMetadata[widgetId]
  property var widgetSettings: {
    if (section && sectionWidgetIndex >= 0) {
      var widgets = Settings.data.bar.widgets[section]
      if (widgets && sectionWidgetIndex < widgets.length) {
        return widgets[sectionWidgetIndex]
      }
    }
    return {}
  }

  readonly property bool showIcon: (widgetSettings.showIcon !== undefined) ? widgetSettings.showIcon : widgetMetadata.showIcon

  // 6% of total width
  readonly property real minWidth: Math.max(1, screen.width * 0.06)
  readonly property real maxWidth: minWidth * 2

  implicitHeight: (barPosition === "left" || barPosition === "right") ? calculatedVerticalHeight() : Math.round(Style.barHeight * scaling)
  implicitWidth: (barPosition === "left" || barPosition === "right") ? Math.round(Style.capsuleHeight * scaling) : calculatedHorizontalWidth()

  function getTitle() {
    try {
      return CompositorService.focusedWindowTitle !== "(No active window)" ? CompositorService.focusedWindowTitle : ""
    } catch (e) {
      Logger.warn("ActiveWindow", "Error getting title:", e)
      return ""
    }
  }

  visible: getTitle() !== ""

  function calculatedVerticalHeight() {
    let total = Math.round(Style.capsuleHeight * scaling)
    if (showIcon) {
      total += Style.fontSizeL * scaling * 1.2 + Style.marginS * scaling
    }
    return total
  }

  function calculatedHorizontalWidth() {
    let total = Style.marginM * 2 * scaling // padding
    if (showIcon) {
      total += Style.fontSizeL * scaling * 1.2 + Style.marginS * scaling
    }
    total += Math.min(fullTitleMetrics.contentWidth, minWidth * scaling)
    return total
  }

  function getAppIcon() {
    try {
      // Try CompositorService first
      const focusedWindow = CompositorService.getFocusedWindow()
      if (focusedWindow && focusedWindow.appId) {
        try {
          const idValue = focusedWindow.appId
          const normalizedId = (typeof idValue === 'string') ? idValue : String(idValue)
          const iconResult = AppIcons.iconForAppId(normalizedId.toLowerCase())
          if (iconResult && iconResult !== "") {
            return iconResult
          }
        } catch (iconError) {
          Logger.warn("ActiveWindow", "Error getting icon from CompositorService:", iconError)
        }
      }

      // Fallback to ToplevelManager
      if (ToplevelManager && ToplevelManager.activeToplevel) {
        try {
          const activeToplevel = ToplevelManager.activeToplevel
          if (activeToplevel.appId) {
            const idValue2 = activeToplevel.appId
            const normalizedId2 = (typeof idValue2 === 'string') ? idValue2 : String(idValue2)
            const iconResult2 = AppIcons.iconForAppId(normalizedId2.toLowerCase())
            if (iconResult2 && iconResult2 !== "") {
              return iconResult2
            }
          }
        } catch (fallbackError) {
          Logger.warn("ActiveWindow", "Error getting icon from ToplevelManager:", fallbackError)
        }
      }

      return ""
    } catch (e) {
      Logger.warn("ActiveWindow", "Error in getAppIcon:", e)
      return ""
    }
  }

  // A hidden text element to safely measure the full title width
  NText {
    id: fullTitleMetrics
    visible: false
    text: getTitle()
    font.pointSize: Style.fontSizeS * scaling
    font.weight: Style.fontWeightMedium
  }

  Rectangle {
    id: windowTitleRect
    visible: root.visible
    anchors.centerIn: parent
    width: (barPosition === "left" || barPosition === "right") ? Math.round(60 * scaling) : parent.width
    height: (barPosition === "left" || barPosition === "right") ? parent.height : Math.round(Style.capsuleHeight * scaling)
    radius: Math.round(Style.radiusM * scaling)
    color: Color.mSurfaceVariant

    Item {
      id: mainContainer
      anchors.fill: parent
      anchors.leftMargin: Style.marginS * scaling
      anchors.rightMargin: Style.marginS * scaling
      clip: true

      // Horizontal layout for top/bottom bars
      RowLayout {
        id: horizontalLayout
        anchors.centerIn: parent
        spacing: Style.marginS * scaling
        visible: barPosition === "top" || barPosition === "bottom"

        // Window icon
        Item {
          Layout.preferredWidth: Style.fontSizeL * scaling * 1.2
          Layout.preferredHeight: Style.fontSizeL * scaling * 1.2
          Layout.alignment: Qt.AlignVCenter
          visible: getTitle() !== "" && showIcon

          IconImage {
            id: windowIcon
            anchors.fill: parent
            source: getAppIcon()
            asynchronous: true
            smooth: true
            visible: source !== ""

            // Handle loading errors gracefully
            onStatusChanged: {
              if (status === Image.Error) {
                Logger.warn("ActiveWindow", "Failed to load icon:", source)
              }
            }
          }
        }

        NText {
          id: titleText
          Layout.preferredWidth: {
            try {
              if (mouseArea.containsMouse) {
                return Math.round(Math.min(fullTitleMetrics.contentWidth, root.maxWidth * scaling))
              } else {
                return Math.round(Math.min(fullTitleMetrics.contentWidth, root.minWidth * scaling))
              }
            } catch (e) {
              Logger.warn("ActiveWindow", "Error calculating width:", e)
              return root.minWidth * scaling
            }
          }
          Layout.alignment: Qt.AlignVCenter
          horizontalAlignment: Text.AlignLeft
          text: getTitle()
          font.pointSize: Style.fontSizeS * scaling
          font.weight: Style.fontWeightMedium
          elide: mouseArea.containsMouse ? Text.ElideNone : Text.ElideRight
          verticalAlignment: Text.AlignVCenter
          color: Color.mPrimary
          clip: true

          Behavior on Layout.preferredWidth {
            NumberAnimation {
              duration: Style.animationSlow
              easing.type: Easing.InOutCubic
            }
          }
        }
      }

      // Vertical layout for left/right bars - icon only
      Item {
        id: verticalLayout
        anchors.centerIn: parent
        width: parent.width - Style.marginM * scaling * 2
        height: parent.height - Style.marginM * scaling * 2
        visible: barPosition === "left" || barPosition === "right"

        // Window icon
        Item {
          width: Style.fontSizeL * scaling * 1.2
          height: Style.fontSizeL * scaling * 1.2
          anchors.centerIn: parent
          visible: getTitle() !== "" && showIcon

          IconImage {
            id: windowIconVertical
            anchors.fill: parent
            source: getAppIcon()
            asynchronous: true
            smooth: true
            visible: source !== ""

            // Handle loading errors gracefully
            onStatusChanged: {
              if (status === Image.Error) {
                Logger.warn("ActiveWindow", "Failed to load icon:", source)
              }
            }
          }
        }

      }

      // Mouse area for hover detection
      MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: {
          if (barPosition === "left" || barPosition === "right") {
            tooltip.show()
          }
        }
        onExited: {
          if (barPosition === "left" || barPosition === "right") {
            tooltip.hide()
          }
        }
      }

      // Hover tooltip with full title (only for vertical bars)
      NTooltip {
        id: tooltip
        target: verticalLayout
        text: getTitle()
        positionLeft: barPosition === "right"
        positionRight: barPosition === "left"
        delay: 500
      }
    }
  }

  Connections {
    target: CompositorService
    function onActiveWindowChanged() {
      try {
        windowIcon.source = Qt.binding(getAppIcon)
        windowIconVertical.source = Qt.binding(getAppIcon)
      } catch (e) {
        Logger.warn("ActiveWindow", "Error in onActiveWindowChanged:", e)
      }
    }
    function onWindowListChanged() {
      try {
        windowIcon.source = Qt.binding(getAppIcon)
        windowIconVertical.source = Qt.binding(getAppIcon)
      } catch (e) {
        Logger.warn("ActiveWindow", "Error in onWindowListChanged:", e)
      }
    }
  }
}
