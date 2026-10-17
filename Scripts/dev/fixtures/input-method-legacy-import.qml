// Legacy i18n import probe (M24b, cases 15 and 16). Runs as the qs entry of a
// disposable shell copy made by inputmethod-regression.py, with the shell itself
// stopped, so this process is the only writer of the profile's settings.
//
// Timeline, seconds after start:
//   5  importLegacyI18n() once; the owner's own startup check has finished by
//      then (the test profile starts with legacyI18nChecked set)
//   9  quit, so the settings debounce (500 ms) has flushed to disk
// The result is one LEGACY_IMPORT|<json> console line with count and error.
// No braces before the imports: Quickshell's import scan fails on them.
import QtQuick
import Quickshell
import qs.Services.Keyboard

Item {
  id: root

  Timer {
    interval: 5000
    running: true
    onTriggered: {
      InputMethodBinds.importLegacyI18n(function (count, error) {
        console.log("LEGACY_IMPORT|" + JSON.stringify({
                                                        "count": count,
                                                        "error": error
                                                      }));
        quit.start();
      });
    }
  }

  Timer {
    id: quit
    interval: 4000
    onTriggered: Qt.exit(0)
  }

  Timer {
    interval: 60000
    running: true
    onTriggered: {
      console.log("LEGACY_IMPORT|" + JSON.stringify({
                                                      "count": -1,
                                                      "error": "timeout"
                                                    }));
      Qt.exit(2);
    }
  }
}
