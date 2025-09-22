import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets
import qs.Services

ColumnLayout {
  id: root
  spacing: Style.marginM * scaling

  // Properties to receive data from parent
  property var widgetData: null
  property var widgetMetadata: null

  // Local state
  property string valueIcon: widgetData.icon !== undefined ? widgetData.icon : widgetMetadata.icon
  property bool valueUseDistroLogo: widgetData.useDistroLogo !== undefined ? widgetData.useDistroLogo : widgetMetadata.useDistroLogo
  property string valueCustomIconPath: widgetData.customIconPath !== undefined ? widgetData.customIconPath : ""

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {})
    settings.icon = valueIcon
    settings.useDistroLogo = valueUseDistroLogo
    settings.customIconPath = valueCustomIconPath
    return settings
  }

  NToggle {
    label: "Use distro logo instead of icon"
    checked: valueUseDistroLogo
    onToggled: {
      valueUseDistroLogo = checked
      if (checked) {
        valueCustomIconPath = ""
        valueIcon = ""
      }
    }
  }

  NFilePicker {
    id: filePicker
    title: "Select a custom icon"
    onFileSelected: function (filePath) {
      valueCustomIconPath = "file://" + filePath
    }
  }

  RowLayout {
    spacing: Style.marginM * scaling

    NLabel {
      label: "Icon"
      description: "Select an icon from the library or a custom file."
    }

    NImageCircled {
      Layout.alignment: Qt.AlignVCenter
      imagePath: valueCustomIconPath
      visible: valueCustomIconPath !== ""
      width: Style.fontSizeXL * 2 * scaling
      height: Style.fontSizeXL * 2 * scaling
    }

    NIcon {
      Layout.alignment: Qt.AlignVCenter
      icon: valueIcon
      font.pointSize: Style.fontSizeXL * scaling
      visible: valueIcon !== "" && valueCustomIconPath === ""
    }

    NButton {
      enabled: !valueUseDistroLogo
      text: "Browse Library"
      onClicked: iconPicker.open()
    }

    NButton {
      enabled: !valueUseDistroLogo
      text: "Browse File"
      onClicked: filePicker.open()
    }
  }

  NIconPicker {
    id: iconPicker
    initialIcon: valueIcon
    onIconSelected: function (iconName) {
      valueIcon = iconName
      valueCustomIconPath = ""
    }
  }
}