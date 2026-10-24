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
  // When the launcher's native keyboard release was acknowledged (ms)
  property double releasedAt: 0
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
      releasedAt = Date.now();
      released = true;
      keyboardReleased(sourceWasVisible);
    }
  }
}
