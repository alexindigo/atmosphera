import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "../../../../Helpers/QtObj2JS.js" as QtObj2JS
import qs.Commons
import qs.Services.Noctalia
import qs.Services.UI
import qs.Widgets

// Monitor Widgets Configuration Dialog
Popup {
  id: root

  required property string screenName

  // Helper function to find screen from parent chain
  function findScreen() {
    var item = parent;
    while (item) {
      if (item.screen !== undefined) {
        return item.screen;
      }
      item = item.parent;
    }
    return null;
  }

  readonly property var screen: findScreen()
  readonly property real maxHeight: screen ? screen.height * 0.85 : (parent ? parent.height * 0.85 : 700)
  readonly property real maxWidth: screen ? screen.width * 0.6 : (parent ? parent.width * 0.6 : 600)

  width: Math.min(Math.max(content.implicitWidth + padding * 2, 500), maxWidth)
  height: Math.min(content.implicitHeight + padding * 2, maxHeight)
  padding: Style.marginXL
  modal: true
  dim: false
  anchors.centerIn: parent

  onOpened: {
    forceActiveFocus();
    updateAvailableWidgetsModel();
  }

  background: Rectangle {
    color: Color.mSurface
    radius: Style.radiusL
    border.color: Color.mPrimary
    border.width: Style.borderM
  }

  // Helper to get/set widgets for this screen
  function _getWidgetsContainer() {
    // Ensure screen has widget overrides
    if (!Settings.hasScreenOverride(screenName, "widgets")) {
      // Deep copy current widgets to create override
      var currentWidgets = Settings.getBarWidgetsForScreen(screenName);
      var widgetsCopy = QtObj2JS.qtObjectToPlainObject(currentWidgets);
      Settings.setScreenOverride(screenName, "widgets", widgetsCopy);
    }
    var entry = Settings.getScreenOverrideEntry(screenName);
    return entry ? entry.widgets : Settings.data.bar.widgets;
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
          if (key !== "allowUserSettings") {
            newWidget[key] = metadata[key];
          }
        });
      }
    }
    var widgets = _getWidgetsContainer();
    widgets[section].push(newWidget);
  }

  function _removeWidgetFromSection(section, index) {
    var widgets = _getWidgetsContainer();
    if (index >= 0 && index < widgets[section].length) {
      var newArray = widgets[section].slice();
      var removedWidgets = newArray.splice(index, 1);
      widgets[section] = newArray;

      if (removedWidgets[0].id === "ControlCenter" && BarService.lookupWidget("ControlCenter") === undefined) {
        ToastService.showWarning(I18n.tr("toast.missing-control-center.label"), I18n.tr("toast.missing-control-center.description"), 12000);
      }
    }
  }

  function _reorderWidgetInSection(section, fromIndex, toIndex) {
    var widgets = _getWidgetsContainer();
    if (fromIndex >= 0 && fromIndex < widgets[section].length && toIndex >= 0 && toIndex < widgets[section].length) {
      var newArray = widgets[section].slice();
      var item = newArray[fromIndex];
      newArray.splice(fromIndex, 1);
      newArray.splice(toIndex, 0, item);
      widgets[section] = newArray;
    }
  }

  function _updateWidgetSettingsInSection(section, index, settings) {
    var widgets = _getWidgetsContainer();
    widgets[section][index] = settings;
  }

  function _moveWidgetBetweenSections(fromSection, index, toSection) {
    var widgets = _getWidgetsContainer();
    if (index >= 0 && index < widgets[fromSection].length) {
      var widget = widgets[fromSection][index];
      var sourceArray = widgets[fromSection].slice();
      sourceArray.splice(index, 1);
      widgets[fromSection] = sourceArray;
      var targetArray = widgets[toSection].slice();
      targetArray.push(widget);
      widgets[toSection] = targetArray;
    }
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
      if (BarWidgetRegistry.isPluginWidget(id)) {
        var pluginId = id.replace("plugin:", "");
        var manifest = PluginRegistry.getPluginManifest(pluginId);
        if (manifest && manifest.name) {
          displayName = manifest.name;
        } else {
          displayName = pluginId;
        }
      }
      availableWidgetsModel.append({
                                     "key": id,
                                     "name": displayName
                                   });
    }
  }

  ListModel {
    id: availableWidgetsModel
  }

  // Get effective widgets for this screen
  readonly property var effectiveWidgets: Settings.getBarWidgetsForScreen(screenName)

  contentItem: FocusScope {
    focus: true

    ColumnLayout {
      id: content
      anchors.fill: parent
      spacing: Style.marginM

      // Title
      RowLayout {
        Layout.fillWidth: true

        NText {
          text: I18n.tr("panels.bar.monitor-widgets-title", {
                          "monitor": screenName
                        })
          pointSize: Style.fontSizeL
          font.weight: Style.fontWeightBold
          color: Color.mPrimary
          Layout.fillWidth: true
        }

        NIconButton {
          icon: "close"
          tooltipText: I18n.tr("common.close")
          onClicked: root.close()
        }
      }

      // Separator
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: Color.mOutline
      }

      // Reset to global button
      NButton {
        visible: Settings.hasScreenOverride(root.screenName, "widgets")
        text: I18n.tr("panels.bar.use-global-widgets")
        icon: "refresh"
        Layout.fillWidth: true
        onClicked: {
          Settings.clearScreenOverride(root.screenName, "widgets");
        }
      }

      // Scrollable widget sections
      NScrollView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 200

        ColumnLayout {
          width: parent.width
          spacing: Style.marginL

          NText {
            text: I18n.tr("panels.bar.widgets-desc")
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
          }

          // Left Section
          NSectionEditor {
            sectionName: I18n.tr("positions.left")
            sectionId: "left"
            settingsDialogComponent: Qt.resolvedUrl(Quickshell.shellDir + "/Modules/Panels/Settings/Bar/BarWidgetSettingsDialog.qml")
            widgetRegistry: BarWidgetRegistry
            widgetModel: root.effectiveWidgets.left
            availableWidgets: availableWidgetsModel
            onAddWidget: (widgetId, section) => root._addWidgetToSection(widgetId, section)
            onRemoveWidget: (section, index) => root._removeWidgetFromSection(section, index)
            onReorderWidget: (section, fromIndex, toIndex) => root._reorderWidgetInSection(section, fromIndex, toIndex)
            onUpdateWidgetSettings: (section, index, settings) => root._updateWidgetSettingsInSection(section, index, settings)
            onMoveWidget: (fromSection, index, toSection) => root._moveWidgetBetweenSections(fromSection, index, toSection)
            onOpenPluginSettingsRequested: manifest => pluginSettingsDialog.openPluginSettings(manifest)
          }

          // Center Section
          NSectionEditor {
            sectionName: I18n.tr("positions.center")
            sectionId: "center"
            settingsDialogComponent: Qt.resolvedUrl(Quickshell.shellDir + "/Modules/Panels/Settings/Bar/BarWidgetSettingsDialog.qml")
            widgetRegistry: BarWidgetRegistry
            widgetModel: root.effectiveWidgets.center
            availableWidgets: availableWidgetsModel
            onAddWidget: (widgetId, section) => root._addWidgetToSection(widgetId, section)
            onRemoveWidget: (section, index) => root._removeWidgetFromSection(section, index)
            onReorderWidget: (section, fromIndex, toIndex) => root._reorderWidgetInSection(section, fromIndex, toIndex)
            onUpdateWidgetSettings: (section, index, settings) => root._updateWidgetSettingsInSection(section, index, settings)
            onMoveWidget: (fromSection, index, toSection) => root._moveWidgetBetweenSections(fromSection, index, toSection)
            onOpenPluginSettingsRequested: manifest => pluginSettingsDialog.openPluginSettings(manifest)
          }

          // Right Section
          NSectionEditor {
            sectionName: I18n.tr("positions.right")
            sectionId: "right"
            settingsDialogComponent: Qt.resolvedUrl(Quickshell.shellDir + "/Modules/Panels/Settings/Bar/BarWidgetSettingsDialog.qml")
            widgetRegistry: BarWidgetRegistry
            widgetModel: root.effectiveWidgets.right
            availableWidgets: availableWidgetsModel
            onAddWidget: (widgetId, section) => root._addWidgetToSection(widgetId, section)
            onRemoveWidget: (section, index) => root._removeWidgetFromSection(section, index)
            onReorderWidget: (section, fromIndex, toIndex) => root._reorderWidgetInSection(section, fromIndex, toIndex)
            onUpdateWidgetSettings: (section, index, settings) => root._updateWidgetSettingsInSection(section, index, settings)
            onMoveWidget: (fromSection, index, toSection) => root._moveWidgetBetweenSections(fromSection, index, toSection)
            onOpenPluginSettingsRequested: manifest => pluginSettingsDialog.openPluginSettings(manifest)
          }
        }
      }

      // Close button
      RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Style.marginM

        Item {
          Layout.fillWidth: true
        }

        NButton {
          text: I18n.tr("common.close")
          onClicked: root.close()
        }
      }
    }
  }

  // Plugin settings dialog
  NPluginSettingsPopup {
    id: pluginSettingsDialog
    parent: Overlay.overlay
    showToastOnSave: false
  }
}
