import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.UPower
import qs.Commons
import qs.Services
import qs.Widgets
import qs.Modules.Notification

Variants {
  model: Quickshell.screens

  delegate: Loader {
    id: root

    required property ShellScreen modelData
    property real scaling: ScalingService.getScreenScale(modelData)

    Connections {
      target: ScalingService
      function onScaleChanged(screenName, scale) {
        if ((modelData !== null) && (screenName === modelData.name)) {
          scaling = scale
        }
      }
    }

    active: Settings.isLoaded && modelData && modelData.name ? (Settings.data.bar.monitors.includes(modelData.name) || (Settings.data.bar.monitors.length === 0)) : false

    sourceComponent: PanelWindow {
      screen: modelData || null

      WlrLayershell.namespace: "noctalia-bar"

      implicitHeight: (Settings.data.bar.position === "left" || Settings.data.bar.position === "right") ? screen.height : Math.round(Style.barHeight * scaling)
      implicitWidth: (Settings.data.bar.position === "left" || Settings.data.bar.position === "right") ? Math.round(Style.barHeight * scaling) : screen.width
      color: Color.transparent

      anchors {
        top: Settings.data.bar.position === "top" || Settings.data.bar.position === "left" || Settings.data.bar.position === "right"
        bottom: Settings.data.bar.position === "bottom" || Settings.data.bar.position === "left" || Settings.data.bar.position === "right"
        left: Settings.data.bar.position === "left" || Settings.data.bar.position === "top" || Settings.data.bar.position === "bottom"
        right: Settings.data.bar.position === "right" || Settings.data.bar.position === "top" || Settings.data.bar.position === "bottom"
      }

      // Floating bar margins - only apply when floating is enabled
      margins {
        top: Settings.data.bar.floating ? Settings.data.bar.marginTop : 0
        bottom: Settings.data.bar.floating ? Settings.data.bar.marginBottom : 0
        left: Settings.data.bar.floating ? Settings.data.bar.marginLeft : 0
        right: Settings.data.bar.floating ? Settings.data.bar.marginRight : 0
      }

      Item {
        anchors.fill: parent
        clip: true

        // Background fill
        Rectangle {
          id: bar

          anchors.fill: parent
          color: Qt.alpha(Color.mSurface, Settings.data.bar.backgroundOpacity)

          // Floating bar rounded corners
          radius: Settings.data.bar.floating ? Settings.data.bar.rounding : 0
        }

        // For vertical bars, use a single column layout
        Loader {
          id: verticalBarLayout
          anchors.fill: parent
          visible: Settings.data.bar.position === "left" || Settings.data.bar.position === "right"
          sourceComponent: verticalBarComponent
        }

        // For horizontal bars, use the original three-section layout
        Loader {
          id: horizontalBarLayout
          anchors.fill: parent
          visible: Settings.data.bar.position === "top" || Settings.data.bar.position === "bottom"
          sourceComponent: horizontalBarComponent
        }

        // Main layout components
        Component {
          id: verticalBarComponent
          Item {
            anchors.fill: parent

            // Top section (left widgets)
            Column {
              spacing: Style.marginS * root.scaling
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.top: parent.top
              anchors.topMargin: Style.marginM * root.scaling
              width: parent.width

              Repeater {
                model: Settings.data.bar.widgets.left
                delegate: NWidgetLoader {
                  widgetId: (modelData.id !== undefined ? modelData.id : "")
                  widgetProps: {
                    "screen": root.modelData || null,
                    "scaling": ScalingService.getScreenScale(screen),
                    "widgetId": modelData.id,
                    "section": "left",
                    "sectionWidgetIndex": index,
                    "sectionWidgetsCount": Settings.data.bar.widgets.left.length,
                    "barPosition": BarService.position
                  }
                  anchors.horizontalCenter: parent.horizontalCenter
                }
              }
            }

            // Center section (center widgets)
            Column {
              spacing: Style.marginS * root.scaling
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width

              Repeater {
                model: Settings.data.bar.widgets.center
                delegate: NWidgetLoader {
                  widgetId: (modelData.id !== undefined ? modelData.id : "")
                  widgetProps: {
                    "screen": root.modelData || null,
                    "scaling": ScalingService.getScreenScale(screen),
                    "widgetId": modelData.id,
                    "section": "center",
                    "sectionWidgetIndex": index,
                    "sectionWidgetsCount": Settings.data.bar.widgets.center.length,
                    "barPosition": BarService.position
                  }
                  anchors.horizontalCenter: parent.horizontalCenter
                }
              }
            }

            // Bottom section (right widgets)
            Column {
              spacing: Style.marginS * root.scaling
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.bottom
              anchors.bottomMargin: Style.marginM * root.scaling
              width: parent.width

              Repeater {
                model: Settings.data.bar.widgets.right
                delegate: NWidgetLoader {
                  widgetId: (modelData.id !== undefined ? modelData.id : "")
                  widgetProps: {
                    "screen": root.modelData || null,
                    "scaling": ScalingService.getScreenScale(screen),
                    "widgetId": modelData.id,
                    "section": "right",
                    "sectionWidgetIndex": index,
                    "sectionWidgetsCount": Settings.data.bar.widgets.right.length,
                    "barPosition": BarService.position
                  }
                  anchors.horizontalCenter: parent.horizontalCenter
                }
              }
            }
          }
        }

        Component {
          id: horizontalBarComponent
          Row {
            anchors.fill: parent

            // Left Section
            Row {
              id: leftSection
              objectName: "leftSection"
              height: parent.height
              anchors.left: parent.left
              anchors.leftMargin: Style.marginS * root.scaling
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.marginS * root.scaling

              Repeater {
                model: Settings.data.bar.widgets.left
                delegate: NWidgetLoader {
                  widgetId: (modelData.id !== undefined ? modelData.id : "")
                  widgetProps: {
                    "screen": root.modelData || null,
                    "scaling": ScalingService.getScreenScale(screen),
                    "widgetId": modelData.id,
                    "section": "left",
                    "sectionWidgetIndex": index,
                    "sectionWidgetsCount": Settings.data.bar.widgets.left.length,
                    "barPosition": BarService.position
                  }
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
            }

            // Center Section
            Row {
              id: centerSection
              objectName: "centerSection"
              height: parent.height
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.marginS * root.scaling

              Repeater {
                model: Settings.data.bar.widgets.center
                delegate: NWidgetLoader {
                  widgetId: (modelData.id !== undefined ? modelData.id : "")
                  widgetProps: {
                    "screen": root.modelData || null,
                    "scaling": ScalingService.getScreenScale(screen),
                    "widgetId": modelData.id,
                    "section": "center",
                    "sectionWidgetIndex": index,
                    "sectionWidgetsCount": Settings.data.bar.widgets.center.length,
                    "barPosition": BarService.position
                  }
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
            }

            // Right Section
            Row {
              id: rightSection
              objectName: "rightSection"
              height: parent.height
              anchors.right: parent.right
              anchors.rightMargin: Style.marginS * root.scaling
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.marginS * root.scaling

              Repeater {
                model: Settings.data.bar.widgets.right
                delegate: NWidgetLoader {
                  widgetId: (modelData.id !== undefined ? modelData.id : "")
                  widgetProps: {
                    "screen": root.modelData || null,
                    "scaling": ScalingService.getScreenScale(screen),
                    "widgetId": modelData.id,
                    "section": "right",
                    "sectionWidgetIndex": index,
                    "sectionWidgetsCount": Settings.data.bar.widgets.right.length,
                    "barPosition": BarService.position
                  }
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
            }
          }
        }
      }
    }
  }
}
