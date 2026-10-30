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
  closePolicy: Popup.NoAutoClose
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
  readonly property bool busy: _busy
  readonly property bool saveFailed: _failed
  readonly property bool discardPending: discardDialog.visible
  readonly property bool dirty: _failed || (_pageApi && _pageApi.staged) || (settingsPage && (typeof settingsPage.settingsDirty !== "boolean" || settingsPage.settingsDirty))
  property bool _busy: false
  property bool _failed: false
  property var _editor: null
  property var _pageApi: null
  signal settingsCompleted(var result)

  Component {
    id: pageApiFactory
    PluginSettingsPageApi {}
  }

  // The loaded settings page (its saveSettings() is what Apply calls).
  readonly property var settingsPage: loadedPage()
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
    Keys.onEscapePressed: event => {
      root.requestClose();
      event.accepted = true;
    }

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
          enabled: !root.busy
          onClicked: root.requestClose()
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
          enabled: !root.busy
          width: settingsScrollView.availableWidth
        }
      }

      NText {
        visible: root.saveFailed
        text: I18n.tr("common.editor-save-failed")
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
      }

      // Action buttons
      RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Style.marginM
        spacing: Style.marginM

        Repeater {
          model: root.settingsPage?.auxButtons || []

          delegate: NButton {
            required property var modelData
            text: modelData.text || ""
            icon: modelData.icon || ""
            outlined: true
            enabled: !root.busy
            onClicked: {
              if (modelData.clicked)
                modelData.clicked();
            }
          }
        }

        NButton {
          id: resetInstanceButton
          visible: root.isInstance
          enabled: !root.busy
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
          enabled: !root.busy
          onClicked: root.requestClose()
        }

        NButton {
          text: I18n.tr("common.apply")
          icon: Icon.check
          enabled: !root.busy && root.settingsPage !== null && root._editor !== null
          onClicked: root.applySettings()
        }
      }
    }
  }

  Popup {
    id: resetInstanceDialog
    parent: root.contentItem
    modal: true
    closePolicy: Popup.NoAutoClose
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
          enabled: !root.busy
          onClicked: resetInstanceDialog.close()
        }

        NButton {
          text: I18n.tr("common.reset")
          backgroundColor: AtmoColor.mPrimary
          textColor: AtmoColor.mOnPrimary
          enabled: !root.busy
          onClicked: {
            root.resetInstanceSettings();
          }
        }
      }
    }
  }

  NSettingsDiscardDialog {
    id: discardDialog
    parent: root.contentItem
    onDiscard: root.confirmDiscard()
    onKeepEditing: root.keepEditing()
  }

  onClosed: {
    resetInstanceDialog.close();
    discardDialog.close();
    // Clear both source and sourceComponent to ensure full cleanup
    settingsLoader.sourceComponent = null;
    settingsLoader.source = "";
    if (_editor)
      _editor.discard();
    _editor = null;
    if (_pageApi)
      _pageApi.destroy();
    _pageApi = null;
    _failed = false;
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
    // A second open must never replace an existing dirty/busy page implicitly.
    if (visible || _busy)
      return false;
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

    _editor = currentPluginApi.createSettingsEditor();
    if (!_editor)
      return false;
    _pageApi = pageApiFactory.createObject(root, {
                                           base: currentPluginApi,
                                           pluginSettings: JSON.parse(JSON.stringify(_editor.initialValue))
                                         });
    _failed = false;

    // Get plugin directory
    var pluginDir = Registry.getPluginDir(pluginId);
    _settingsEntryPoint = settingsEntryPoint || "settings";
    var settingsEntry = pluginManifest.entryPoints[_settingsEntryPoint];
    _settingsUrl = "file://" + pluginDir + "/" + settingsEntry + "?v=" + (Registry.pluginLoadVersions[pluginId] || 0);

    _loadPage();

    var preferred = (settingsPage && settingsPage.preferredWidth !== undefined) ? settingsPage.preferredWidth + padding * 2 : 0;
    width = Math.max(preferred, _minWidth);
    open();
    return true;
  }

  function _loadPage() {
    settingsLoader.setSource(_settingsUrl, PluginLoader.initialProperties(_settingsEntryPoint, _settingsUrl, _pageApi, {}));
  }

  function loadedPage(): var {
    return settingsLoader.item;
  }

  // Drops the instance overrides, then reloads the page: the page keeps its own
  // copy of the values it was opened with and must read the plugin settings again.
  function resetInstanceSettings() {
    if (!currentInstanceApi || !_editor || _busy)
      return;
    _submit(true);
  }

  function applySettings() {
    if (!_editor || !settingsPage || _busy)
      return;
    // Page saveSettings is synchronous staging, never a recursive owner Apply.
    _busy = true;
    try {
      if (typeof settingsPage.saveSettings === "function")
        settingsPage.saveSettings();
      _submit(false);
    } catch (error) {
      _finish({status: "failed", refreshState: "not_refreshed", error: {code: "editor-input"}}, false);
    }
  }

  function _submit(reset) {
    _busy = true;
    _pageApi.busy = true;
    _failed = false;
    try {
      var completed = function (result) { root._finish(result, reset); };
      if (reset)
        _editor.resetOverrides(completed);
      else
        _editor.apply(JSON.parse(JSON.stringify(_pageApi.pluginSettings)), completed);
    } catch (error) {
      _finish({status: "failed", refreshState: "not_refreshed", error: {code: "editor-input"}}, reset);
    }
  }

  function _finish(result, reset) {
    var accepted = result && (result.status === "saved" || result.status === "nothing_to_save") && result.refreshState === "current";
    _failed = !accepted;
    if (accepted)
      _pageApi.pluginSettings = JSON.parse(JSON.stringify(_editor.initialValue));
    // Keep competing page actions disabled throughout receipt delivery.
    settingsCompleted(result);
    _pageApi.complete(result);
    _pageApi.busy = false;
    _busy = false;
    if (!accepted)
      return;
    if (reset) {
      resetInstanceDialog.close();
      settingsLoader.sourceComponent = null;
      settingsLoader.source = "";
      _loadPage();
    }
    if (showToastOnSave)
      ToastService.showNotice(I18n.tr("panels.plugins.title"), I18n.tr("panels.plugins.settings-saved"));
  }

  function requestClose() {
    if (_busy)
      return;
    if (dirty)
      discardDialog.open();
    else
      confirmDiscard();
  }

  function keepEditing() {
    discardDialog.close();
  }

  function confirmDiscard() {
    if (_busy || (_editor && _editor.discard() === false))
      return;
    _editor = null;
    discardDialog.close();
    close();
  }
}
