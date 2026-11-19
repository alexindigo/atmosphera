import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

Popup {
  id: root
  modal: true
  closePolicy: Popup.NoAutoClose
  dim: true
  anchors.centerIn: parent

  width: Math.min(600 * Style.uiScaleRatio, parent.width * 0.9)
  height: Math.min(contentLayout.implicitHeight + padding * 2, parent.height * 0.9)
  padding: Style.marginL

  property int editIndex: -1
  property int timeoutValue: 60
  property string commandValue: ""
  property string resumeCommandValue: ""
  property string nameValue: ""
  property bool showCommand: true
  property bool showTimeout: true
  property bool showName: false
  property string titleText: root.editIndex >= 0 ? I18n.tr("panels.idle.custom-entry-edit") : I18n.tr("panels.idle.custom-entry-new")

  signal saved(int timeout, string command, string resumeCommand, string name)

  readonly property bool busy: session.busy
  readonly property bool saveFailed: session.failed
  readonly property bool discardPending: session.discardPending

  function openEditor(handle, value, index) {
    if (visible || session.busy)
      return false;
    editIndex = index;
    setValue(value);
    session.begin(handle, session.value);
    open();
    return true;
  }

  function setValue(value) {
    if (session.busy)
      return;
    nameInput.text = value.name;
    timeoutSpinBox.value = value.timeout;
    commandInput.text = value.command;
    resumeCommandInput.text = value.resumeCommand;
  }

  function submit(value) {
    if (session.busy)
      return;
    setValue(value);
    session.apply();
  }

  function requestClose() {
    session.requestClose();
  }

  function confirmDiscard() {
    session.confirmDiscard();
  }

  function keepEditing() {
    session.discardPending = false;
  }

  NSettingsEditSession {
    id: session
    value: ({name: nameInput.text, timeout: timeoutSpinBox.value, command: commandInput.text, resumeCommand: resumeCommandInput.text})
    onAccepted: value => {
      root.saved(value.timeout, value.command, value.resumeCommand, value.name);
      root.close();
    }
    onCloseRequested: root.close()
  }

  NSettingsDiscardDialog {
    parent: root.contentItem
    visible: session.discardPending
    onDiscard: root.confirmDiscard()
    onKeepEditing: root.keepEditing()
  }

  background: Rectangle {
    color: AtmoColor.mSurface
    radius: Style.radiusL
    border.color: AtmoColor.mOutline
    border.width: Style.borderS
  }

  onOpened: {
    if (showName) {
      nameInput.forceActiveFocus();
    } else {
      timeoutSpinBox.forceActiveFocus();
    }
  }

  contentItem: ColumnLayout {
    id: contentLayout
    spacing: Style.marginL

    // Header
    RowLayout {
      Layout.fillWidth: true
      NText {
        text: root.titleText
        font.weight: Style.fontWeightBold
        pointSize: Style.fontSizeL
        Layout.fillWidth: true
      }
      AtmoIconButton {
        icon: Icon.close
        enabled: !session.busy
        onClicked: root.requestClose()
      }
    }

    // Input Area
    ColumnLayout {
      enabled: !session.busy
      Layout.fillWidth: true
      spacing: Style.marginM

      NTextInput {
        id: nameInput
        visible: root.showName
        Layout.fillWidth: true
        label: I18n.tr("panels.idle.custom-entry-name")
        placeholderText: I18n.tr("panels.idle.custom-entry-name-placeholder")
      }

      NSpinBox {
        id: timeoutSpinBox
        visible: root.showTimeout
        Layout.fillWidth: true
        label: I18n.tr("panels.idle.custom-entry-timeout")
        from: 0
        to: 86400
        suffix: "s"
      }

      NTextInput {
        id: commandInput
        visible: root.showCommand
        Layout.fillWidth: true
        label: I18n.tr("panels.idle.custom-entry-command")
        placeholderText: "notify-send \"Idle\""
        fontFamily: Settings.data.ui.fontFixed
      }

      NTextInput {
        id: resumeCommandInput
        Layout.fillWidth: true
        label: I18n.tr("panels.idle.resume-command-label")
        placeholderText: "notify-send \"Welcome back!\""
        fontFamily: Settings.data.ui.fontFixed
      }
    }

    NText {
      visible: session.failed
      text: I18n.tr("common.editor-save-failed")
      wrapMode: Text.WordWrap
      Layout.fillWidth: true
    }

    // Action Buttons
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginM

      Item {
        Layout.fillWidth: true
      } // Spacer

      NButton {
        text: I18n.tr("common.cancel")
        outlined: true
        enabled: !session.busy
        onClicked: root.requestClose()
      }

      NButton {
        text: I18n.tr("common.save")
        icon: Icon.check
        backgroundColor: AtmoColor.mPrimary
        textColor: AtmoColor.mOnPrimary
        enabled: !session.busy
        onClicked: session.apply()
      }
    }
  }
}
