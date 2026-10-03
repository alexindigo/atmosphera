// Built-in catalog consumer probe (plan: post-071). Runs as the qs entry of
// a disposable shell copy with a FRESH fixture profile: the plugin system
// seeds the Built-in source, fetches the shipped registry, and builds the
// Available model — the actual consumer chain of builtin/plugins/registry.json
// (AvailableSubTab renders Service.availablePlugins).
// Prints CATALOG|AVAILABLE|[ids...] then exits; CATALOG|FAIL|<reason> on timeout.
import QtQuick
import Quickshell
import qs.Commons
import qs.Services.Plugins

Item {
  id: probe

  property int _polls: 0

  property int _readyPolls: 0

  Component.onCompleted: {
    console.log("CATALOG|START");
    // Mirror shell.qml ordering: Registry.init() first (seeds/loads
    // plugins.json asynchronously), Service.init() only once the sources
    // are actually loaded — otherwise the startup refresh fetches from
    // zero enabled sources.
    Registry.init();
    readyTimer.start();
  }

  Timer {
    id: readyTimer
    interval: 250
    repeat: true
    onTriggered: {
      probe._readyPolls++;
      if (Registry.getEnabledSources().length > 0) {
        readyTimer.stop();
        Service.init();
        pollTimer.start();
      } else if (probe._readyPolls > 120) {
        console.log("CATALOG|FAIL|registry sources never loaded");
        Qt.exit(2);
      }
    }
  }

  Timer {
    id: pollTimer
    interval: 500
    repeat: true
    onTriggered: {
      probe._polls++;
      var avail = Service.availablePlugins;
      var builtinIds = [];
      var allIds = [];
      if (avail) {
        for (var i = 0; i < avail.length; i++) {
          var p = avail[i];
          allIds.push(p.id);
          var url = (p.source && p.source.url) ? p.source.url : "";
          if (url.indexOf("/builtin/plugins") !== -1)
            builtinIds.push(p.id);
        }
      }
      // Complete when the Built-in source's fetch has landed its entries
      if (builtinIds.length > 0) {
        builtinIds.sort();
        allIds.sort();
        console.log("CATALOG|BUILTIN|" + JSON.stringify(builtinIds));
        console.log("CATALOG|AVAILABLE|" + JSON.stringify(allIds));
        Qt.exit(0);
      }
      if (probe._polls > 60) {
        console.log("CATALOG|FAIL|built-in source entries never appeared after 30s");
        Qt.exit(2);
      }
    }
  }
}
