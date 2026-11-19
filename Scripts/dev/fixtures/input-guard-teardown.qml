// Actual guarded rows: deletion before a queued turn and during focus delivery.
import QtQuick
import Quickshell
import qs.Widgets

ShellRoot {
  id: root
  property int stage: 0
  property int destroyedRows: 0
  property int focusTeardowns: 0
  property bool tearDownOnFocus: false
  property bool tearDownOnSuppression: false
  property int suppressionTeardowns: 0
  readonly property Item currentRow: rows.item

  function check(ok, label) {
    if (!ok)
      throw new Error("I4_GUARD_TEARDOWN_ASSERT: " + label);
  }

  FloatingWindow {
    implicitWidth: 400
    implicitHeight: 200
    Item {
      id: survivor
      anchors.fill: parent
      Loader {
        id: rows
        active: false
        sourceComponent: guardedRow
      }
    }
  }

  Component {
    id: guardedRow
    Item {
      id: row
      width: 100
      height: 100
      onEnabledChanged: {
        if (!enabled && root.tearDownOnSuppression) {
          root.suppressionTeardowns++;
          rows.active = false;
        }
      }
      Item {
        id: edit
        onActiveFocusChanged: {
          if (activeFocus && root.tearDownOnFocus) {
            root.focusTeardowns++;
            rows.active = false;
          }
        }
      }
      NInputGuard {
        target: row
        focusTarget: edit
        focusOnActivation: true
      }
      Component.onDestruction: root.destroyedRows++
    }
  }

  Timer {
    interval: 50
    repeat: true
    running: true
    onTriggered: {
      if (!survivor.Window.active)
        return;
      try {
        if (root.stage < 16) {
          survivor.forceActiveFocus();
          rows.active = true;
          root.currentRow.visible = false;
          root.currentRow.visible = true;
          rows.active = false;
          root.stage++;
        } else if (root.stage < 32) {
          root.check(!rows.active, "previous focus-owned row was destroyed");
          root.tearDownOnFocus = true;
          survivor.forceActiveFocus();
          rows.active = true;
          root.stage++;
        } else if (root.stage < 64) {
          root.tearDownOnFocus = false;
          root.tearDownOnSuppression = true;
          if (root.stage % 2 === 0) {
            survivor.forceActiveFocus();
            rows.active = true;
          } else {
            root.currentRow.visible = false;
          }
          root.stage++;
        } else {
          root.check(root.destroyedRows === 48, "all queued and in-flight row owners destroyed");
          root.check(root.focusTeardowns === 16, "actual native focus delivery triggered teardown");
          root.check(root.suppressionTeardowns === 16, "enabled-state suppression triggered teardown");
          root.check(!rows.active, "no stale row survives");
          survivor.forceActiveFocus();
          root.check(survivor.activeFocus, "remaining consumer keeps usable focus");
          console.log("I4_GUARD_TEARDOWN: PASS");
          Qt.exit(0);
        }
      } catch (error) {
        console.error(String(error));
        Qt.exit(2);
      }
    }
  }
  Timer {
    interval: 8000
    running: true
    onTriggered: {
      console.error("I4_GUARD_TEARDOWN_ASSERT: watchdog");
      Qt.exit(2);
    }
  }
}
