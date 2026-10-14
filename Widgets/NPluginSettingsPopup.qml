import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Services.Plugins
import qs.Services.UI
import qs.Widgets

Popup {
  id: root
  modal: true
  dim: false
  anchors.centerIn: parent
  property var screen: null
  readonly property real maxHeight: (screen ? screen.height : (parent ? parent.height : 800)) * 0.8

  property real _minWidth: 600 * Style.uiScaleRatio
  width: _minWidth
  height: Math.min(settingsContent.implicitHeight + padding * 2, maxHeight)
  padding: Style.marginXL

  property var currentPlugin: null
  property var currentPluginApi: null
  // The instance api when the page edits one placed instance; null for the plugin level.
  property var currentInstanceApi: null
  readonly property bool isInstance: currentInstanceApi !== null
  property bool showToastOnSave: false

  // The loaded settings page (its saveSettings() is what Apply calls).
  readonly property var settingsPage: settingsLoader.item
  readonly property var resetButton: resetInstanceButton
  readonly property var resetConfirmation: resetInstanceDialog

  property string _settingsUrl: ""
  property string _settingsEntryPoint: "settings"

  background: Rectangle {
    color: AtmoColor.mSurface
    radius: Style.radiusL
    border.color: AtmoColor.mPrimary
    border.width: Style.borderM
  }

  contentItem: FocusScope {
    focus: true

    ColumnLayout {
      id: settingsContent
      anchors.fill: parent
      spacing: Style.marginM

      // Header
      RowLayout {
        Layout.fillWidth: true

        NText {
          text: I18n.tr("panels.plugins.plugin-settings-title", {
                          "plugin": root.currentPlugin?.name || ""
                        })
          pointSize: Style.fontSizeL
          font.weight: Style.fontWeightBold
          color: AtmoColor.mPrimary
          Layout.fillWidth: true
        }

        AtmoIconButton {
          icon: Icon.close
          tooltipText: I18n.tr("common.close")
          onClicked: root.close()
        }
      }

      NText {
        visible: root.isInstance
        text: I18n.tr("panels.plugins.instance-settings-hint")
        pointSize: Style.fontSizeS
        color: AtmoColor.mOnSurfaceVariant
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
      }

      // Separator
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: AtmoColor.mOutline
      }

      // Settings loader - pluginApi is passed via setSource() in openPluginSettings()
      NScrollView {
        id: settingsScrollView
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 100
        horizontalPolicy: ScrollBar.AlwaysOff
        gradientColor: AtmoColor.mSurface

        Loader {
          id: settingsLoader
          width: settingsScrollView.availableWidth
        }
      }

      // Action buttons
      RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Style.marginM
        spacing: Style.marginM

        Repeater {
          model: settingsLoader.item?.auxButtons || []

          delegate: NButton {
            required property var modelData
            text: modelData.text || ""
            icon: modelData.icon || ""
            outlined: true
            onClicked: {
              if (modelData.clicked)
                modelData.clicked();
            }
          }
        }

        NButton {
          id: resetInstanceButton
          visible: root.isInstance
          text: I18n.tr("panels.plugins.reset-to-plugin-settings")
          outlined: true
          onClicked: {
            if (root.isInstance)
              resetInstanceDialog.open();
          }
        }

        Item {
          Layout.fillWidth: true
        }

        NButton {
          text: I18n.tr("common.close")
          outlined: true
          onClicked: root.close()
        }

        NButton {
          text: I18n.tr("common.apply")
          icon: Icon.check
          onClicked: {
            if (settingsLoader.item && settingsLoader.item.saveSettings) {
              settingsLoader.item.saveSettings();
              if (root.showToastOnSave) {
                ToastService.showNotice(I18n.tr("panels.plugins.title"), I18n.tr("panels.plugins.settings-saved"));
              }
            }
          }
        }
      }
    }
  }

  Popup {
    id: resetInstanceDialog
    parent: root.contentItem
    modal: true
    dim: false
    anchors.centerIn: parent
    width: 400 * Style.uiScaleRatio
    padding: Style.marginL

    background: Rectangle {
      color: AtmoColor.mSurface
      radius: Style.radiusS
      border.color: AtmoColor.mPrimary
      border.width: Style.borderM
    }

    contentItem: ColumnLayout {
      spacing: Style.marginL

      NHeader {
        label: I18n.tr("panels.plugins.reset-instance-dialog-title")
        description: I18n.tr("panels.plugins.reset-instance-dialog-description")
      }

      RowLayout {
        spacing: Style.marginM
        Layout.fillWidth: true

        Item {
          Layout.fillWidth: true
        }

        NButton {
          text: I18n.tr("common.cancel")
          onClicked: resetInstanceDialog.close()
        }

        NButton {
          text: I18n.tr("common.reset")
          backgroundColor: AtmoColor.mPrimary
          textColor: AtmoColor.mOnPrimary
          onClicked: {
            root.resetInstanceSettings();
            resetInstanceDialog.close();
          }
        }
      }
    }
  }

  onClosed: {
    resetInstanceDialog.close();
    // Clear both source and sourceComponent to ensure full cleanup
    settingsLoader.sourceComponent = null;
    settingsLoader.source = "";
    currentPlugin = null;
    currentPluginApi = null;
    currentInstanceApi = null;
  }

  // Plugin level: the page edits and saves the plugin settings.
  function openPluginSettings(pluginManifest, settingsEntryPoint) {
    _open(pluginManifest, settingsEntryPoint, null);
  }

  // One placed instance: the page edits the instance api's settings (plugin
  // settings with this placement's overrides on top), and Reset drops the
  // overrides. `instanceApi` comes from PluginInstances.apiFor; null when the
  // plugin is not loaded.
  function openInstanceSettings(pluginManifest, instanceApi, settingsEntryPoint) {
    if (!instanceApi) {
      Logger.e("NPluginSettingsPopup", "Cannot open instance settings: no instance api for:", pluginManifest.compositeKey || pluginManifest.id);
      if (showToastOnSave) {
        ToastService.showError(I18n.tr("panels.plugins.title"), I18n.tr("panels.plugins.settings-error-not-loaded"));
      }
      return;
    }
    _open(pluginManifest, settingsEntryPoint, instanceApi);
  }

  function _open(pluginManifest, settingsEntryPoint, instanceApi) {
    resetInstanceDialog.close();
    currentPlugin = pluginManifest;

    // Use composite key if available (for custom plugins), otherwise use manifest ID (for official plugins)
    var pluginId = pluginManifest.compositeKey || pluginManifest.id;

    currentInstanceApi = instanceApi || null;
    currentPluginApi = instanceApi || Service.getPluginAPI(pluginId);
    if (!currentPluginApi) {
      Logger.e("NPluginSettingsPopup", "Cannot open settings: plugin not loaded:", pluginId);
      if (showToastOnSave) {
        ToastService.showError(I18n.tr("panels.plugins.title"), I18n.tr("panels.plugins.settings-error-not-loaded"));
      }
      return;
    }

    // Get plugin directory
    var pluginDir = Registry.getPluginDir(pluginId);
    _settingsEntryPoint = settingsEntryPoint || "settings";
    var settingsEntry = pluginManifest.entryPoints[_settingsEntryPoint];
    _settingsUrl = "file://" + pluginDir + "/" + settingsEntry + "?v=" + (Registry.pluginLoadVersions[pluginId] || 0);

    _loadPage();

    var preferred = (settingsLoader.item && settingsLoader.item.preferredWidth !== undefined) ? settingsLoader.item.preferredWidth + padding * 2 : 0;
    width = Math.max(preferred, _minWidth);
    open();
  }

  function _loadPage() {
    settingsLoader.setSource(_settingsUrl, PluginLoader.initialProperties(_settingsEntryPoint, _settingsUrl, currentPluginApi, {}));
  }

  // Drops the instance overrides, then reloads the page: the page keeps its own
  // copy of the values it was opened with and must read the plugin settings again.
  function resetInstanceSettings() {
    if (!currentInstanceApi)
      return;
    currentInstanceApi.resetSettings();
    settingsLoader.sourceComponent = null;
    settingsLoader.source = "";
    _loadPage();
  }
}
