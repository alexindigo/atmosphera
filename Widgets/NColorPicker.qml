import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

Rectangle {
  id: root

  property color selectedColor: "#000000"
  property bool expanded: false
  property real scaling: 1.0
  property real currentHue: 0
  property real currentSaturation: 0

  signal colorSelected(color color)
  signal colorCancelled

  implicitWidth: 150 * scaling
  implicitHeight: 40 * scaling

  radius: Style.radiusM
  color: Color.mSurface
  border.color: Color.mOutline
  border.width: Math.max(1, Style.borderS)

  function rgbToHsv(r, g, b) {
    r /= 255
    g /= 255
    b /= 255
    var max = Math.max(r, g, b), min = Math.min(r, g, b)
    var h, s, v = max
    var d = max - min
    s = max === 0 ? 0 : d / max
    if (max === min) {
      h = 0
    } else {
      switch (max) {
      case r:
        h = (g - b) / d + (g < b ? 6 : 0)
        break
      case g:
        h = (b - r) / d + 2
        break
      case b:
        h = (r - g) / d + 4
        break
      }
      h /= 6
    }
    return [h * 360, s * 100, v * 100]
  }

  function hsvToRgb(h, s, v) {
    h /= 360
    s /= 100
    v /= 100
    var r, g, b
    var i = Math.floor(h * 6)
    var f = h * 6 - i
    var p = v * (1 - s)
    var q = v * (1 - f * s)
    var t = v * (1 - (1 - f) * s)
    switch (i % 6) {
    case 0:
      r = vg = tb = p
      break
    case 1:
      r = qg = vb = p
      break
    case 2:
      r = pg = vb = t
      break
    case 3:
      r = pg = qb = v
      break
    case 4:
      r = tg = pb = v
      break
    case 5:
      r = vg = pb = q
      break
    }
    return [Math.round(r * 255), Math.round(g * 255), Math.round(b * 255)]
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: colorPickerPopup.open()

    RowLayout {
      anchors.fill: parent
      anchors.margins: Style.marginS
      spacing: Style.marginS

      Rectangle {
        Layout.preferredWidth: 24
        Layout.preferredHeight: 24
        radius: Layout.preferredWidth * 0.5
        color: root.selectedColor
        border.color: Color.mOutline
        border.width: Math.max(1, Style.borderS)
      }

      NText {
        text: root.selectedColor.toString().toUpperCase()
        font.family: Settings.data.ui.fontFixed
        Layout.fillWidth: true
      }

      NIcon {
        text: "palette"
        color: Color.mOnSurfaceVariant
      }
    }
  }

  Popup {
    id: colorPickerPopup

    width: 580 * scaling
    height: 750 * scaling
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    modal: true
    clip: true

    background: Rectangle {
      color: Color.mSurface
      radius: 12 * scaling
      border.color: Color.mPrimary
      border.width: 2 * scaling
    }

    ScrollView {
      id: scrollView
      anchors.fill: parent
      anchors.margins: 24 * scaling

      ScrollBar.vertical.policy: ScrollBar.AlwaysOff
      ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
      clip: true

      ColumnLayout {
        width: scrollView.availableWidth
        spacing: 20 * scaling

        // Header
        RowLayout {
          Layout.fillWidth: true
          Layout.topMargin: 10 * scaling

          RowLayout {
            spacing: 8 * scaling

            NIcon {
              text: "palette"
              font.pointSize: 20 * scaling
              color: Color.mPrimary
            }

            NText {
              text: "Color Picker"
              font.pointSize: 20 * scaling
              font.weight: Font.Bold
              color: Color.mPrimary
            }
          }

          Item {
            Layout.fillWidth: true
          }

          NIconButton {
            icon: "close"
            onClicked: colorPickerPopup.close()
          }
        }

        // Color preview section
        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 100 * scaling
          radius: 8 * scaling
          color: root.selectedColor
          border.color: Color.mOutline
          border.width: 1 * scaling

          ColumnLayout {
            anchors.centerIn: parent
            spacing: 5 * scaling

            NText {
              text: root.selectedColor.toString().toUpperCase()
              font.family: Settings.data.ui.fontFixed
              font.pointSize: 18 * scaling
              font.weight: Font.Bold
              color: root.selectedColor.r + root.selectedColor.g + root.selectedColor.b > 1.5 ? "#000000" : "#FFFFFF"
              horizontalAlignment: Text.AlignHCenter
            }

            NText {
              text: "RGB(" + Math.round(root.selectedColor.r * 255) + ", " + Math.round(
                      root.selectedColor.g * 255) + ", " + Math.round(root.selectedColor.b * 255) + ")"
              font.family: Settings.data.ui.fontFixed
              font.pointSize: 12 * scaling
              color: root.selectedColor.r + root.selectedColor.g + root.selectedColor.b > 1.5 ? "#000000" : "#FFFFFF"
              horizontalAlignment: Text.AlignHCenter
            }
          }
        }

        NDivider {
          Layout.fillWidth: true
        }

        // Hex input
        ColumnLayout {
          Layout.fillWidth: true
          spacing: 8 * scaling

          NLabel {
            label: "Hex Color"
            description: "Enter a hexadecimal color code"
            Layout.fillWidth: true
          }

          NTextInput {
            text: root.selectedColor.toString().toUpperCase()
            fontFamily: Settings.data.ui.fontFixed
            Layout.fillWidth: true
            onEditingFinished: {
              if (/^#[0-9A-F]{6}$/i.test(text)) {
                root.selectedColor = text
              }
            }
          }
        }

        NDivider {
          Layout.fillWidth: true
        }

        // RGB sliders section
        NBox {
          Layout.fillWidth: true
          Layout.preferredHeight: 240 * scaling

          ColumnLayout {
            anchors.fill: parent
            anchors.margins: 15 * scaling
            spacing: 10 * scaling

            NLabel {
              label: "RGB Values"
              description: "Adjust red, green, blue, and brightness values"
              Layout.fillWidth: true
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: 15 * scaling

              NText {
                text: "R"
                font.weight: Font.Bold
                Layout.preferredWidth: 20 * scaling
              }

              NSlider {
                id: redSlider
                Layout.fillWidth: true
                from: 0
                to: 255
                value: Math.round(root.selectedColor.r * 255)
                onMoved: {
                  root.selectedColor = Qt.rgba(value / 255, root.selectedColor.g, root.selectedColor.b, 1)
                  var hsv = root.rgbToHsv(root.selectedColor.r * 255, root.selectedColor.g * 255,
                                          root.selectedColor.b * 255)
                  root.currentHue = hsv[0]
                  root.currentSaturation = hsv[1]
                }
              }

              NText {
                text: Math.round(redSlider.value)
                font.family: Settings.data.ui.fontFixed
                Layout.preferredWidth: 30 * scaling
              }
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: 15 * scaling

              NText {
                text: "G"
                font.weight: Font.Bold
                Layout.preferredWidth: 20 * scaling
              }

              NSlider {
                id: greenSlider
                Layout.fillWidth: true
                from: 0
                to: 255
                value: Math.round(root.selectedColor.g * 255)
                onMoved: {
                  root.selectedColor = Qt.rgba(root.selectedColor.r, value / 255, root.selectedColor.b, 1)
                  // Update stored hue and saturation when RGB changes
                  var hsv = root.rgbToHsv(root.selectedColor.r * 255, root.selectedColor.g * 255,
                                          root.selectedColor.b * 255)
                  root.currentHue = hsv[0]
                  root.currentSaturation = hsv[1]
                }
              }

              NText {
                text: Math.round(greenSlider.value)
                font.family: Settings.data.ui.fontFixed
                Layout.preferredWidth: 30 * scaling
              }
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: 15 * scaling

              NText {
                text: "B"
                font.weight: Font.Bold
                Layout.preferredWidth: 20 * scaling
              }

              NSlider {
                id: blueSlider
                Layout.fillWidth: true
                from: 0
                to: 255
                value: Math.round(root.selectedColor.b * 255)
                onMoved: {
                  root.selectedColor = Qt.rgba(root.selectedColor.r, root.selectedColor.g, value / 255, 1)
                  // Update stored hue and saturation when RGB changes
                  var hsv = root.rgbToHsv(root.selectedColor.r * 255, root.selectedColor.g * 255,
                                          root.selectedColor.b * 255)
                  root.currentHue = hsv[0]
                  root.currentSaturation = hsv[1]
                }
              }

              NText {
                text: Math.round(blueSlider.value)
                font.family: Settings.data.ui.fontFixed
                Layout.preferredWidth: 30 * scaling
              }
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: 15 * scaling

              NText {
                text: "Brightness"
                font.weight: Font.Bold
                Layout.preferredWidth: 80 * scaling
              }

              NSlider {
                id: brightnessSlider
                Layout.fillWidth: true
                from: 0
                to: 100
                value: {
                  var hsv = root.rgbToHsv(root.selectedColor.r * 255, root.selectedColor.g * 255,
                                          root.selectedColor.b * 255)
                  return hsv[2]
                }
                onMoved: {
                  var hue = root.currentHue
                  var saturation = root.currentSaturation

                  if (hue === 0 && saturation === 0) {
                    var hsv = root.rgbToHsv(root.selectedColor.r * 255, root.selectedColor.g * 255,
                                            root.selectedColor.b * 255)
                    hue = hsv[0]
                    saturation = hsv[1]
                    root.currentHue = hue
                    root.currentSaturation = saturation
                  }

                  var rgb = root.hsvToRgb(hue, saturation, value)
                  root.selectedColor = Qt.rgba(rgb[0] / 255, rgb[1] / 255, rgb[2] / 255, 1)
                }
              }

              NText {
                text: Math.round(brightnessSlider.value) + "%"
                font.family: Settings.data.ui.fontFixed
                Layout.preferredWidth: 40 * scaling
              }
            }
          }
        }

        NDivider {
          Layout.fillWidth: true
        }

        NBox {
          Layout.fillWidth: true
          Layout.preferredHeight: 120 * scaling

          ColumnLayout {
            anchors.fill: parent
            anchors.margins: 15 * scaling
            spacing: 10 * scaling

            NLabel {
              label: "Theme Colors"
              description: "Quick access to your theme's color palette"
              Layout.fillWidth: true
            }

            Flow {
              spacing: 6 * scaling
              Layout.fillWidth: true
              flow: Flow.LeftToRight

              Repeater {
                model: [Color.mPrimary, Color.mSecondary, Color.mTertiary, Color.mError, Color.mSurface, Color.mSurfaceVariant, Color.mOutline, "#FFFFFF", "#000000"]

                Rectangle {
                  width: 24 * scaling
                  height: 24 * scaling
                  radius: 4 * scaling
                  color: modelData
                  border.color: root.selectedColor === modelData ? Color.mPrimary : Color.mOutline
                  border.width: root.selectedColor === modelData ? 2 * scaling : 1 * scaling

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      root.selectedColor = modelData
                      var hsv = root.rgbToHsv(root.selectedColor.r * 255, root.selectedColor.g * 255,
                                              root.selectedColor.b * 255)
                      root.currentHue = hsv[0]
                      root.currentSaturation = hsv[1]
                    }
                  }
                }
              }
            }
          }
        }

        NDivider {
          Layout.fillWidth: true
        }

        NBox {
          Layout.fillWidth: true
          Layout.preferredHeight: 170 * scaling

          ColumnLayout {
            anchors.fill: parent
            anchors.margins: 15 * scaling
            spacing: 10 * scaling

            NLabel {
              label: "Color Palettes"
              description: "Choose from a wide range of predefined colors"
              Layout.fillWidth: true
            }

            Flow {
              Layout.fillWidth: true
              Layout.fillHeight: true
              spacing: 6 * scaling
              flow: Flow.LeftToRight

              Repeater {
                model: ["#F44336", "#E91E63", "#9C27B0", "#673AB7", "#3F51B5", "#2196F3", "#03A9F4", "#00BCD4", "#009688", "#4CAF50", "#8BC34A", "#CDDC39", "#FFEB3B", "#FFC107", "#FF9800", "#FF5722", "#795548", "#9E9E9E", "#E74C3C", "#C0392B", "#E67E22", "#D35400", "#F39C12", "#F1C40F", "#2ECC71", "#27AE60", "#1ABC9C", "#16A085", "#3498DB", "#2980B9", "#9B59B6", "#8E44AD", "#34495E", "#2C3E50", "#95A5A6", "#7F8C8D", "#FFFFFF", "#000000"]

                Rectangle {
                  width: 24 * scaling
                  height: 24 * scaling
                  radius: 4 * scaling
                  color: modelData
                  border.color: root.selectedColor === modelData ? Color.mPrimary : Color.mOutline
                  border.width: root.selectedColor === modelData ? 2 * scaling : 1 * scaling

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      root.selectedColor = modelData
                      var hsv = root.rgbToHsv(root.selectedColor.r * 255, root.selectedColor.g * 255,
                                              root.selectedColor.b * 255)
                      root.currentHue = hsv[0]
                      root.currentSaturation = hsv[1]
                    }
                  }
                }
              }
            }
          }
        }

        RowLayout {
          Layout.fillWidth: true
          Layout.topMargin: 20 * scaling
          Layout.bottomMargin: 20 * scaling
          spacing: 10 * scaling

          Item {
            Layout.fillWidth: true
          }

          NButton {
            text: "Cancel"
            icon: "close"
            outlined: true
            customHeight: 36 * scaling
            customWidth: 100 * scaling
            onClicked: {
              root.colorCancelled()
              colorPickerPopup.close()
            }
          }

          NButton {
            text: "Apply"
            icon: "check"
            customHeight: 36 * scaling
            customWidth: 100 * scaling
            onClicked: {
              root.colorSelected(root.selectedColor)
              colorPickerPopup.close()
            }
          }
        }
      }
    }
  }

  NSlider {
    id: hueSlider
    visible: false
    from: 0
    to: 360
    value: {
      var hsv = root.rgbToHsv(root.selectedColor.r * 255, root.selectedColor.g * 255, root.selectedColor.b * 255)
      return hsv[0]
    }
  }

  NSlider {
    id: saturationSlider
    visible: false
    from: 0
    to: 100
    value: {
      var hsv = root.rgbToHsv(root.selectedColor.r * 255, root.selectedColor.g * 255, root.selectedColor.b * 255)
      return hsv[1]
    }
  }
}
