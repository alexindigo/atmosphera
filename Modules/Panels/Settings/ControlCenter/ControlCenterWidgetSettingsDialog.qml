import QtQuick
import QtQuick.Controls
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
  property var settingsCache: ({})
  property bool barIsVertical: false
  property var settingsEditor: null
  readonly property bool saveBusy: liveEdits.busy
  readonly property bool saveFailed: liveEdits.failed
  readonly property bool settingsDirty: liveEdits.dirty
  readonly property bool discardPending: discardDialog.visible

  signal updateWidgetSettings(string section, int index, var settings)
  signal settingsSaveCompleted(var result)

  readonly property real maxHeight: (screen ? screen.height : (parent ? parent.height : 800)) * 0.8
  readonly property real defaultContentWidth: Math.round(600 * Style.uiScaleRatio)
  function _settingsPage(): var {
    return settingsLoader.item;
  }
  readonly property real settingsContentWidth: {
    var page = root._settingsPage();
    if (page && page.implicitWidth > 0) {
      return page.implicitWidth;
    }
    return defaultContentWidth;
  }

  readonly property real dialogPadding: Style.marginXL
  width: Math.max(settingsContentWidth + scrollView.leftPadding + scrollView.rightPadding + dialogPadding * 2, 500)
  height: Math.min(content.implicitHeight + dialogPadding * 2, maxHeight)
  padding: 0
  modal: true
  closePolicy: Popup.NoAutoClose
  anchors.centerIn: parent

  onOpened: {
    if (widgetData && widgetId) {
      loadWidgetSettings();
    }
  }

  background: Rectangle {
    color: AtmoColor.mSurface
    radius: Style.radiusL
    border.color: AtmoColor.mPrimary
    border.width: Style.borderM
  }

  contentItem: ColumnLayout {
    id: content
    anchors.fill: parent
    anchors.margins: dialogPadding
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

      Item {
        Layout.preferredWidth: closeButton.implicitWidth
        Layout.preferredHeight: closeButton.implicitHeight
        AtmoIconButton {
          id: closeButton
          anchors.fill: parent
          icon: Icon.close
          tooltipText: I18n.tr("common.close")
          visible: !root.saveBusy
          onClicked: saveAndClose()
        }
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
        visible: !root.saveBusy
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

        Loader {
          id: settingsLoader
          Layout.fillWidth: true
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
    function onSettingsChanged(newSettings) {
      root.queueSettings(newSettings);
    }
  }

  function saveAndClose() {
    if (saveBusy)
      return;
    inputEdits.commit();
    var page = root._settingsPage();
    if (page && typeof page.saveSettings === 'function') {
      var newSettings = page.saveSettings();
      if (newSettings) {
        root.queueSettings(newSettings);
      }
    }
    liveEdits.saveAndClose();
  }

  function loadWidgetSettings() {
    const widgetSettingsMap = {
      "CustomButton": "WidgetSettings/CustomButtonSettings.qml"
    };

    const source = widgetSettingsMap[widgetId];
    if (source) {
      settingsLoader.setSource(source, {
                                 "widgetData": widgetData,
                                 "widgetMetadata": ControlCenterWidgetRegistry.widgetMetadata[widgetId]
                               });
    }
  }
}
