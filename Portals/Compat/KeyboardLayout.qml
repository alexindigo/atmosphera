// Probes GNOME's input-source D-Bus name at startup.
// If free, claims it and exposes the current keyboard layout
// from Niri/compositor via the GNOME protocol so apps/widgets
// that hardcode org.gnome.desktop.input-sources work without GNOME.

// TODO: wire to your D-Bus library once service registration is ready

import QtQuick
import Quickshell
import qs.Services.Compositor

QtObject {
  id: root

  // Try to claim org.gnome.desktop.input-sources on init.
  // If occupied (GNOME running), do nothing.
  Component.onCompleted: {
    // DBusLibrary.tryRegisterName("org.gnome.desktop.input-sources")
    //   .onRejected(() => Logger.i("Compat", "GNOME input-sources already claimed — skipping"))
    //   .onResolved(() => {
    //       Logger.i("Compat", "Claimed org.gnome.desktop.input-sources");
    //       // Register object with the expected interface and methods
    //   });
  }
}
