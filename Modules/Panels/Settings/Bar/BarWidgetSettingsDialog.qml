import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import qs.Commons
import qs.Services.UI
import qs.Widgets

// Widget Settings Dialog Component
Popup {
  id: root

  property int widgetIndex: -1
  property var widgetData: null
  property string widgetId: ""
  property string sectionId: ""
  property var screen: null
  property bool barIsVertical: false
  property var settingsEditor: null
  readonly property bool saveBusy: liveEdits.busy
  readonly property bool saveFailed: liveEdits.failed
  readonly property bool settingsDirty: liveEdits.dirty
  readonly property bool discardPending: discardDialog.visible

  signal settingsSaveCompleted(var result)

  readonly property real maxHeight: (screen ? screen.height : (parent ? parent.height : 800)) * 0.8

  signal updateWidgetSettings(string section, int index, var settings)

  width: Math.max(content.implicitWidth + padding * 2, 640)
  height: Math.min(content.implicitHeight + padding * 2, maxHeight)
  padding: Style.marginXL
  modal: true
  closePolicy: Popup.NoAutoClose
  dim: false
  anchors.centerIn: parent

  onOpened: {
    // Load settings when popup opens with data
    if (widgetData && widgetId) {
      loadWidgetSettings();
    }
    // Request focus to ensure keyboard input works
    forceActiveFocus();
  }

  background: Rectangle {
    id: bgRect

    color: AtmoColor.mSurface
    radius: Style.radiusL
    border.color: AtmoColor.mPrimary
    border.width: Style.borderM
  }

  contentItem: FocusScope {
    id: focusScope
    focus: true

    ColumnLayout {
      id: content
      anchors.fill: parent
      spacing: Style.marginM

      // Title
      RowLayout {
        id: titleRow
        Layout.fillWidth: true
        Layout.preferredHeight: implicitHeight

        NText {
          text: I18n.tr("system.widget-settings-title", {
                          "widget": root.widgetId
                        })
          pointSize: Style.fontSizeL
          font.weight: Style.fontWeightBold
          color: AtmoColor.mPrimary
          Layout.fillWidth: true
        }

        AtmoIconButton {
          icon: Icon.close
          tooltipText: I18n.tr("common.close")
          enabled: !root.saveBusy
          onClicked: saveAndClose()
        }
      }

      // Separator
      Rectangle {
        id: separator
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: AtmoColor.mOutline
      }

      RowLayout {
        visible: root.saveFailed
        Layout.fillWidth: true
        NText {
          text: I18n.tr("common.editor-save-failed")
          color: AtmoColor.mError
          wrapMode: Text.WordWrap
          Layout.fillWidth: true
        }
        NButton {
          text: I18n.tr("common.discard")
          enabled: !root.saveBusy
          onClicked: root.requestDiscard()
        }
      }

      // Scrollable settings area
      NScrollView {
        id: scrollView
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 100
        gradientColor: AtmoColor.mSurface

        ColumnLayout {
          width: scrollView.availableWidth
          spacing: Style.marginM

          // Settings based on widget type
          // Will be triggered via settingsLoader.setSource()
          Loader {
            id: settingsLoader
            Layout.fillWidth: true
            onLoaded: {
              // Try to focus the first focusable item in the loaded settings
              if (item) {
                Qt.callLater(() => {
                  var firstInput = findFirstFocusable(item);
                  if (firstInput) {
                    firstInput.forceActiveFocus();
                  } else {
                    focusScope.forceActiveFocus();
                  }
                });
              }
            }

            function findFirstFocusable(item) {
              if (!item)
                return null;
              // Check if this item can accept focus
              if (item.focus !== undefined && item.focus === true)
                return item;
              // Check children
              if (item.children) {
                for (var i = 0; i < item.children.length; i++) {
                  var child = item.children[i];
                  if (child && child.focus !== undefined && child.focus === true)
                    return child;
                  var found = findFirstFocusable(child);
                  if (found)
                    return found;
                }
              }
              return null;
            }
          }
        }
      }
    }
  }

  NLiveSettingsEditSession {
    id: liveEdits
    inputGuard: inputEdits
    editor: root.settingsEditor || {
              submit: function (fields, callback) {
                root.updateWidgetSettings(root.sectionId, root.widgetIndex, fields);
                Settings.saveResult(callback);
              }
            }
    onCompleted: result => root.settingsSaveCompleted(result)
    onCloseRequested: root.close()
  }

  NSettingsDiscardDialog {
    id: discardDialog
    parent: root.parent
    onDiscard: root.confirmDiscard()
    onKeepEditing: root.keepEditing()
  }

  NSettingsInputGuard {
    id: inputEdits
    target: settingsLoader
    active: root.visible && !root.saveBusy
  }

  function requestDiscard() {
    if (!saveBusy && settingsDirty)
      discardDialog.open();
  }

  function keepEditing() {
    discardDialog.close();
  }

  function confirmDiscard() {
    if (saveBusy || !discardDialog.visible)
      return false;
    discardDialog.close();
    return liveEdits.confirmDiscard();
  }

  function queueSettings(fields) {
    return liveEdits.queue(fields);
  }

  Connections {
    target: settingsLoader.item
    ignoreUnknownSignals: true
    function onSettingsChanged(fields) {
      root.queueSettings(fields);
    }
  }

  function saveAndClose() {
    if (saveBusy)
      return;
    inputEdits.commit();
    if (settingsLoader.item && typeof settingsLoader.item.saveSettings === "function") {
      var fields = settingsLoader.item.saveSettings();
      if (fields)
        root.queueSettings(fields);
    }
    liveEdits.saveAndClose();
  }

  function loadWidgetSettings() {
    const source = BarWidgetRegistry.widgetSettingsMap[widgetId];
    if (source) {
      settingsLoader.setSource(source, {
                                 "screen": screen,
                                 "widgetData": widgetData,
                                 "widgetMetadata": BarWidgetRegistry.widgetMetadata[widgetId]
                               });
    }
  }
}
