pragma Singleton

import Quickshell
import qs.Commons

Singleton {
  // Match the compositor facade's precedence, even before it has initialized.
  readonly property bool isNiriSession: !!Quickshell.env("NIRI_SOCKET") && !Quickshell.env("LABWC_PID") && !(Quickshell.env("XDG_CURRENT_DESKTOP") || "").toLowerCase().includes("mango")
  property bool _reported: false

  function reportUnavailable() {
    if (_reported)
      return;
    _reported = true;
    Logger.w("NiriIpc", "Niri IPC unavailable; install or upgrade qt6-niriqml to 0.3.0 or newer");
  }
}
