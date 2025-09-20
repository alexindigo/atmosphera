import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets
import qs.Services

ColumnLayout {
  id: root
  spacing: Style.marginM * scaling
  width: 700 * scaling

  // Properties to receive data from parent
  property var widgetData: null
  property var widgetMetadata: null

  // Local state
  property bool valueUsePrimaryColor: widgetData.usePrimaryColor !== undefined ? widgetData.usePrimaryColor : widgetMetadata.usePrimaryColor
  property bool valueUseMonospacedFont: widgetData.useMonospacedFont !== undefined ? widgetData.useMonospacedFont : widgetMetadata.useMonospacedFont
  property string valueLine1: widgetData.line1 !== undefined ? widgetData.line1 : widgetMetadata.line1
  property string valueLine2: widgetData.line2 !== undefined ? widgetData.line2 : widgetMetadata.line2
  property string valueLine3: widgetData.line3 !== undefined ? widgetData.line3 : widgetMetadata.line3
  property string valueLine4: widgetData.line4 !== undefined ? widgetData.line4 : widgetMetadata.line4

  // Track the currently focused input field
  property var focusedInput: null
  property int focusedLineIndex: -1

  readonly property var now: Time.date

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {})
    settings.usePrimaryColor = valueUsePrimaryColor
    settings.useMonospacedFont = valueUseMonospacedFont
    settings.line1 = valueLine1.trim()
    settings.line2 = valueLine2.trim()
    settings.line3 = valueLine3.trim()
    settings.line4 = valueLine4.trim()
    return settings
  }

  // Function to insert token at cursor position in the focused input
  function insertToken(token) {
    if (!focusedInput || !focusedInput.inputItem) {
      // If no input is focused, default to line 1
      if (inputLine1.inputItem) {
        inputLine1.inputItem.focus = true
        focusedInput = inputLine1
        focusedLineIndex = 1
      }
    }

    if (focusedInput && focusedInput.inputItem) {
      var input = focusedInput.inputItem
      var cursorPos = input.cursorPosition
      var currentText = input.text

      // Insert token at cursor position
      var newText = currentText.substring(0, cursorPos) + token + currentText.substring(cursorPos)
      input.text = newText + " "

      // Move cursor after the inserted token
      input.cursorPosition = cursorPos + token.length + 1

      // Ensure the input keeps focus
      input.focus = true
    }
  }

  // Function to update the value property based on which line was edited
  function updateLineValue(lineIndex, text) {
    switch (lineIndex) {
    case 1:
      valueLine1 = text
      break
    case 2:
      valueLine2 = text
      break
    case 3:
      valueLine3 = text
      break
    case 4:
      valueLine4 = text
      break
    }
  }

  NToggle {
    Layout.fillWidth: true
    label: "Use primary color"
    description: "When enabled, this applies the primary color for emphasis."
    checked: valueUsePrimaryColor
    onToggled: checked => valueUsePrimaryColor = checked
  }

  NToggle {
    Layout.fillWidth: true
    label: "Use monospaced font"
    description: "When enabled, the clock will use the monospaced font."
    checked: valueUseMonospacedFont
    onToggled: checked => valueUseMonospacedFont = checked
  }

  NDivider {
    Layout.fillWidth: true
  }

  NHeader {
    label: "Clock format"
    description: "Build your clock display using the tokens below.\nAdditional lines (3 & 4) are only shown in the vertical bar layout.\nClick on any token to insert it into the selected input field."
  }

  RowLayout {
    id: main
    Layout.fillWidth: true
    spacing: Style.marginL * scaling

    ColumnLayout {
      Layout.fillWidth: true
      Layout.preferredWidth: 1 // Equal sizing hint
      spacing: Style.marginM * scaling

      NTextInput {
        id: inputLine1
        Layout.fillWidth: true
        label: "1st line"
        placeholderText: "HH:mm"
        text: valueLine1
        onTextChanged: updateLineValue(1, text)

        // Track focus state
        Component.onCompleted: {
          if (inputItem) {
            inputItem.onActiveFocusChanged.connect(function () {
              if (inputItem.activeFocus) {
                root.focusedInput = inputLine1
                root.focusedLineIndex = 1
              }
            })
          }
        }
      }

      NTextInput {
        id: inputLine2
        Layout.fillWidth: true
        label: "2nd line"
        placeholderText: "ddd MMM d"
        text: valueLine2
        onTextChanged: updateLineValue(2, text)

        // Track focus state
        Component.onCompleted: {
          if (inputItem) {
            inputItem.onActiveFocusChanged.connect(function () {
              if (inputItem.activeFocus) {
                root.focusedInput = inputLine2
                root.focusedLineIndex = 2
              }
            })
          }
        }
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      Layout.preferredWidth: 1 // Equal sizing hint
      spacing: Style.marginM * scaling

      NTextInput {
        id: inputLine3
        Layout.fillWidth: true
        label: "3rd line"
        placeholderText: ""
        text: valueLine3
        onTextChanged: updateLineValue(3, text)

        // Track focus state
        Component.onCompleted: {
          if (inputItem) {
            inputItem.onActiveFocusChanged.connect(function () {
              if (inputItem.activeFocus) {
                root.focusedInput = inputLine3
                root.focusedLineIndex = 3
              }
            })
          }
        }
      }

      NTextInput {
        id: inputLine4
        Layout.fillWidth: true
        label: "4th line"
        placeholderText: ""
        text: valueLine4
        onTextChanged: updateLineValue(4, text)

        // Track focus state
        Component.onCompleted: {
          if (inputItem) {
            inputItem.onActiveFocusChanged.connect(function () {
              if (inputItem.activeFocus) {
                root.focusedInput = inputLine4
                root.focusedLineIndex = 4
              }
            })
          }
        }
      }
    }

    // --------------
    // Preview
    ColumnLayout {
      Layout.alignment: Qt.AlignHCenter | Qt.AlignTop
      Layout.fillWidth: false // Don't stretch this column

      NLabel {
        label: "Preview"
        Layout.alignment: Qt.AlignHCenter | Qt.AlignTop
      }

      Rectangle {
        Layout.preferredWidth: 240 * scaling
        Layout.preferredHeight: 120 * scaling // Fixed height instead of fillHeight

        color: Color.mSurfaceVariant
        radius: Style.radiusM * scaling
        border.color: focusedLineIndex > 0 ? Color.mSecondary : Color.mOutline
        border.width: Math.max(1, Style.borderS * scaling)

        Behavior on border.color {
          ColorAnimation {
            duration: Style.animationFast
          }
        }

        ColumnLayout {
          spacing: -2 * scaling
          anchors.centerIn: parent

          NText {
            visible: text !== ""
            text: Qt.formatDateTime(now, valueLine1.trim())
            font.family: valueUseMonospacedFont ? Settings.data.ui.fontFixed : Settings.data.ui.fontDefault
            font.pointSize: Style.fontSizeM * scaling
            font.weight: Style.fontWeightBold
            color: valueUsePrimaryColor ? Color.mPrimary : Color.mOnSurface
            wrapMode: Text.WordWrap
            Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter

            Behavior on color {
              ColorAnimation {
                duration: Style.animationFast
              }
            }
          }

          NText {
            visible: text !== ""
            text: Qt.formatDateTime(now, valueLine2.trim())
            font.family: valueUseMonospacedFont ? Settings.data.ui.fontFixed : Settings.data.ui.fontDefault
            font.pointSize: Style.fontSizeM * scaling
            font.weight: Style.fontWeightBold
            color: valueUsePrimaryColor ? Color.mPrimary : Color.mOnSurface
            wrapMode: Text.WordWrap
            Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter

            Behavior on color {
              ColorAnimation {
                duration: Style.animationFast
              }
            }
          }

          NText {
            visible: text !== ""
            text: Qt.formatDateTime(now, valueLine3.trim())
            font.family: valueUseMonospacedFont ? Settings.data.ui.fontFixed : Settings.data.ui.fontDefault
            font.pointSize: Style.fontSizeM * scaling
            font.weight: Style.fontWeightBold
            color: valueUsePrimaryColor ? Color.mPrimary : Color.mOnSurface
            wrapMode: Text.WordWrap
            Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
            Layout.topMargin: visible ? Style.marginXS * scaling : 0

            Behavior on color {
              ColorAnimation {
                duration: Style.animationFast
              }
            }
          }

          NText {
            visible: text !== ""
            text: Qt.formatDateTime(now, valueLine4.trim())
            font.family: valueUseMonospacedFont ? Settings.data.ui.fontFixed : Settings.data.ui.fontDefault
            font.pointSize: Style.fontSizeM * scaling
            font.weight: Style.fontWeightBold
            color: valueUsePrimaryColor ? Color.mPrimary : Color.mOnSurface
            wrapMode: Text.WordWrap
            Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter

            Behavior on color {
              ColorAnimation {
                duration: Style.animationFast
              }
            }
          }
        }
      }
    }
  }

  NDivider {
    Layout.topMargin: Style.marginL * scaling
    Layout.bottomMargin: Style.marginL * scaling
  }

  NHeader {
    label: "Tokens"
    description: focusedLineIndex > 0 ? "Click any token to add it to line " + focusedLineIndex : "Select an input field above, then click a token to insert it."
  }

  NDateTimeTokens {
    Layout.fillWidth: true
    height: 400 * scaling

    // Connect to token clicked signal if NDateTimeTokens provides it
    onTokenClicked: token => root.insertToken(token)
  }
}
