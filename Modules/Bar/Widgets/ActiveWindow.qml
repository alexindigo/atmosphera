import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.Commons
import qs.Services
import qs.Widgets

Row {
  id: root

  property ShellScreen screen
  property real scaling: ScalingService.scale(screen)
  // Title stays collapsed by default; expands only on hover
  property bool showingFullTitle: false
  readonly property int minWidth: 120

  anchors.verticalCenter: parent.verticalCenter
  spacing: Style.marginS * scaling
  visible: getTitle() !== ""

  // Remove auto-expand timer; we rely solely on hover

  // No auto-expansion on window change; keep collapsed unless hovered
  function getTitle() {
    // Use the service's focusedWindowTitle property which is updated immediately
    // when WindowOpenedOrChanged events are received
    return CompositorService.focusedWindowTitle !== "(No active window)" ? CompositorService.focusedWindowTitle : ""
  }

  function getAppIcon() {
    const focusedWindow = CompositorService.getFocusedWindow()
    if (!focusedWindow || !focusedWindow.appId)
      return ""

    return Icons.iconForAppId(focusedWindow.appId)
  }

  //  A hidden text element to safely measure the full title width
  NText {
    id: fullTitleMetrics
    visible: false
    text: titleText.text
    font: titleText.font
  }

  Rectangle {
    // Let the Rectangle size itself based on its content (the Row)
    visible: root.visible
    width: row.width + Style.marginM * scaling * 2
    height: Math.round(Style.capsuleHeight * scaling)
    radius: Math.round(Style.radiusM * scaling)
    color: Color.mSurfaceVariant

    anchors.verticalCenter: parent.verticalCenter

    Item {
      id: mainContainer
      anchors.fill: parent
      anchors.leftMargin: Style.marginS * scaling
      anchors.rightMargin: Style.marginS * scaling

      Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.marginS * scaling

        // Window icon
        Item {
          width: Style.fontSizeL * scaling * 1.2
          height: Style.fontSizeL * scaling * 1.2
          anchors.verticalCenter: parent.verticalCenter
          visible: getTitle() !== "" && Settings.data.bar.showActiveWindowIcon

          IconImage {
            id: windowIcon
            anchors.fill: parent
            source: getAppIcon()
            asynchronous: true
            smooth: true
            visible: source !== ""
          }
        }

        NText {
          id: titleText

          // Collapsed width when not hovered, expand on hover
          width: mouseArea.containsMouse ? Math.min(fullTitleMetrics.contentWidth + (Style.marginS * scaling),
                                                    400 * scaling) : (minWidth * scaling)
          horizontalAlignment: Text.AlignLeft
          text: getTitle()
          font.pointSize: Style.fontSizeS * scaling
          font.weight: Style.fontWeightMedium
          elide: mouseArea.containsMouse ? Text.ElideNone : Text.ElideRight
          anchors.verticalCenter: parent.verticalCenter
          verticalAlignment: Text.AlignVCenter
          color: Color.mSecondary
          clip: true

          Behavior on width {
            NumberAnimation {
              duration: Style.animationSlow
              easing.type: Easing.InOutCubic
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
      }
    }
  }
}
