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

  readonly property var currentPlugin: settingsSession.currentPlugin
  readonly property var currentPluginApi: settingsSession.currentPluginApi
  // The instance api when the page edits one placed instance; null for the plugin level.
  readonly property var currentInstanceApi: settingsSession.currentInstanceApi
  readonly property bool isInstance: settingsSession.isInstance
  property bool showToastOnSave: false
  readonly property bool busy: settingsSession.busy
  readonly property bool saveFailed: settingsSession.failed
  readonly property bool discardPending: discardDialog.visible
  readonly property bool dirty: settingsSession.dirty
  readonly property var _editor: settingsSession.editor
  readonly property var _pageApi: settingsSession.pageApi
  readonly property var undisplayedOverrideFields: settingsSession.fields ? settingsSession.fields.undisplayedOverrides : []
  signal settingsCompleted(var result)
  // The adopted presentation ends even if the native Popup never opened.
  signal presentationClosed
  property bool _presenting: false

  // Optional host-owned transition admission, injected without knowing the
  // containing tab/window/service. The returned function releases registration.
  property var registerPresentation: null
  property var _releasePresentation: null

  Connections {
    target: settingsSession
    function onEditorChanged() {
      if (settingsSession.editor && !root._releasePresentation && root.registerPresentation) {
        root._releasePresentation = root.registerPresentation(function () {
          return root.requestClose();
        });
      } else if (!settingsSession.editor) {
        root._unregisterPresentation();
      }
    }
  }

  function _unregisterPresentation() {
    var release = _releasePresentation;
    _releasePresentation = null;
    if (release)
      release();
  }
  Component.onDestruction: _unregisterPresentation()

  NSettingsInputGuard {
    id: inputEdits
    target: settingsLoader
    active: root.visible && !root.busy
  }

  PluginSettingsSession {
    id: settingsSession
    page: root.settingsPage
    presentationOpen: root.visible
    inputDirty: inputEdits.dirty
    commitInputs: function () {
      inputEdits.commit();
    }
    captureInputs: function () {
      return inputEdits.capture();
    }
    acknowledgeInputs: function (fence) {
      inputEdits.acknowledge(fence);
    }
    resetInputs: function () {
      inputEdits.reset();
    }
    onPresentRequested: {
      root._loadPage();
      var preferred = root.settingsPage && root.settingsPage.preferredWidth !== undefined ? root.settingsPage.preferredWidth + root.padding * 2 : 0;
      root.width = Math.max(preferred, root._minWidth);
      root.open();
    }
    onReloadRequested: {
      resetInstanceDialog.close();
      settingsLoader.sourceComponent = null;
      settingsLoader.source = "";
      inputEdits.reset();
      root._loadPage();
    }
    onCloseAccepted: {
      discardDialog.close();
      if (root.visible)
        root.close();
      else
        root._finishPresentation();
    }
    onDiscardRequired: discardDialog.open()
    onSettingsCompleted: result => {
      if (result?.error?.phase === "observation")
        resetInstanceDialog.close();
      root.settingsCompleted(result);
    }
    onOpeningFailed: {
      if (root.showToastOnSave)
        ToastService.showError(I18n.tr("panels.plugins.title"), I18n.tr("panels.plugins.settings-error-not-loaded"));
      root._finishPresentation();
    }
    onSaved: {
      if (root.showToastOnSave)
        ToastService.showNotice(I18n.tr("panels.plugins.title"), I18n.tr("panels.plugins.settings-saved"));
    }
  }

  // The loaded settings page (its saveSettings() is what Apply calls).
  readonly property var settingsPage: loadedPage()
  readonly property var resetButton: resetInstanceButton
  readonly property var resetConfirmation: resetInstanceDialog

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
        clip: true

        // Both host-owned override rows and plugin content share the bounded
        // scrolling region. Header, failure feedback and actions remain outside.
        ColumnLayout {
          width: settingsScrollView.availableWidth
          spacing: Style.marginM

          ColumnLayout {
            visible: root.undisplayedOverrideFields.length > 0
            Layout.fillWidth: true
            NText {
              text: I18n.tr("panels.plugins.additional-overrides")
              Layout.fillWidth: true
            }
            Repeater {
              // List models carry keys, not capability methods. Inject each
              // stable field handle from its existing owner at the delegate.
              model: root.undisplayedOverrideFields.map(function (field) {
                return field.key;
              })
              RowLayout {
                required property var modelData
                readonly property var field: settingsSession.fields.field(modelData)
                Layout.fillWidth: true
                NText {
                  Layout.fillWidth: true
                  // Never render values, including secrets, in the summary.
                  text: field.key
                }
                NButton {
                  text: I18n.tr("common.reset")
                  enabled: !root.busy && field.pendingIntent !== "reset"
                  onClicked: field.reset()
                }
              }
            }
          }

          Loader {
            id: settingsLoader
            enabled: !root.busy
            Layout.fillWidth: true
          }
        }
      }

      RowLayout {
        visible: root.saveFailed
        Layout.fillWidth: true
        spacing: Style.marginM

        NText {
          Layout.fillWidth: true
          text: I18n.tr(settingsSession.observationError === "settings-observation-draft-changed" ? "common.editor-observation-draft-changed" : (settingsSession.observationError ? "common.editor-observation-failed" : "common.editor-save-failed"))
          wrapMode: Text.WordWrap
        }

        Loader {
          active: root.saveFailed && settingsSession.observationError !== ""
          visible: active
          sourceComponent: NButton {
            objectName: "checkObservationButton"
            enabled: !root.busy
            outlined: true
            keyboardAccessible: true
            text: I18n.tr("common.check-again")
            onClicked: settingsSession.retryObservation()
          }
        }
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
          visible: root._editor !== null && root._editor.writable !== false
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
    // A native host hide or a caller using Popup.close() is not permission to
    // destroy dirty/busy input. Only the session's admitted Close clears the
    // editor first. Keep this exact loaded page through a refused hide.
    if (settingsSession.editor && !settingsSession.requestClose()) {
      var selected = settingsSession.editor;
      Qt.callLater(function () {
        if (settingsSession.editor === selected)
          root.open();
      });
      return;
    }
    _finishPresentation();
  }

  function _finishPresentation() {
    if (!_presenting)
      return;
    resetInstanceDialog.close();
    discardDialog.close();
    // Clear both source and sourceComponent to ensure full cleanup
    settingsLoader.sourceComponent = null;
    settingsLoader.source = "";
    settingsSession.presentationClosed();
    _presenting = false;
    presentationClosed();
  }

  // Plugin level: the page edits and saves the plugin settings.
  function openPluginSettings(pluginManifest, settingsEntryPoint) {
    return _openSettings(() => settingsSession.openPluginSettings(pluginManifest, settingsEntryPoint));
  }

  // One placed instance: the page edits the instance api's settings (plugin
  // settings with this placement's overrides on top), and Reset drops the
  // overrides. `instanceApi` comes from PluginInstances.apiFor; null when the
  // plugin is not loaded.
  function openInstanceSettings(pluginManifest, instanceApi, settingsEntryPoint, capturedEditor) {
    return _openSettings(() => settingsSession.openInstanceSettings(pluginManifest, instanceApi, settingsEntryPoint, capturedEditor));
  }

  function _openSettings(select) {
    if (_presenting)
      return false;
    _presenting = true;
    return select();
  }

  function _loadPage() {
    settingsLoader.setSource(settingsSession.settingsUrl, PluginLoader.initialProperties(settingsSession.settingsEntryPoint, settingsSession.settingsUrl, _pageApi, {}));
  }

  function loadedPage(): var {
    return settingsLoader.item;
  }

  // Remove declared configuration overrides through the selected session. The
  // accepted receipt reloads field presentation; content and opaque data remain.
  function resetInstanceSettings() {
    return settingsSession.resetInstanceSettings();
  }

  function applySettings() {
    return settingsSession.applySettings();
  }

  function requestClose() {
    return !_presenting || settingsSession.requestClose();
  }

  function keepEditing() {
    discardDialog.close();
  }

  function confirmDiscard() {
    return settingsSession.confirmDiscard();
  }
}
