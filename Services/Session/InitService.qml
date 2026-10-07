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

  function init(onComplete) {
    if (_initialized) {
      if (typeof onComplete === "function") BindingsService.observeStartup(onComplete);
      return;
    }
    _initialized = true;
    Logger.d("InitService", "Session init");
    // Install ownership/hold before any existing startup side effect. The
    // owner retains this initialization operation if any stage fails.
    BindingsService.init(function (environment, complete) {
      KeydService.init(environment, function (keydOk, keydError) {
        if (!keydOk) { complete(false, keydError); return; }
        XremapService.init(environment, function (xremapOk, xremapError) {
          if (!xremapOk) { complete(false, xremapError); return; }
          CompositorInit.init(environment, complete);
        });
      });
    }, onComplete);
  }
}
