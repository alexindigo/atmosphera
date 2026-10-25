import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Services.Compositor
import qs.Services.Keyboard
import qs.Services.UI

ShellRoot {
  id: root
  property bool started: false
  property bool closing: false
  property bool holdKeyboard: true
  property bool producerDestroyed: false
  property var session: null
  property var producer: null
  property double nativeReleasedAt: 0
  property double releaseRequestedAt: 0

  Component {
    id: producerFactory
    QtObject {
      property var pasteSession
      property var destroyedCallback
      function activate() {
        const kind = Quickshell.env("PASTE_KIND");
        if (kind === "text") {
          if (pasteSession)
            LauncherActionService.pasteText(Quickshell.env("PASTE_TEXT"), pasteSession);
          else
            LauncherActionService.pasteText(Quickshell.env("PASTE_TEXT"));
        }
        else
          LauncherActionService.pasteClipboard(Quickshell.env("PASTE_CLIP_ID"), kind === "image" ? "image/png" : "text/plain", pasteSession);
      }
      Component.onDestruction: destroyedCallback()
    }
  }
  function commit() {
    producer.activate();
    if (session)
      LauncherActionService.finishSession(session);
    closing = true;
    producer.destroy();
    producer = null;
    releaseDelay.start();
  }
  Timer {
    // Deliberately delayed native release is a test condition, not a product delay.
    id: releaseDelay
    interval: 600
    onTriggered: {
      root.releaseRequestedAt = Date.now();
      root.holdKeyboard = false;
    }
  }
  Timer {
    interval: 20
    repeat: true
    running: true
    onTriggered: {
      const target = CompositorService.getFocusedWindow();
      if (!target || String(target.id) !== Quickshell.env("PASTE_TARGET_ID"))
        return;
      stop();
      ClipboardService.autoWatch = false;
      ClipboardService.stopWatchers();
      if (typeof LauncherActionService.beginSession === "function")
        root.session = LauncherActionService.beginSession(Quickshell.screens[0]);
      root.producer = producerFactory.createObject(root, {pasteSession: root.session,
        destroyedCallback: () => root.producerDestroyed = true});
      root.started = true;
    }
  }
  PanelWindow {
    visible: root.started && (!root.closing || root.holdKeyboard || (root.session && !root.session.released))
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.holdKeyboard ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    Item {
      id: nativeObserver
      anchors.fill: parent
      Connections {
        target: nativeObserver.Window.window
        function onActiveChanged() {
          if (root.closing && !nativeObserver.Window.active && root.nativeReleasedAt === 0)
            root.nativeReleasedAt = Date.now();
          if (root.session && nativeObserver.Window.active)
            LauncherActionService.attachWindow(root.session, nativeObserver.Window.window);
          if (nativeObserver.Window.active && transientUi.item)
            transientUi.item.forceActiveFocus();
        }
      }
      Loader {
        id: transientUi
        focus: true
        active: !root.closing
        anchors.fill: parent
        sourceComponent: Item {
          focus: true
          Keys.onReturnPressed: event => {
            event.accepted = true;
            root.commit();
          }
        }
      }
    }
  }
  IpcHandler {
    target: "heldPaste"
    function state(): string {
      return JSON.stringify({started: root.started, closing: root.closing, active: nativeObserver.Window.active,
        hadKeyboard: root.session ? root.session.hadKeyboard : true,
        uiFocused: transientUi.item ? transientUi.item.activeFocus : false,
        producerDestroyed: root.producerDestroyed, uiDestroyed: !transientUi.item,
        holdKeyboard: root.holdKeyboard, queued: LauncherActionService.pending.length,
        clipboardReady: ClipboardService.cliphistAvailable,
        nativeReleasedAt: root.nativeReleasedAt, releaseRequestedAt: root.releaseRequestedAt});
    }
    function exitControl(): void { Qt.exit(0); }
  }
}
