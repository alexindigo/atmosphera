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

  // Use a reasonable width/height relative to parent or fixed
  width: Math.min(600 * Style.uiScaleRatio, parent.width * 0.9)
  height: Math.min(contentLayout.implicitHeight + padding * 2, parent.height * 0.9)
  padding: Style.marginL

  property string hookLabel: ""
  property string hookDescription: ""
  property string hookPlaceholder: ""
  property string initialValue: ""
  readonly property bool busy: session.busy
  readonly property bool saveFailed: session.failed
  readonly property bool discardPending: session.discardPending

  signal saved(string newValue)
  signal test(string value)

  property var _testSlot: null

  function openEditor(handle, value) {
    if (visible || session.busy)
      return false;
    initialValue = value;
    session.begin(handle, value);
    commandInput.text = value;
    open();
    return true;
  }

  function setValue(value) {
    if (!session.busy)
      commandInput.text = value;
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
    value: commandInput.text
    onAccepted: value => {
      root.saved(value);
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
    commandInput.forceActiveFocus();
  }

  contentItem: ColumnLayout {
    id: contentLayout
    spacing: Style.marginL

    // Header
    RowLayout {
      Layout.fillWidth: true
      NText {
        text: root.hookLabel
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

    // Description/Help
    NText {
      text: root.hookDescription
      color: AtmoColor.mOnSurfaceVariant
      wrapMode: Text.WordWrap
      Layout.fillWidth: true
    }

    // Input Area
    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.marginS

      NTextInput {
        id: commandInput
        enabled: !session.busy
        Layout.fillWidth: true
        placeholderText: root.hookPlaceholder
        // Allow multiline? Hooks are usually oneline commands but can be scripts.
        // NTextInput is likely single line. Let's assume single line for now as per previous implementation.
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

      NButton {
        text: I18n.tr("common.test")
        icon: Icon.caretRight
        onClicked: root.test(commandInput.text)
        // Disable test if empty? Or maybe allow testing defined script.
        enabled: !session.busy && commandInput.text !== ""
      }

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
        onClicked: root.submit(commandInput.text)
      }
    }
  }
}
