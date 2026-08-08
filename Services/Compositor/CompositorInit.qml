pragma Singleton

import QtQuick
import qs.Commons

// Compositor integration init — dispatches to the per-compositor init module.
Singleton {
  id: root

  function init() {
    if (CompositorService.isNiri) {
      NiriSessionInit.init();
    }
    // Future: Hyprland session init, etc.
  }
}
