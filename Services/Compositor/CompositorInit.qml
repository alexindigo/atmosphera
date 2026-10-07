pragma Singleton

import QtQuick
import Quickshell
import qs.Commons

// Compositor integration init — dispatches to the per-compositor init module.
Singleton {
  id: root

  function init(environment, onComplete) {
    if (CompositorService.isNiri) {
      NiriSessionInit.init(environment, onComplete);
    } else if (typeof onComplete === "function") {
      onComplete(true, "", false);
    }
    // Future: Hyprland session init, etc.
  }
}
