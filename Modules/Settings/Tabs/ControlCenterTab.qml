import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets
import qs.Modules.Settings.Extras

ColumnLayout {
  id: root
  spacing: Style.marginL

  // Handler for drag start - disables panel background clicks
  function handleDragStart() {
    var panel = PanelService.getPanel("settingsPanel")
    if (panel && panel.disableBackgroundClick) {
      panel.disableBackgroundClick()
    }
  }

  // Handler for drag end - re-enables panel background clicks
  function handleDragEnd() {
    var panel = PanelService.getPanel("settingsPanel")
    if (panel && panel.enableBackgroundClick) {
      panel.enableBackgroundClick()
    }
  }

  ColumnLayout {
    spacing: Style.marginL
    Layout.fillWidth: true

    NHeader {
      label: I18n.tr("settings.control-center.section.label")
      description: I18n.tr("settings.control-center.section.description")
    }

    NComboBox {
      id: controlCenterPosition
      label: I18n.tr("settings.control-center.position.label")
      description: I18n.tr("settings.control-center.position.description")
      Layout.fillWidth: true
      model: [{
          "key": "close_to_bar_button",
          "name": I18n.tr("options.control-center.position.close_to_bar_button")
        }, {
          "key": "top_left",
          "name": I18n.tr("options.control-center.position.top_left")
        }, {
          "key": "top_right",
          "name": I18n.tr("options.control-center.position.top_right")
        }, {
          "key": "bottom_left",
          "name": I18n.tr("options.control-center.position.bottom_left")
        }, {
          "key": "bottom_right",
          "name": I18n.tr("options.control-center.position.bottom_right")
        }, {
          "key": "bottom_center",
          "name": I18n.tr("options.control-center.position.bottom_center")
        }, {
          "key": "top_center",
          "name": I18n.tr("options.control-center.position.top_center")
        }]
      currentKey: Settings.data.controlCenter.position
      onSelected: function (key) {
        Settings.data.controlCenter.position = key
      }
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginXL
    Layout.bottomMargin: Style.marginXL
  }

  // // Quick Settings Style Section
  // ColumnLayout {
  //   spacing: Style.marginL
  //   Layout.fillWidth: true

  //   NHeader {
  //     label: I18n.tr("settings.control-center.quickSettingsStyle.section.label")
  //     description: I18n.tr("settings.control-center.quickSettingsStyle.section.description")
  //   }

  //   NComboBox {
  //     id: quickSettingsStyle
  //     label: I18n.tr("settings.control-center.quickSettingsStyle.style.label")
  //     description: I18n.tr("settings.control-center.quickSettingsStyle.style.description")
  //     Layout.fillWidth: true
  //     model: [{
  //         "key": "compact",
  //         "name": I18n.tr("options.control-center.quickSettingsStyle.compact")
  //       }, {
  //         "key": "classic",
  //         "name": I18n.tr("options.control-center.quickSettingsStyle.classic")
  //       }, {
  //         "key": "modern",
  //         "name": I18n.tr("options.control-center.quickSettingsStyle.modern")
  //       }]
  //     currentKey: Settings.data.controlCenter.quickSettingsStyle || "compact"
  //     onSelected: function (key) {
  //       Settings.data.controlCenter.quickSettingsStyle = key
  //     }
  //   }
  // }

  // NDivider {
  //   Layout.fillWidth: true
  //   Layout.topMargin: Style.marginXL
  //   Layout.bottomMargin: Style.marginXL
  // }

  // // Widgets Management Section
  // ColumnLayout {
  //   spacing: Style.marginXXS
  //   Layout.fillWidth: true

  //   NHeader {
  //     label: I18n.tr("settings.control-center.widgets.section.label")
  //     description: I18n.tr("settings.control-center.widgets.section.description")
  //   }

  //   // Bar Sections
  //   ColumnLayout {
  //     Layout.fillWidth: true
  //     Layout.fillHeight: true
  //     Layout.topMargin: Style.marginM
  //     spacing: Style.marginM

  //     // Quick Settings
  //     SectionEditor {
  //       sectionName: I18n.tr("settings.control-center.quickSettings.sectionName")
  //       sectionId: "quickSettings"
  //       settingsDialogComponent: ""
  //       widgetRegistry: ControlCenterWidgetRegistry
  //       widgetModel: Settings.data.controlCenter.widgets["quickSettings"]
  //       availableWidgets: availableWidgets
  //       enableMoveBetweenSections: false
  //       onAddWidget: (widgetId, section) => _addWidgetToSection(widgetId, section)
  //       onRemoveWidget: (section, index) => _removeWidgetFromSection(section, index)
  //       onReorderWidget: (section, fromIndex, toIndex) => _reorderWidgetInSection(section, fromIndex, toIndex)
  //       onUpdateWidgetSettings: (section, index, settings) => _updateWidgetSettingsInSection(section, index, settings)
  //       onDragPotentialStarted: root.handleDragStart()
  //       onDragPotentialEnded: root.handleDragEnd()
  //     }
  //   }
  // }

  // NDivider {
  //   Layout.fillWidth: true
  //   Layout.topMargin: Style.marginXL
  //   Layout.bottomMargin: Style.marginXL
  // }

  // ---------------------------------
  // Signal functions
  // ---------------------------------
  function _addWidgetToSection(widgetId, section) {
    var newWidget = {
      "id": widgetId
    }
    if (ControlCenterWidgetRegistry.widgetHasUserSettings(widgetId)) {
      var metadata = ControlCenterWidgetRegistry.widgetMetadata[widgetId]
      if (metadata) {
        Object.keys(metadata).forEach(function (key) {
          if (key !== "allowUserSettings") {
            newWidget[key] = metadata[key]
          }
        })
      }
    }
    Settings.data.controlCenter.widgets[section].push(newWidget)
  }

  function _removeWidgetFromSection(section, index) {
    if (index >= 0 && index < Settings.data.controlCenter.widgets[section].length) {
      var newArray = Settings.data.controlCenter.widgets[section].slice()
      var removedWidgets = newArray.splice(index, 1)
      Settings.data.controlCenter.widgets[section] = newArray

      // Check that we still have a control center
      if (removedWidgets[0].id === "ControlCenter" && BarService.lookupWidget("ControlCenter") === undefined) {
        ToastService.showWarning(I18n.tr("toast.missing-control-center.label"), I18n.tr("toast.missing-control-center.description"), 12000)
      }
    }
  }

  function _reorderWidgetInSection(section, fromIndex, toIndex) {
    if (fromIndex >= 0 && fromIndex < Settings.data.controlCenter.widgets[section].length && toIndex >= 0 && toIndex < Settings.data.controlCenter.widgets[section].length) {

      // Create a new array to avoid modifying the original
      var newArray = Settings.data.controlCenter.widgets[section].slice()
      var item = newArray[fromIndex]
      newArray.splice(fromIndex, 1)
      newArray.splice(toIndex, 0, item)

      Settings.data.controlCenter.widgets[section] = newArray
      //Logger.log("BarTab", "Widget reordered. New array:", JSON.stringify(newArray))
    }
  }

  function _updateWidgetSettingsInSection(section, index, settings) {
    // Update the widget settings in the Settings data
    Settings.data.controlCenter.widgets[section][index] = settings
    //Logger.log("BarTab", `Updated widget settings for ${settings.id} in ${section} section`)
  }

  // Base list model for all combo boxes
  ListModel {
    id: availableWidgets
  }

  Component.onCompleted: {
    // Fill out availableWidgets ListModel
    availableWidgets.clear()
    ControlCenterWidgetRegistry.getAvailableWidgets().forEach(entry => {
                                                                availableWidgets.append({
                                                                                          "key": entry,
                                                                                          "name": entry
                                                                                        })
                                                              })
  }
}
