import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "../../../../../Helpers/SectionWidgetCommands.js" as SectionCommands
import qs.Commons
import qs.Services.Plugins
import qs.Services.System
import qs.Services.UI
import qs.Widgets

ColumnLayout {
  id: root
  spacing: 0

  property list<var> cardsModel: []
  property list<var> cardsDefault: [
    {
      "id": "profile-card",
      "text": "Profile",
      "enabled": true,
      "required": true
    },
    {
      "id": "shortcuts-card",
      "text": "Shortcuts",
      "enabled": true,
      "required": false
    },
    {
      "id": "audio-card",
      "text": "Audio Sliders",
      "enabled": true,
      "required": false
    },
    {
      "id": "brightness-card",
      "text": "Brightness",
      "enabled": false,
      "required": false
    },
    {
      "id": "weather-card",
      "text": "Weather",
      "enabled": true,
      "required": false
    },
    {
      "id": "media-sysmon-card",
      "text": "Media and System Monitor",
      "enabled": true,
      "required": false
    }
  ]

  // Fill out availableWidgets ListModel from the registry
  function updateAvailableWidgetsModel() {
    availableWidgets.clear();
    var sortedEntries = ControlCenterWidgetRegistry.getAvailableWidgets().slice().sort();
    sortedEntries.forEach(entry => {
      const isPlugin = ControlCenterWidgetRegistry.isPluginWidget(entry);
      let displayName = entry;
      let badges = [];
      if (isPlugin) {
        const pluginId = entry.replace("plugin:", "");
        const manifest = Registry.getPluginManifest(pluginId);
        if (manifest && manifest.name) {
          displayName = manifest.name;
        } else {
          displayName = pluginId;
        }
        badges.push({
                      "color": AtmoColor.mSecondary
                    });
      }
      availableWidgets.append({
                                "key": entry,
                                "name": displayName,
                                "badges": badges
                              });
    });
  }

  // Plugin control-center widgets can register while this tab is open
  Connections {
    target: ControlCenterWidgetRegistry
    function onPluginWidgetRegistryUpdated() {
      root.updateAvailableWidgetsModel();
    }
  }

  Component.onCompleted: {
    updateAvailableWidgetsModel();
    // Starts empty
    cardsModel = [];

    // Add the cards available in settings
    for (var i = 0; i < Settings.data.controlCenter.cards.length; i++) {
      const settingCard = Settings.data.controlCenter.cards[i];

      for (var j = 0; j < cardsDefault.length; j++) {
        if (settingCard.id === cardsDefault[j].id) {
          var card = cardsDefault[j];
          card.enabled = settingCard.enabled;
          // Auto-disable weather card if weather is disabled
          if (card.id === "weather-card" && !Settings.data.location.weatherEnabled) {
            card.enabled = false;
          }
          cardsModel.push(card);
        }
      }
    }

    // Add any missing cards from default
    for (var i = 0; i < cardsDefault.length; i++) {
      var found = false;
      for (var j = 0; j < cardsModel.length; j++) {
        if (cardsModel[j].id === cardsDefault[i].id) {
          found = true;
          break;
        }
      }

      if (!found) {
        var card = cardsDefault[i];
        // Auto-disable weather card if weather is disabled
        if (card.id === "weather-card" && !Settings.data.location.weatherEnabled) {
          card.enabled = false;
        }
        cardsModel.push(card);
      }
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
      text: I18n.tr("common.cards")
      tabIndex: 1
      checked: subTabBar.currentIndex === 1
    }
    NTabButton {
      text: I18n.tr("common.shortcuts")
      tabIndex: 2
      checked: subTabBar.currentIndex === 2
    }
  }

  Item {
    Layout.fillWidth: true
    Layout.preferredHeight: Style.marginL
  }

  NTabView {
    id: tabView
    currentIndex: subTabBar.currentIndex
    Layout.fillWidth: true
    Layout.fillHeight: true

    AppearanceSubTab {}

    CardsSubTab {
      cardsModel: root.cardsModel
      cardsDefault: root.cardsDefault
    }

    ShortcutsSubTab {
      availableWidgets: availableWidgets
      captureWidgetInteraction: root.captureWidgetInteraction
      captureWidgetSettings: root.captureWidgetSettings
      onAddWidgetToSection: (widgetId, section) => _addWidgetToSection(widgetId, section)
      onRemoveWidgetFromSection: (section, index) => _removeWidgetFromSection(section, index)
      onReorderWidgetInSection: (section, fromIndex, toIndex) => _reorderWidgetInSection(section, fromIndex, toIndex)
      onUpdateWidgetSettingsInSection: (section, index, settings) => _updateWidgetSettingsInSection(section, index, settings)
      onMoveWidgetBetweenSections: (fromSection, index, toSection) => _moveWidgetBetweenSections(fromSection, index, toSection)
      onOpenPluginSettingsRequested: (manifest, settingsEntryPoint, section, index) => root._openInstanceSettings(manifest, settingsEntryPoint, section, index)
    }
  }

  // ---------------------------------
  // Signal functions
  // ---------------------------------
  function _addWidgetToSection(widgetId, section) {
    var newWidget = {
      "id": widgetId
    };
    if (ControlCenterWidgetRegistry.widgetHasUserSettings(widgetId)) {
      var metadata = ControlCenterWidgetRegistry.widgetMetadata[widgetId];
      if (metadata) {
        Object.keys(metadata).forEach(function (key) {
          newWidget[key] = metadata[key];
        });
      }
    }
    var editor = Settings.createRecordListEditor(["controlCenter", "shortcuts", section], []);
    if (!editor)
      return false;
    return editor.submit([{op: "insert", index: editor.initialValue.length, value: newWidget}], function () { editor.detach(); });
  }

  function captureWidgetInteraction(section, index) {
    var sections = [
      {id: "left", path: ["controlCenter", "shortcuts", "left"], listAddress: [], length: Settings.data.controlCenter.shortcuts.left.length},
      {id: "right", path: ["controlCenter", "shortcuts", "right"], listAddress: [], length: Settings.data.controlCenter.shortcuts.right.length}
    ];
    return SectionCommands.capture({sections: sections,
      createEditor: function (path, address, targets) { return Settings.createRecordListEditor(path, address, targets); },
      later: function (callback) { Qt.callLater(callback); }, onChanged: function () {}}, section, index);
  }

  function _submitWidgetInteraction(section, index, action, destination) {
    var interaction = root.captureWidgetInteraction(section, index);
    if (!interaction)
      return false;
    return interaction.submit(action, destination, function (result) {
      if (result.status !== "admitted" || result.refreshState !== "current")
        Logger.w("ControlCenterTab", "Widget command refused", result.error?.code || "list-edit-conflict");
      interaction.detach();
    });
  }

  function _removeWidgetFromSection(section, index) {
    return root._submitWidgetInteraction(section, index, "remove", null);
  }

  function _reorderWidgetInSection(section, fromIndex, toIndex) {
    return root._submitWidgetInteraction(section, fromIndex, "reorder", toIndex);
  }

  function _moveWidgetBetweenSections(fromSection, index, toSection) {
    return root._submitWidgetInteraction(fromSection, index, "move", toSection);
  }

  function captureWidgetSettings(section, index) {
    var commands = Settings.createRecordListEditor(["controlCenter", "shortcuts", section], []);
    if (!commands || !Number.isSafeInteger(index) || index < 0 || index >= commands.initialValue.length) {
      if (commands)
        commands.detach();
      return null;
    }
    return {
      initialValue: commands.initialValue[index],
      submit: function (fields, callback) {
        var edits = fields && typeof fields === "object" && !Array.isArray(fields) ? Object.keys(fields).filter(function (key) {
          return key !== "id";
        }).map(function (key) { return {op: "set", index: index, field: key, value: fields[key]}; }) : [];
        return commands.submit(edits, function (result) {
          if (result.status === "admitted" && result.refreshState === "current") {
            Settings.saveResult(callback);
          } else if (typeof callback === "function") {
            callback({status: "failed", error: result.error || {code: "list-edit-conflict"}});
          }
        });
      },
      detach: function () { commands.detach(); }
    };
  }

  function _updateWidgetSettingsInSection(section, index, settings) {
    var editor = root.captureWidgetSettings(section, index);
    return editor ? editor.submit(settings, function () { editor.detach(); }) : false;
  }

  // Base list model for all combo boxes
  ListModel {
    id: availableWidgets
  }

  // Opens the settings of the plugin instance at a control-center placement.
  function _openInstanceSettings(manifest, settingsEntryPoint, section, index) {
    var placement = {
      "kind": "controlCenter",
      "section": section,
      "index": index
    };
    pluginSettingsDialog.openInstanceSettings(manifest, PluginInstances.apiFor(manifest.compositeKey || manifest.id, placement), settingsEntryPoint);
  }

  // Shared Plugin Settings Popup
  NPluginSettingsPopup {
    id: pluginSettingsDialog
    parent: Overlay.overlay
    showToastOnSave: false
  }
}
