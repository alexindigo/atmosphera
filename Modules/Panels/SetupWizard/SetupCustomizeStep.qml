import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root

  property real selectedScaleRatio: 1.0
  property string selectedBarPosition: "top"

  signal scaleRatioChanged(real ratio)
  signal barPositionChanged(string position)


  ColumnLayout {
    Layout.fillWidth: true
      spacing: Style.marginM

      // Bar Position section
      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.marginM

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.marginS

          Rectangle {
            width: 28
            height: 28
            radius: Style.radiusM
            color: Color.mSurface

            AtmoIcon {
              icon: Icon.layout2
              pointSize: Style.fontSizeL
              color: Color.mPrimary
              anchors.centerIn: parent
            }
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            NText {
              text: I18n.tr("panels.bar.appearance-position-label")
              pointSize: Style.fontSizeL
              font.weight: Style.fontWeightBold
              color: Color.mOnSurface
            }

            NText {
              text: I18n.tr("panels.bar.appearance-position-description")
              pointSize: Style.fontSizeS
              color: Color.mOnSurfaceVariant
            }
          }
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.marginS

          Repeater {
            model: [
              {
                "key": "top",
                "name": I18n.tr("positions.top"),
                "icon": "position-top"
              },
              {
                "key": "bottom",
                "name": I18n.tr("positions.bottom"),
                "icon": "position-bottom"
              },
              {
                "key": "left",
                "name": I18n.tr("positions.left"),
                "icon": "position-left"
              },
              {
                "key": "right",
                "name": I18n.tr("positions.right"),
                "icon": "position-right"
              }
            ]
            delegate: Rectangle {
              Layout.fillWidth: true
              Layout.preferredHeight: 40
              radius: Style.radiusM
              border.width: Style.borderS

              property bool isActive: selectedBarPosition === modelData.key

              color: (positionHoverHandler.hovered || isActive) ? Color.mPrimary : Color.mSurfaceVariant
              border.color: (positionHoverHandler.hovered || isActive) ? Color.mPrimary : Color.mOutline
              opacity: (positionHoverHandler.hovered || isActive) ? 1.0 : 0.8

              NText {
                text: modelData.name
                pointSize: Style.fontSizeM
                font.weight: (positionHoverHandler.hovered || parent.isActive) ? Style.fontWeightBold : Style.fontWeightMedium
                color: (positionHoverHandler.hovered || parent.isActive) ? Color.mOnPrimary : Color.mOnSurface
                anchors.centerIn: parent
              }

              HoverHandler {
                id: positionHoverHandler
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  selectedBarPosition = modelData.key;
                  barPositionChanged(modelData.key);
                }
              }

              Behavior on color {
                ColorAnimation {
                  duration: Style.animationFast
                }
              }
              Behavior on border.color {
                ColorAnimation {
                  duration: Style.animationFast
                }
              }
              Behavior on opacity {
                NumberAnimation {
                  duration: Style.animationFast
                }
              }
            }
          }
        }
      }

      // Divider
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: Color.mOutline
        opacity: 0.2
        Layout.topMargin: Style.marginS
        Layout.bottomMargin: Style.marginS
      }

      // Bar Density section
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM

        Rectangle {
          width: 32
          height: 32
          radius: Style.radiusM
          color: Color.mSurface
          AtmoIcon {
            icon: Icon.minimize
            pointSize: Style.fontSizeL
            color: Color.mPrimary
            anchors.centerIn: parent
          }
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: 2
          NText {
            text: I18n.tr("panels.bar.appearance-density-label")
            pointSize: Style.fontSizeL
            font.weight: Style.fontWeightBold
            color: Color.mOnSurface
          }
          NText {
            text: I18n.tr("panels.bar.appearance-density-description")
            pointSize: Style.fontSizeS
            color: Color.mOnSurfaceVariant
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
          }
        }

        RowLayout {
          spacing: Style.marginS
          Repeater {
            model: [
              {
                "key": "mini",
                "name": I18n.tr("options.bar.density-mini")
              },
              {
                "key": "compact",
                "name": I18n.tr("options.bar.density-compact")
              },
              {
                "key": "default",
                "name": I18n.tr("options.bar.density-default")
              },
              {
                "key": "comfortable",
                "name": I18n.tr("options.bar.density-comfortable")
              },
              {
                "key": "spacious",
                "name": I18n.tr("options.bar.density-spacious")
              }
            ]
            delegate: Rectangle {
              radius: Style.radiusM
              border.width: Style.borderS
              Layout.preferredHeight: 32
              Layout.preferredWidth: Math.max(90, densityText.implicitWidth + Style.margin2XL)

              property bool isActive: Settings.data.bar.density === modelData.key

              color: (densityHoverHandler.hovered || isActive) ? Color.mPrimary : Color.mSurfaceVariant
              border.color: (densityHoverHandler.hovered || isActive) ? Color.mPrimary : Color.mOutline
              opacity: (densityHoverHandler.hovered || isActive) ? 1.0 : 0.8

              NText {
                id: densityText
                text: modelData.name
                pointSize: Style.fontSizeS
                font.weight: (densityHoverHandler.hovered || parent.isActive) ? Style.fontWeightBold : Style.fontWeightMedium
                color: (densityHoverHandler.hovered || parent.isActive) ? Color.mOnPrimary : Color.mOnSurface
                anchors.centerIn: parent
              }

              HoverHandler {
                id: densityHoverHandler
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  Settings.data.bar.density = modelData.key;
                }
              }

              Behavior on color {
                ColorAnimation {
                  duration: Style.animationFast
                }
              }
              Behavior on border.color {
                ColorAnimation {
                  duration: Style.animationFast
                }
              }
              Behavior on opacity {
                NumberAnimation {
                  duration: Style.animationFast
                }
              }
            }
          }
        }
      }

      // Divider
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: Color.mOutline
        opacity: 0.2
        Layout.topMargin: Style.marginS
        Layout.bottomMargin: Style.marginS
      }

      // UI Scale section
      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.marginM

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.marginS
          Rectangle {
            width: 32
            height: 32
            radius: Style.radiusM
            color: Color.mSurface
            AtmoIcon {
              icon: Icon.maximize
              pointSize: Style.fontSizeL
              color: Color.mPrimary
              anchors.centerIn: parent
            }
          }
          ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            NText {
              text: I18n.tr("panels.user-interface.scaling-label")
              pointSize: Style.fontSizeL
              font.weight: Style.fontWeightBold
              color: Color.mOnSurface
            }
            NText {
              text: I18n.tr("panels.user-interface.scaling-description")
              pointSize: Style.fontSizeS
              color: Color.mOnSurfaceVariant
            }
          }
        }

        NValueSlider {
          Layout.fillWidth: true
          from: 0.8
          to: 1.2
          stepSize: 0.05
          value: selectedScaleRatio
          onMoved: function (value) {
            selectedScaleRatio = value;
            scaleRatioChanged(value);
          }
          text: Math.floor(selectedScaleRatio * 100) + "%"
        }
      }

      // Divider
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: Color.mOutline
        opacity: 0.2
        Layout.topMargin: Style.marginS
        Layout.bottomMargin: Style.marginS
      }

      // Bar Type section
      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.marginM

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.marginS

          Rectangle {
            width: 28
            height: 28
            radius: Style.radiusM
            color: Color.mSurface

            AtmoIcon {
              icon: Icon.layout2
              pointSize: Style.fontSizeL
              color: Color.mPrimary
              anchors.centerIn: parent
            }
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            NText {
              text: I18n.tr("panels.bar.appearance-type-label") ?? "Bar Type"
              pointSize: Style.fontSizeL
              font.weight: Style.fontWeightBold
              color: Color.mOnSurface
            }

            NText {
              text: I18n.tr("panels.bar.appearance-type-description") ?? "Choose the style of the bar: Simple, Floating or Framed"
              pointSize: Style.fontSizeS
              color: Color.mOnSurfaceVariant
            }
          }
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.marginS

          Repeater {
            model: [
              {
                "key": "simple",
                "name": I18n.tr("options.bar.type-simple") ?? "Simple"
              },
              {
                "key": "floating",
                "name": I18n.tr("options.bar.type-floating") ?? "Floating"
              },
              {
                "key": "framed",
                "name": I18n.tr("options.bar.type-framed") ?? "Framed"
              }
            ]
            delegate: Rectangle {
              Layout.fillWidth: true
              Layout.preferredHeight: 40
              radius: Style.radiusM
              border.width: Style.borderS

              property bool isActive: Settings.data.bar.barType === modelData.key

              color: (barTypeHoverHandler.hovered || isActive) ? Color.mPrimary : Color.mSurfaceVariant
              border.color: (barTypeHoverHandler.hovered || isActive) ? Color.mPrimary : Color.mOutline
              opacity: (barTypeHoverHandler.hovered || isActive) ? 1.0 : 0.8

              NText {
                text: modelData.name
                pointSize: Style.fontSizeM
                font.weight: (barTypeHoverHandler.hovered || parent.isActive) ? Style.fontWeightBold : Style.fontWeightMedium
                color: (barTypeHoverHandler.hovered || parent.isActive) ? Color.mOnPrimary : Color.mOnSurface
                anchors.centerIn: parent
              }

              HoverHandler {
                id: barTypeHoverHandler
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  Settings.data.bar.barType = modelData.key;
                }
              }

              Behavior on color {
                ColorAnimation {
                  duration: Style.animationFast
                }
              }
              Behavior on border.color {
                ColorAnimation {
                  duration: Style.animationFast
                }
              }
              Behavior on opacity {
                NumberAnimation {
                  duration: Style.animationFast
                }
              }
            }
          }
        }
      }

      // Divider
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: Color.mOutline
        opacity: 0.2
        Layout.topMargin: Style.marginS
        Layout.bottomMargin: Style.marginS
      }

      // Divider
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: Color.mOutline
        opacity: 0.2
        Layout.topMargin: Style.marginS
        Layout.bottomMargin: Style.marginS
      }

      // Dim Desktop opacity
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM
        Rectangle {
          width: 32
          height: 32
          radius: Style.radiusM
          color: Color.mSurface
          AtmoIcon {
            icon: Icon.screenShare
            pointSize: Style.fontSizeL
            color: Color.mPrimary
            anchors.centerIn: parent
          }
        }
        ColumnLayout {
          Layout.fillWidth: true
          spacing: 2
          NText {
            text: I18n.tr("panels.user-interface.dimmer-opacity-label")
            pointSize: Style.fontSizeL
            font.weight: Style.fontWeightBold
            color: Color.mOnSurface
          }
          NText {
            text: I18n.tr("panels.user-interface.dimmer-opacity-description")
            pointSize: Style.fontSizeS
            color: Color.mOnSurfaceVariant
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
          }
          NValueSlider {
            Layout.fillWidth: true
            Layout.topMargin: Style.marginXS
            from: 0
            to: 1
            stepSize: 0.01
            value: Settings.data.general.dimmerOpacity
            onMoved: value => Settings.data.general.dimmerOpacity = value
            text: Math.floor(Settings.data.general.dimmerOpacity * 100) + "%"
          }
        }
      }

      // Divider
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: Color.mOutline
        opacity: 0.2
        Layout.topMargin: Style.marginS
        Layout.bottomMargin: Style.marginS
      }

      // Drop Shadows toggle
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM
        Rectangle {
          width: 32
          height: 32
          radius: Style.radiusM
          color: Color.mSurface
          AtmoIcon {
            icon: Icon.uiShadow
            pointSize: Style.fontSizeL
            color: Color.mPrimary
            anchors.centerIn: parent
          }
        }
        ColumnLayout {
          Layout.fillWidth: true
          spacing: 2
          NText {
            text: I18n.tr("panels.user-interface.shadows-label")
            pointSize: Style.fontSizeL
            font.weight: Style.fontWeightBold
            color: Color.mOnSurface
          }
          NText {
            text: I18n.tr("panels.user-interface.shadows-description")
            pointSize: Style.fontSizeS
            color: Color.mOnSurfaceVariant
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
          }
        }
        NToggle {
          checked: Settings.data.general.enableShadows
          onToggled: checked => Settings.data.general.enableShadows = checked
        }
      }

      Item {
        Layout.fillWidth: true
        Layout.preferredHeight: Style.marginL
      }
    }
}
