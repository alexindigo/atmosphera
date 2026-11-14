import QtQuick
import qs.Widgets

// A legacy page has local input but no settingsDirty contract.
Column {
  required property var pluginApi
  NTextInput {
    text: parent.pluginApi.pluginSettings.label || ""
  }
}
