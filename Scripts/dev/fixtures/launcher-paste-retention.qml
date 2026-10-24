// Private shell for launcher-paste-retention.py. Never imported by the
// production shell. A real mapped layer source holds its native keyboard
// while its committed paste ends copy-only (a new session supersedes it) and
// its producer finishes the session again on deferred destruction.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Services.UI

ShellRoot {
  id: root
  property var lease: null
  property var newer: null
  property var producer: null
  property bool closing: false
  property bool holding: true
  property int acknowledgements: 0

  Component {
    id: producerFactory
    QtObject {
      property var session
      function commit() {
        LauncherActionService.pasteText("K5 cancellation retention payload", session);
        LauncherActionService.finishSession(session);
        root.closing = true;
      }
      // Like LauncherCore: finish on close and again on destruction.
      Component.onDestruction: LauncherActionService.finishSession(session)
    }
  }

  PanelWindow {
    id: source
    screen: Quickshell.screens[0]
    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }
    color: "transparent"
    visible: !root.closing || LauncherActionService.retainsScreen(screen)
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.holding ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    Item {
      id: item
      anchors.fill: parent
    }
  }

  Component.onCompleted: {
    root.lease = LauncherActionService.beginSession(source.screen);
    root.lease.keyboardReleased.connect(() => root.acknowledgements++);
    root.producer = producerFactory.createObject(root, {
                                                   session: root.lease
                                                 });
  }
  Connections {
    target: item.Window.window
    function onActiveChanged() {
      if (root.lease && item.Window.active)
        LauncherActionService.attachWindow(root.lease, item.Window.window, source.screen);
    }
  }

  IpcHandler {
    target: "pasteRetention"
    function state(): string {
      return JSON.stringify({
                              visible: source.visible,
                              active: item.Window.active,
                              retained: LauncherActionService.retainsScreen(source.screen),
                              pending: LauncherActionService.pending.length,
                              sessions: LauncherActionService.pasteSessions.length,
                              oldAlive: !!root.lease,
                              retired: root.lease ? root.lease.retired : null,
                              released: root.lease ? root.lease.released : null,
                              hadKeyboard: root.lease ? root.lease.hadKeyboard : null,
                              queued: root.lease ? root.lease.queued : null,
                              acknowledgements: root.acknowledgements
                            });
    }
    function commit(): void {
      root.producer.commit();
    }
    function supersede(): void {
      root.newer = LauncherActionService.beginSession(source.screen);
    }
    function finishAgain(): void {
      LauncherActionService.finishSession(root.lease);
    }
    function destroyProducer(): void {
      root.producer.destroy();
      root.producer = null;
    }
    function releaseKeyboard(): void {
      root.holding = false;
    }
    function exitControl(): void {
      Qt.quit();
    }
  }
}
