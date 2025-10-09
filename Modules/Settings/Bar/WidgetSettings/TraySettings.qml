import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  // Properties to receive data from parent
  property var widgetData: ({}) // Expected by BarWidgetSettingsDialog
  property var widgetMetadata: ({}) // Expected by BarWidgetSettingsDialog

  // Local state for the blacklist
  property var localBlacklist: widgetData.blacklist || Settings.data.bar.trayBlacklist || []

  ListModel {
    id: blacklistModel
  }

  Component.onCompleted: {
    // Populate the ListModel from localBlacklist
    for (var i = 0; i < localBlacklist.length; i++) {
      blacklistModel.append({"rule": localBlacklist[i]})
    }
  }

  spacing: Style.marginM * scaling

  // Input for new blacklist items
  RowLayout {
    Layout.fillWidth: true
    spacing: Style.marginS * scaling

    NTextInput {
      id: newRuleInput
      Layout.fillWidth: true
      placeholderText: I18n.tr("settings.bar.widget-settings.tray.blacklist.placeholder")
    }

    NIconButton {
      icon: "add"
      enabled: newRuleInput.text.length > 0
      onClicked: {
        if (newRuleInput.text.length > 0) {
          var newRule = newRuleInput.text.trim()
          var exists = false
          for (var i = 0; i < blacklistModel.count; i++) {
            if (blacklistModel.get(i).rule === newRule) {
              exists = true
              break
            }
          }
          if (!exists) {
            blacklistModel.append({"rule": newRule})
            newRuleInput.text = ""
          }
        }
      }
    }
  }

  // List of current blacklist items
  ListView {
    Layout.fillWidth: true
    Layout.preferredHeight: 150 * scaling
    clip: true
    model: blacklistModel
    delegate: Rectangle {
        width: ListView.width
        height: 40 * scaling
        color: Color.transparent // Make background transparent
        visible: model.rule !== undefined && model.rule !== "" // Only visible if rule exists
        
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Style.marginM * scaling
            anchors.rightMargin: Style.marginS * scaling
            spacing: Style.marginS * scaling

            NText {
                Layout.fillWidth: true
                text: model.rule
                elide: Text.ElideRight
            }

            NIconButton {
                Layout.alignment: Qt.AlignRight
                icon: "close"
                baseSize: 24 * scaling
                colorBg: Color.transparent
                colorFg: Color.mError
                onClicked: {
                    blacklistModel.remove(index)
                }
            }
        }
    }
  }

  // This function will be called by the dialog to get the new settings
  function saveSettings() {
    var newBlacklist = []
    for (var i = 0; i < blacklistModel.count; i++) {
      newBlacklist.push(blacklistModel.get(i).rule)
    }

    // Return the updated settings for this widget instance
    var settings = Object.assign({}, widgetData || {})
    settings.blacklist = newBlacklist
    return settings
  }
}