// Input-method secure-mode probe (M22, case 9). Runs as the qs entry of a
// disposable shell copy made by inputmethod-regression.py, with the shell itself
// stopped, so this process is the only InputMethodService client besides fcitx5.
//
// Timeline, seconds after start. enterSecureMode() is called before fcitx5 is
// attached, so the lock is applied on attach, not at the call:
//   2  enterSecureMode()
//   5  row "entered" (the harness changes fcitx5 state while locked after this)
//  11  exitSecureMode()
//  13  row "exited", then quit
// Each row is one INPUT_METHOD_SECURE|<json> console line.
import QtQuick
import Quickshell
import qs.Services.Keyboard

Item {
  id: root

  property int tick: 0

  function publish(row) {
    console.log("INPUT_METHOD_SECURE|" + JSON.stringify(row));
  }

  function snapshot() {
    return {
      "fcitx5Available": InputMethodService.fcitx5Available,
      "secureModeActive": InputMethodService.secureModeActive,
      "active": InputMethodService.active,
      "group": InputMethodService.currentGroup,
      "im": InputMethodService.currentIM
    };
  }

  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: {
      root.tick++;
      if (root.tick === 2) {
        root.publish({
                       "phase": "call",
                       "action": "enterSecureMode"
                     });
        InputMethodService.enterSecureMode();
      } else if (root.tick === 5) {
        root.publish(Object.assign({
                                     "phase": "entered"
                                   }, root.snapshot()));
      } else if (root.tick === 11) {
        root.publish({
                       "phase": "call",
                       "action": "exitSecureMode"
                     });
        InputMethodService.exitSecureMode();
      } else if (root.tick === 13) {
        root.publish(Object.assign({
                                     "phase": "exited"
                                   }, root.snapshot()));
        Qt.exit(0);
      }
    }
  }

  Timer {
    interval: 60000
    running: true
    onTriggered: {
      root.publish({
                     "phase": "timeout"
                   });
      Qt.exit(2);
    }
  }
}
