import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginM

  property var widgetData: null
  property var widgetMetadata: null

  property bool valueShowBackground: widgetData.showBackground !== undefined ? widgetData.showBackground : (widgetMetadata ? widgetMetadata.showBackground : true)
  property string valueClockStyle: {
    // If clockStyle is "minimal", default to "digital" for the combo box
    var style = widgetData.clockStyle !== undefined ? widgetData.clockStyle : "digital";
    return style === "minimal" ? "digital" : style;
  }
  property bool valueMinimalMode: {
    // Check if minimalMode is set, or if clockStyle is "minimal"
    if (widgetData.minimalMode !== undefined) {
      return widgetData.minimalMode;
    }
    return widgetData.clockStyle === "minimal";
  }
  property bool valueShowMonthName: widgetData.showMonthName !== undefined ? widgetData.showMonthName : true

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {});
    settings.showBackground = valueShowBackground;
    if (valueMinimalMode) {
      settings.clockStyle = "minimal";
    } else {
      settings.clockStyle = valueClockStyle;
    }
    settings.minimalMode = valueMinimalMode;
    settings.showMonthName = valueShowMonthName;
    return settings;
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("settings.desktop-widgets.clock.minimal-mode.label")
    description: I18n.tr("settings.desktop-widgets.clock.minimal-mode.description")
    checked: valueMinimalMode
    onToggled: checked => valueMinimalMode = checked
  }

  NComboBox {
    Layout.fillWidth: true
    visible: !valueMinimalMode
    label: I18n.tr("settings.desktop-widgets.clock.style.label")
    description: I18n.tr("settings.desktop-widgets.clock.style.description")
    currentKey: valueClockStyle
    minimumWidth: 260 * Style.uiScaleRatio
    model: [
      {
        "key": "digital",
        "name": I18n.tr("settings.desktop-widgets.clock.style.digital")
      },
      {
        "key": "analog",
        "name": I18n.tr("settings.desktop-widgets.clock.style.analog")
      }
    ]
    onSelected: key => valueClockStyle = key
  }

  NToggle {
    Layout.fillWidth: true
    visible: valueMinimalMode
    label: I18n.tr("settings.desktop-widgets.clock.show-month-name.label")
    description: I18n.tr("settings.desktop-widgets.clock.show-month-name.description")
    checked: valueShowMonthName
    onToggled: checked => valueShowMonthName = checked
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("settings.desktop-widgets.clock.show-background.label")
    description: I18n.tr("settings.desktop-widgets.clock.show-background.description")
    checked: valueShowBackground
    onToggled: checked => valueShowBackground = checked
  }
}
