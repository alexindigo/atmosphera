pragma Singleton

import QtQuick
import Quickshell

Singleton {
  id: root

  // Simple signal-based notification system
  // actionLabel: optional label for clickable action link
  // actionCallback: optional function to call when action is clicked
  signal notify(string message, string description, string icon, string type, int duration, string actionLabel, var actionCallback)

  // Convenience methods
  function showNotice(message, description = "", icon = "", duration = 3000, actionLabel = "", actionCallback = null) {
    notify(message, description, icon, "notice", duration, actionLabel, actionCallback);
  }

  function showWarning(message, description = "", duration = 4000, actionLabel = "", actionCallback = null) {
    notify(message, description, "", "warning", duration, actionLabel, actionCallback);
  }

  function showError(message, description = "", duration = 6000, actionLabel = "", actionCallback = null) {
    notify(message, description, "", "error", duration, actionLabel, actionCallback);
  }
}
