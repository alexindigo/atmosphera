import QtQuick

// Owned by the durable action service, never by the closing launcher/provider.
QtObject {
  id: root
  property var screen: null
  property var targetId: null
  property var sourceWindow: null
  property int queued: 0
  property bool closeRequested: false
  property bool hadKeyboard: false
  property bool released: false
  property bool retired: false
  readonly property bool nativeActive: sourceWindow ? sourceWindow.active : false
  signal keyboardReleased(bool sourceWasVisible)

  onNativeActiveChanged: {
    if (nativeActive)
      hadKeyboard = true;
    checkRelease();
  }
  onCloseRequestedChanged: checkRelease()

  function checkRelease() {
    // A local hide/destruction can also deactivate a QWindow. It is not an
    // acknowledgement: the host must stay mapped while relinquishing keys.
    if (!released && closeRequested && hadKeyboard && sourceWindow && sourceWindow.visible && !nativeActive) {
      const sourceWasVisible = sourceWindow.visible;
      released = true;
      keyboardReleased(sourceWasVisible);
    }
  }
}
