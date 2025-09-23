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
      font.pointSize: Style.fontSizeXXL * 1.5 * scaling
      visible: valueIcon !== "" && valueCustomIconPath === ""
    }
  }

  RowLayout {
    spacing: Style.marginM * scaling
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
    onIconSelected: iconName => {
                      valueIcon = iconName
                      valueCustomIconPath = ""
                    }
  }

  NFilePicker {
    id: filePicker
    title: "Select a custom icon"
    onAccepted: paths => valueCustomIconPath = paths[0]
  }
}
