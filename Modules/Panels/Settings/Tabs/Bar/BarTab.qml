import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "../../../../../Helpers/SectionWidgetCommands.js" as SectionCommands
import qs.Commons
import qs.Services.Plugins
import qs.Services.UI
import qs.Widgets

ColumnLayout {
  id: root
  spacing: 0

  // Helper functions to update arrays immutably
  function addMonitor(list, name) {
    const arr = (list || []).slice();
    if (!arr.includes(name))
      arr.push(name);
    return arr;
  }
  function removeMonitor(list, name) {
    return (list || []).filter(function (n) {
      return n !== name;
    });
  }

  // Signal functions for widgets sub-tab (global widgets only).
  // These intentionally edit Settings.data.bar.widgets (global defaults),
  // not per-screen overrides. Per-screen editing is handled by MonitorWidgetsConfig.qml.
  function _addWidgetToSection(widgetId, section) {
    var newWidget = {
      "id": widgetId
    };
    if (BarWidgetRegistry.widgetHasUserSettings(widgetId)) {
      var metadata = BarWidgetRegistry.widgetMetadata[widgetId];
      if (metadata) {
        Object.keys(metadata).forEach(function (key) {
          newWidget[key] = metadata[key];
        });
      }
    }
    var editor = Settings.createRecordListEditor(["bar", "widgets", section], []);
    if (!editor)
      return false;
    return editor.submit([
                           {
                             op: "insert",
                             index: editor.initialValue.length,
                             value: newWidget
                           }
                         ], function (result) {
                           if (result.status === "admitted" && result.refreshState === "current")
                             BarService.widgetsRevision++;
                           editor.detach();
                         });
  }

  // Capture this before a menu/drag delay; the three global lists are explicit
  // owning leaves, independent of per-monitor display routing.
  function captureWidgetInteraction(section, index) {
    var sections = [
          {
            id: "left",
            path: ["bar", "widgets", "left"],
            listAddress: [],
            length: Settings.data.bar.widgets.left.length
          },
          {
            id: "center",
            path: ["bar", "widgets", "center"],
            listAddress: [],
            length: Settings.data.bar.widgets.center.length
          },
          {
            id: "right",
            path: ["bar", "widgets", "right"],
            listAddress: [],
            length: Settings.data.bar.widgets.right.length
          }
        ];
    return SectionCommands.capture({
                                     sections: sections,
                                     createEditor: function (path, address, targets) {
                                       return Settings.createRecordListEditor(path, address, targets);
                                     },
                                     later: function (callback) {
                                       Qt.callLater(callback);
                                     },
                                     onChanged: function (action, initial) {
                                       BarService.widgetsRevision++;
                                       if (action === "remove" && initial.id === "ControlCenter" && BarService.lookupWidget("ControlCenter") === undefined)
                                         ToastService.showWarning(I18n.tr("toast.missing-control-center.label"), I18n.tr("toast.missing-control-center.description"), 6000);
                                     }
                                   }, section, index);
  }

  function _submitWidgetInteraction(section, index, action, destination) {
    var interaction = root.captureWidgetInteraction(section, index);
    if (!interaction)
      return false;
    return interaction.submit(action, destination, function (result) {
      if (result.status !== "admitted" || result.refreshState !== "current")
        Logger.w("BarTab", "Widget command refused", result.error?.code || "list-edit-conflict");
      interaction.detach();
    });
  }

  function _removeWidgetFromSection(section, index) {
    return root._submitWidgetInteraction(section, index, "remove", null);
  }

  function _reorderWidgetInSection(section, fromIndex, toIndex) {
    return root._submitWidgetInteraction(section, fromIndex, "reorder", toIndex);
  }

  // Note: _updateWidgetSettingsInSection does NOT increment revision
  // because it only changes settings, not widget structure
  function _updateWidgetSettingsInSection(section, index, settings) {
    return BarService.updateWidgetSettings("", section, index, settings, function (result) {
      if (result.status === "failed")
        Logger.w("BarTab", "Widget settings save failed", result.error?.code || "save-failed");
    });
  }

  function _moveWidgetBetweenSections(fromSection, index, toSection) {
    return root._submitWidgetInteraction(fromSection, index, "move", toSection);
  }

  function getWidgetLocations(widgetId) {
    if (!BarService)
      return [];
    const instances = BarService.getAllRegisteredWidgets();
    const locations = {};
    for (var i = 0; i < instances.length; i++) {
      if (instances[i].widgetId === widgetId) {
        const section = instances[i].section;
        if (section === "left")
          locations["arrow-bar-to-left"] = true;
        else if (section === "center")
          locations["layout-columns"] = true;
        else if (section === "right")
          locations["arrow-bar-to-right"] = true;
      }
    }
    return Object.keys(locations);
  }

  function createBadges(isPlugin, locations) {
    const badges = [];
    if (isPlugin) {
      badges.push({
                    "color": AtmoColor.mSecondary
                  });
    }
    locations.forEach(function (location) {
      badges.push({
                    "icon": location,
                    "color": AtmoColor.mOnSurfaceVariant
                  });
    });
    return badges;
  }

  function updateAvailableWidgetsModel() {
    availableWidgets.clear();
    const widgets = BarWidgetRegistry.getAvailableWidgets();
    widgets.forEach(entry => {
      const isPlugin = BarWidgetRegistry.isPluginWidget(entry);
      let displayName = entry;
      if (isPlugin) {
        const pluginId = entry.replace("plugin:", "");
        const manifest = Registry.getPluginManifest(pluginId);
        if (manifest && manifest.name) {
          displayName = manifest.name;
        } else {
          displayName = pluginId;
        }
      }
      availableWidgets.append({
                                "key": entry,
                                "name": displayName,
                                "badges": createBadges(isPlugin, getWidgetLocations(entry))
                              });
    });
  }

  ListModel {
    id: availableWidgets
  }

  Component.onCompleted: {
    Qt.callLater(updateAvailableWidgetsModel);
  }

  Connections {
    target: BarService
    function onActiveWidgetsChanged() {
      updateAvailableWidgetsModel();
    }
  }

  Connections {
    target: BarWidgetRegistry
    function onPluginWidgetRegistryUpdated() {
      updateAvailableWidgetsModel();
    }
  }

  Connections {
    target: Settings.data.bar
    function onPositionChanged() {
      if (Settings.data.bar.position === "none" && (tabView.currentIndex === 1 || tabView.currentIndex === 2))
        tabView.currentIndex = 0;
    }
  }

  NTabBar {
    id: subTabBar
    Layout.fillWidth: true
    Layout.bottomMargin: Style.marginM
    distributeEvenly: true
    currentIndex: tabView.currentIndex

    NTabButton {
      text: I18n.tr("common.appearance")
      tabIndex: 0
      checked: subTabBar.currentIndex === 0
    }
    NTabButton {
      text: I18n.tr("common.widgets")
      tabIndex: 1
      enabled: Settings.data.bar.position !== "none"
      checked: subTabBar.currentIndex === 1
    }
    NTabButton {
      text: I18n.tr("common.behavior")
      tabIndex: 2
      enabled: Settings.data.bar.position !== "none"
      checked: subTabBar.currentIndex === 2
    }
    NTabButton {
      text: I18n.tr("common.monitors")
      tabIndex: 3
      checked: subTabBar.currentIndex === 3
    }
  }

  Item {
    Layout.fillWidth: true
    Layout.preferredHeight: Style.marginS
  }

  NTabView {
    id: tabView
    currentIndex: {
      if (Settings.data.bar.position === "none" && (subTabBar.currentIndex === 1 || subTabBar.currentIndex === 2))
        return 0;
      return subTabBar.currentIndex;
    }

    AppearanceSubTab {}
    WidgetsSubTab {
      availableWidgets: availableWidgets
      captureWidgetInteraction: root.captureWidgetInteraction
      captureWidgetSettings: function (section, index) {
        return BarService.createWidgetSettingsEditor("", section, index);
      }
      addWidgetToSection: root._addWidgetToSection
      removeWidgetFromSection: root._removeWidgetFromSection
      reorderWidgetInSection: root._reorderWidgetInSection
      updateWidgetSettingsInSection: root._updateWidgetSettingsInSection
      moveWidgetBetweenSections: root._moveWidgetBetweenSections
      onOpenPluginSettings: (manifest, settingsEntryPoint, section, index) => root._openInstanceSettings(manifest, settingsEntryPoint, section, index)
    }
    BehaviorSubTab {}
    MonitorsSubTab {
      addMonitor: root.addMonitor
      removeMonitor: root.removeMonitor
    }
  }

  // Opens the settings of the plugin instance at a global bar placement (plugin-instances design, 4).
  function _openInstanceSettings(manifest, settingsEntryPoint, section, index) {
    var placement = {
      "kind": "bar",
      "list": "global",
      "section": section,
      "index": index
    };
    pluginSettingsDialog.openInstanceSettings(manifest, PluginInstances.apiFor(manifest.compositeKey || manifest.id, placement), settingsEntryPoint);
  }

  NPluginSettingsPopup {
    id: pluginSettingsDialog
    parent: Overlay.overlay
    showToastOnSave: false
  }
}
