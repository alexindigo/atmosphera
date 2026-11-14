import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "../../../../Helpers/RecordListEditor.js" as Lists
import "../../../../Helpers/SectionWidgetCommands.js" as SectionCommands
import qs.Commons
import qs.Services.Plugins
import qs.Services.UI
import qs.Widgets

// Monitor Widgets Configuration (inline)
NBox {
  id: root

  required property var screen
  readonly property string screenName: screen?.name || ""
  // determine bar orientation
  readonly property string barPosition: Settings.getBarPositionForScreen(screenName)
  readonly property bool barIsVertical: barPosition === "left" || barPosition === "right"

  color: AtmoColor.mSurfaceVariant
  Layout.fillWidth: true
  implicitHeight: content.implicitHeight + Style.margin2L

  // Owned editing copy. Reading or rejecting an edit must not create an override.
  function _getWidgetsContainer() {
    var currentWidgets = Settings.getBarWidgetsForScreen(screenName);
    if (!currentWidgets || typeof currentWidgets !== "object")
      return null;
    // Global widgets is a QObject namespace, not a dictionary. Snapshot its
    // three declared leaves; enumerating it also copies Qt signals as settings.
    // An existing screen record is plain data and keeps its unknown members.
    var record = currentWidgets === Settings.data.bar.widgets ? {} : currentWidgets;
    return Object.assign({}, record, {
                           "left": (currentWidgets.left || []).slice(),
                           "center": (currentWidgets.center || []).slice(),
                           "right": (currentWidgets.right || []).slice()
                         });
  }

  function _sectionAddress(name, section) {
    return [
          {
            field: "name",
            equals: name
          },
          {
            key: "widgets"
          },
          {
            key: section
          }
        ];
  }

  // A first edit carries three fenced copy commands, not display rows in an
  // insertion body. Capture is pure; only a valid complete batch creates widgets.
  function _captureListEditor(path, address, additionalLists) {
    var name = root.screenName;
    var inherited = Settings.getBarWidgetsForScreen(name) === Settings.data.bar.widgets;
    var displayed = root._getWidgetsContainer();
    if (!displayed)
      return null;
    var section = address[address.length - 1].key;
    var extra = Lists.copy(additionalLists || []);
    var destinations = [];
    ["left", "center", "right"].forEach(function (key) {
      var targetAddress = root._sectionAddress(name, key);
      var selection = Lists.stamp(targetAddress) === Lists.stamp(address) ? 0 : -1;
      for (var i = 0; i < extra.length && selection === -1; ++i) {
        if (Lists.stamp(extra[i].path) === Lists.stamp(path) && Lists.stamp(extra[i].listAddress) === Lists.stamp(targetAddress))
          selection = i + 1;
      }
      if (selection === -1) {
        extra.push({
                     path: ["bar", "screenOverrides"],
                     listAddress: targetAddress,
                     ensure: true
                   });
        selection = extra.length;
      }
      destinations.push(selection);
    });
    var firstSource = extra.length + 1;
    if (inherited) {
      extra = extra.concat([
                             {
                               path: ["bar", "widgets", "left"],
                               listAddress: []
                             },
                             {
                               path: ["bar", "widgets", "center"],
                               listAddress: []
                             },
                             {
                               path: ["bar", "widgets", "right"],
                               listAddress: []
                             }
                           ]);
    }
    var commands = Settings.createRecordListEditor(path, address, extra, {
                                                     ensure: true
                                                   });
    if (!commands)
      return null;
    var copied = false;
    var handle = {
      initialValue: inherited ? Lists.copy(displayed[section]) : commands.initialValue,
      endpoint: function (index, selection, ensure) {
        return commands.endpoint(index, selection, ensure);
      },
      target: function (selection, ensure) {
        return commands.target(selection, ensure);
      },
      isCurrent: function () {
        return root.screenName === name && (Settings.getBarWidgetsForScreen(name) === Settings.data.bar.widgets) === (inherited && !copied);
      },
      submit: function (edits, callback) {
        if (!handle.isCurrent()) {
          Qt.callLater(function () {
            if (typeof callback === "function")
              callback({
                         status: "failed",
                         error: {
                           code: "list-edit-conflict"
                         }
                       });
          });
          return false;
        }
        var prefix = inherited && !copied ? destinations.map(function (selection, index) {
          return {
            op: "copy",
            from: commands.target(firstSource + index, false),
            to: commands.target(selection)
          };
        }) : [];
        return commands.submit(prefix.concat(edits), function (result) {
          if (result.status === "admitted" && result.refreshState === "current") {
            copied = inherited || copied;
            handle.initialValue = Lists.copy(commands.initialValue);
          }
          if (typeof callback === "function")
            callback(result);
        });
      },
      detach: function () {
        commands.detach();
      }
    };
    return handle;
  }

  function captureWidgetInteraction(section, index) {
    var name = root.screenName;
    var widgets = root._getWidgetsContainer();
    if (!widgets)
      return null;
    var sections = [
          {
            id: "left",
            path: ["bar", "screenOverrides"],
            listAddress: root._sectionAddress(name, "left"),
            ensure: true,
            length: widgets.left.length
          },
          {
            id: "center",
            path: ["bar", "screenOverrides"],
            listAddress: root._sectionAddress(name, "center"),
            ensure: true,
            length: widgets.center.length
          },
          {
            id: "right",
            path: ["bar", "screenOverrides"],
            listAddress: root._sectionAddress(name, "right"),
            ensure: true,
            length: widgets.right.length
          }
        ];
    return SectionCommands.capture({
                                     sections: sections,
                                     createEditor: root._captureListEditor,
                                     later: function (callback) {
                                       Qt.callLater(callback);
                                     },
                                     onChanged: function (action, initial) {
                                       BarService.widgetsRevision++;
                                       if (action === "remove" && initial.id === "ControlCenter" && BarService.lookupWidget("ControlCenter") === undefined)
                                         ToastService.showWarning(I18n.tr("toast.missing-control-center.label"), I18n.tr("toast.missing-control-center.description"), 12000);
                                     }
                                   }, section, index);
  }

  function captureWidgetSettings(section, index) {
    var commands = root._captureListEditor(["bar", "screenOverrides"], root._sectionAddress(root.screenName, section));
    if (!commands || !Number.isSafeInteger(index) || index < 0 || index >= commands.initialValue.length)
      return null;
    return {
      initialValue: Lists.copy(commands.initialValue[index]),
      submit: function (fields, callback) {
        var edits = fields && typeof fields === "object" && !Array.isArray(fields) ? Object.keys(fields).filter(function (key) {
          return key !== "id";
        }).map(function (key) {
          return {
            op: "set",
            index: index,
            field: key,
            value: fields[key]
          };
        }) : [];
        if (!edits.length) {
          Qt.callLater(function () {
            if (typeof callback === "function")
              callback({
                         status: "failed",
                         error: {
                           code: "list-edit-input"
                         }
                       });
          });
          return false;
        }
        return commands.submit(edits, function (result) {
          if (result.status !== "admitted" || result.refreshState !== "current") {
            if (typeof callback === "function")
              callback({
                         status: "failed",
                         error: result.error || {
                           code: "list-edit-conflict"
                         }
                       });
          } else {
            Settings.saveResult(callback);
          }
        });
      },
      detach: function () {
        commands.detach();
      }
    };
  }

  function _submitWidgetInteraction(section, index, action, destination) {
    var interaction = root.captureWidgetInteraction(section, index);
    if (!interaction)
      return false;
    return interaction.submit(action, destination, function (result) {
      interaction.detach();
    });
  }

  // Widget manipulation functions
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
    var commands = root._captureListEditor(["bar", "screenOverrides"], root._sectionAddress(root.screenName, section));
    if (!commands)
      return false;
    return commands.submit([
                             {
                               op: "insert",
                               index: commands.initialValue.length,
                               value: newWidget
                             }
                           ], function (result) {
                             if (result.status === "admitted" && result.refreshState === "current")
                               BarService.widgetsRevision++;
                             commands.detach();
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
    var editor = root.captureWidgetSettings(section, index);
    return editor ? editor.submit(settings, function () {
      editor.detach();
    }) : false;
  }

  function _moveWidgetBetweenSections(fromSection, index, toSection) {
    return root._submitWidgetInteraction(fromSection, index, "move", toSection);
  }

  // Opens the settings of the plugin instance at a bar placement of this monitor.
  // The list is the one the bar draws here (PluginInstances.barList).
  function _openInstanceSettings(manifest, settingsEntryPoint, section, index) {
    var placement = {
      "kind": "bar",
      "list": PluginInstances.barList(screenName),
      "section": section,
      "index": index
    };
    pluginSettingsDialog.openInstanceSettings(manifest, PluginInstances.apiFor(manifest.compositeKey || manifest.id, placement), settingsEntryPoint);
  }

  // Available widgets ListModel
  function updateAvailableWidgetsModel() {
    availableWidgetsModel.clear();
    var widgetIds = BarWidgetRegistry.getAvailableWidgets();
    if (!widgetIds)
      return;
    for (var i = 0; i < widgetIds.length; i++) {
      var id = widgetIds[i];
      var displayName = id;
      const badges = [];
      if (BarWidgetRegistry.isPluginWidget(id)) {
        var pluginId = id.replace("plugin:", "");
        var manifest = Registry.getPluginManifest(pluginId);
        if (manifest && manifest.name) {
          displayName = manifest.name;
        } else {
          displayName = pluginId;
        }
        badges.push({
                      "color": AtmoColor.mSecondary
                    });
      }
      if (BarWidgetRegistry.isCpuIntensive(id)) {
        badges.push({
                      "color": AtmoColor.mSecondary
                    });
      }
      availableWidgetsModel.append({
                                     "key": id,
                                     "name": displayName,
                                     "badges": badges
                                   });
    }
  }

  // Plugin bar widgets can register while this panel is open
  Connections {
    target: BarWidgetRegistry
    function onPluginWidgetRegistryUpdated() {
      root.updateAvailableWidgetsModel();
    }
  }

  Component.onCompleted: Qt.callLater(updateAvailableWidgetsModel)

  ListModel {
    id: availableWidgetsModel
  }

  // Get effective widgets for this screen
  readonly property var effectiveWidgets: Settings.getBarWidgetsForScreen(screenName)

  ColumnLayout {
    id: content
    anchors.fill: parent
    anchors.margins: Style.marginL
    spacing: Style.marginM

    NText {
      text: I18n.tr("panels.bar.widgets-desc")
      wrapMode: Text.WordWrap
      Layout.fillWidth: true
    }

    // Left Section
    NSectionEditor {
      sectionName: root.barIsVertical ? I18n.tr("positions.top") : I18n.tr("positions.left")
      sectionId: "left"
      captureWidgetInteraction: root.captureWidgetInteraction
      captureWidgetSettings: root.captureWidgetSettings
      barIsVertical: root.barIsVertical
      screen: root.screen
      settingsDialogComponent: Qt.resolvedUrl(Quickshell.shellDir + "/Modules/Panels/Settings/Bar/BarWidgetSettingsDialog.qml")
      widgetRegistry: BarWidgetRegistry
      widgetModel: root.effectiveWidgets?.left || []
      availableWidgets: availableWidgetsModel
      onAddWidget: (widgetId, section) => root._addWidgetToSection(widgetId, section)
      onRemoveWidget: (section, index) => root._removeWidgetFromSection(section, index)
      onReorderWidget: (section, fromIndex, toIndex) => root._reorderWidgetInSection(section, fromIndex, toIndex)
      onUpdateWidgetSettings: (section, index, settings) => root._updateWidgetSettingsInSection(section, index, settings)
      onMoveWidget: (fromSection, index, toSection) => root._moveWidgetBetweenSections(fromSection, index, toSection)
      onOpenPluginSettingsRequested: (manifest, settingsEntryPoint, section, index) => root._openInstanceSettings(manifest, settingsEntryPoint, section, index)
    }

    // Center Section
    NSectionEditor {
      sectionName: I18n.tr("positions.center")
      sectionId: "center"
      captureWidgetInteraction: root.captureWidgetInteraction
      captureWidgetSettings: root.captureWidgetSettings
      barIsVertical: root.barIsVertical
      screen: root.screen
      settingsDialogComponent: Qt.resolvedUrl(Quickshell.shellDir + "/Modules/Panels/Settings/Bar/BarWidgetSettingsDialog.qml")
      widgetRegistry: BarWidgetRegistry
      widgetModel: root.effectiveWidgets?.center || []
      availableWidgets: availableWidgetsModel
      onAddWidget: (widgetId, section) => root._addWidgetToSection(widgetId, section)
      onRemoveWidget: (section, index) => root._removeWidgetFromSection(section, index)
      onReorderWidget: (section, fromIndex, toIndex) => root._reorderWidgetInSection(section, fromIndex, toIndex)
      onUpdateWidgetSettings: (section, index, settings) => root._updateWidgetSettingsInSection(section, index, settings)
      onMoveWidget: (fromSection, index, toSection) => root._moveWidgetBetweenSections(fromSection, index, toSection)
      onOpenPluginSettingsRequested: (manifest, settingsEntryPoint, section, index) => root._openInstanceSettings(manifest, settingsEntryPoint, section, index)
    }

    // Right Section
    NSectionEditor {
      sectionName: root.barIsVertical ? I18n.tr("positions.bottom") : I18n.tr("positions.right")
      sectionId: "right"
      captureWidgetInteraction: root.captureWidgetInteraction
      captureWidgetSettings: root.captureWidgetSettings
      barIsVertical: root.barIsVertical
      screen: root.screen
      settingsDialogComponent: Qt.resolvedUrl(Quickshell.shellDir + "/Modules/Panels/Settings/Bar/BarWidgetSettingsDialog.qml")
      widgetRegistry: BarWidgetRegistry
      widgetModel: root.effectiveWidgets?.right || []
      availableWidgets: availableWidgetsModel
      onAddWidget: (widgetId, section) => root._addWidgetToSection(widgetId, section)
      onRemoveWidget: (section, index) => root._removeWidgetFromSection(section, index)
      onReorderWidget: (section, fromIndex, toIndex) => root._reorderWidgetInSection(section, fromIndex, toIndex)
      onUpdateWidgetSettings: (section, index, settings) => root._updateWidgetSettingsInSection(section, index, settings)
      onMoveWidget: (fromSection, index, toSection) => root._moveWidgetBetweenSections(fromSection, index, toSection)
      onOpenPluginSettingsRequested: (manifest, settingsEntryPoint, section, index) => root._openInstanceSettings(manifest, settingsEntryPoint, section, index)
    }
  }

  // Plugin settings dialog
  NPluginSettingsPopup {
    id: pluginSettingsDialog
    parent: Overlay.overlay
    showToastOnSave: false
  }
}
