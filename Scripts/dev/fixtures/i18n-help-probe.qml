// I18n help-text consumer probe (plan: post-071). Loads the actual I18n
// singleton from the tree under test and resolves the custom-button IPC
// description through the real translation path (I18n.tr) — the same call
// CustomButtonSettings.qml makes when rendering the help text.
// Language comes from the fixture config (general.language).
// Prints I18NHELP|LANG|<code> + I18NHELP|TEXT|<resolved string>, then exits.
import QtQuick
import Quickshell
import qs.Commons

Item {
  id: probe

  property bool _done: false
  // Expected language for this run ("" = system/en). Report only once the
  // settings-driven language switch has actually landed — the first
  // translationsLoaded is the pre-settings default (en), the fixture's
  // general.language arrives a tick later via onLanguageChanged.
  readonly property string expectLang: Quickshell.env("PROBE_EXPECT_LANG") || ""

  Component.onCompleted: {
    console.log("I18NHELP|START");
    checkTimer.start();
  }

  Connections {
    target: I18n
    function onTranslationsLoaded() {
      probe.report();
    }
  }

  function report() {
    if (_done)
      return;
    // Wait until settings are in and I18n's langCode matches the fixture's
    // configured language ("" in settings resolves to the system locale).
    var want = expectLang;
    var configured = "";
    try {
      configured = Settings.data.general.language || "";
    } catch (e) {}
    if (!Settings.isLoaded)
      return;
    if (configured !== "" && I18n.langCode !== configured)
      return; // settings-driven switch still pending
    if (configured === "" && want !== "" && I18n.langCode !== want)
      return;
    _done = true;
    console.log("I18NHELP|LANG|" + (I18n.langCode || "en"));
    console.log("I18NHELP|TEXT|" + I18n.tr("bar.custom-button.ipc-identifier-description"));
    Qt.exit(0);
  }

  // Poll until the report conditions land (settings in + language settled)
  Timer {
    id: checkTimer
    interval: 500
    repeat: true
    onTriggered: {
      probe._polls++;
      probe.report();
      if (probe._polls > 36 && !probe._done) {
        checkTimer.stop();
        console.log("I18NHELP|FAIL|language never settled (langCode=" + I18n.langCode + ")");
        Qt.exit(2);
      }
    }
  }

  property int _polls: 0

  Timer {
    interval: 20000
    running: true
    onTriggered: {
      console.log("I18NHELP|FAIL|timeout");
      Qt.exit(2);
    }
  }
}
