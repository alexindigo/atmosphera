pragma Singleton

import QtQuick
import Quickshell
import qs.Commons

Singleton {
  id: root

  property bool initialized: false

  function init() {
    if (initialized)
      return;
    initialized = true;
    Logger.d("Telemetry", "Telemetry disabled (fork removed upstream endpoint)");
  }

  function getInstanceId() {
    return "";
  }
}
