import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets

Rectangle {
  id: root

  property ShellScreen screen
  property real scaling: 1.0

  // Widget properties passed from Bar.qml for per-instance settings
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

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

  readonly property string barPosition: Settings.data.bar.position
  readonly property bool isBarVertical: barPosition === "left" || barPosition === "right"
  readonly property bool compact: (Settings.data.bar.density === "compact")

  readonly property var now: Time.date

  // Resolve settings: try user settings or defaults from BarWidgetRegistry
  readonly property bool usePrimaryColor: widgetSettings.usePrimaryColor !== undefined ? widgetSettings.usePrimaryColor : widgetMetadata.usePrimaryColor
  property bool useMonospacedFont: widgetSettings.useMonospacedFont !== undefined ? widgetSettings.useMonospacedFont : widgetMetadata.useMonospacedFont
  readonly property string formatHorizontal: widgetSettings.formatHorizontal !== undefined ? widgetSettings.formatHorizontal : widgetMetadata.formatHorizontal
  readonly property string formatVertical: widgetSettings.formatVertical !== undefined ? widgetSettings.formatVertical : widgetMetadata.formatVertical

  implicitWidth: isBarVertical ? Math.round(Style.capsuleHeight * scaling) : Math.round(layout.implicitWidth + Style.marginM * 2 * scaling)
  implicitHeight: isBarVertical ? Math.round(Style.capsuleHeight * 2.5 * scaling) : Math.round(Style.capsuleHeight * scaling) // Match BarPill

  radius: Math.round(Style.radiusS * scaling)
  color: Settings.data.bar.showCapsule ? Color.mSurfaceVariant : Color.transparent

  Item {
    id: clockContainer
    anchors.centerIn: parent

    RowLayout {
      id: layout
      anchors.centerIn: parent

      Loader {
        active: !isBarVertical
        sourceComponent: NText {
          anchors.centerIn: parent
          visible: text !== ""
          text: Qt.formatDateTime(now, formatHorizontal.trim())
          font.family: useMonospacedFont ? Settings.data.ui.fontFixed : Settings.data.ui.fontDefault
          font.pointSize: isBarVertical ? Style.fontSizeS * scaling : Style.fontSizeS * scaling
          font.weight: Style.fontWeightBold
          color: usePrimaryColor ? Color.mPrimary : Color.mOnSurface
          wrapMode: Text.WordWrap
        }
      }

      Loader {
        active: isBarVertical
        sourceComponent: ColumnLayout {
          anchors.centerIn: parent
          spacing: -2 * scaling
          Repeater {
            model: Qt.formatDateTime(now, formatVertical.trim()).split(" ")
            delegate: NText {
              visible: text !== ""
              text: modelData
              font.family: useMonospacedFont ? Settings.data.ui.fontFixed : Settings.data.ui.fontDefault
              font.pointSize: isBarVertical ? Style.fontSizeS * scaling : Style.fontSizeXS * scaling
              font.weight: Style.fontWeightBold
              color: usePrimaryColor ? Color.mPrimary : Color.mOnSurface
              wrapMode: Text.WordWrap
              Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
            }
          }
        }
      }
    }
  }

  NTooltip {
    id: tooltip
    text: "Open calendar"
    target: clockContainer
    positionAbove: Settings.data.bar.position === "bottom"
  }

  MouseArea {
    id: clockMouseArea
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    hoverEnabled: true
    onEntered: {
      if (!PanelService.getPanel("calendarPanel")?.active) {
        tooltip.show()
      }
    }
    onExited: {
      tooltip.hide()
    }
    onClicked: {
      tooltip.hide()
      PanelService.getPanel("calendarPanel")?.toggle(this)
    }
  }
}
