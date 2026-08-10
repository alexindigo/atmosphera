pragma Singleton

import QtQuick
import Quickshell
import qs.Commons
import qs.Services.Compositor
import qs.Services.Keyboard

// Atmosphera session init seam — runs on every shell start.
// Delegates to CompositorInit; future init tasks fan out from here.
Singleton {
  id: root

  property bool _initialized: false

  function init() {
    if (_initialized)
      return;
    _initialized = true;
    Logger.d("InitService", "Session init");
    KeydService.init();
    XremapService.init();
    CompositorInit.init();
  }
}
